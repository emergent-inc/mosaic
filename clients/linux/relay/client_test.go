package relay_test

import (
	"context"
	"testing"
	"time"

	"github.com/emergent-inc/mosaic/clients/linux/proto"
	"github.com/emergent-inc/mosaic/clients/linux/relay"
	"github.com/emergent-inc/mosaic/clients/linux/relay/relaytest"
)

func TestNormalizeSessionCode(t *testing.T) {
	cases := map[string]string{
		"5z-nh":     "5ZNH",
		"5ZNH GF9P": "5ZNHGF9P",
		"abcd":      "ABCD",
		"a2c4e":     "A2C4E",
	}
	for in, want := range cases {
		got, err := relay.NormalizeSessionCode(in)
		if err != nil || got != want {
			t.Errorf("normalize(%q) = %q, %v; want %q", in, got, err, want)
		}
	}
	if _, err := relay.NormalizeSessionCode("abc"); err == nil {
		t.Error("expected error for 3-char code")
	}
}

func dial(t *testing.T, srv *relaytest.Server, code, name, participant string) *relay.Conn {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	conn, err := relay.Dial(ctx, srv.URL, code, proto.Peer{
		PeerID:        relay.NewPeerID(),
		ParticipantID: participant,
		DisplayName:   name,
		Color:         "#7A5CFF",
	})
	if err != nil {
		t.Fatalf("dial %s: %v", name, err)
	}
	t.Cleanup(func() { conn.Close() })
	return conn
}

func waitFrame(t *testing.T, conn *relay.Conn, want string) proto.Envelope {
	t.Helper()
	timeout := time.After(3 * time.Second)
	for {
		select {
		case env, ok := <-conn.Frames():
			if !ok {
				t.Fatalf("connection closed waiting for %q: %v", want, conn.Err())
			}
			if env.Type == want {
				return env
			}
		case <-timeout:
			t.Fatalf("timeout waiting for %q", want)
		}
	}
}

func TestJoinCreateAndRoster(t *testing.T) {
	srv := relaytest.New()
	defer srv.Close()

	ctx := context.Background()
	code, err := relay.CreateSession(ctx, srv.URL)
	if err != nil {
		t.Fatal(err)
	}

	host := dial(t, srv, code, "host", "part-host")
	if host.SessionID != code {
		t.Fatalf("session id = %q, want %q", host.SessionID, code)
	}

	viewer := dial(t, srv, code, "viewer", "part-viewer")
	_ = viewer

	// Host should observe the viewer joining.
	env := waitFrame(t, host, proto.TypePeerJoined)
	var joined proto.PeerJoined
	if err := env.Decode(&joined); err != nil {
		t.Fatal(err)
	}
	if joined.Peer.DisplayName != "viewer" {
		t.Fatalf("unexpected peer.joined: %+v", joined.Peer)
	}
	if len(host.Peers()) != 1 {
		t.Fatalf("host roster = %d, want 1", len(host.Peers()))
	}
}

func TestUnknownRoomFails(t *testing.T) {
	srv := relaytest.New()
	defer srv.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()
	_, err := relay.Dial(ctx, srv.URL, "ZZZZZZZZ", proto.Peer{
		PeerID: relay.NewPeerID(), DisplayName: "x", Color: "#fff",
	})
	if err == nil {
		t.Fatal("expected join to fail for unknown room")
	}
}

func TestTerminalOutputAndInputRoundTrip(t *testing.T) {
	srv := relaytest.New()
	defer srv.Close()
	srv.CreateRoom("ROOM0001")

	host := dial(t, srv, "ROOM0001", "host", "part-host")
	viewer := dial(t, srv, "ROOM0001", "viewer", "part-viewer")
	// Ensure the host has seen the viewer before targeting it.
	waitFrame(t, host, proto.TypePeerJoined)

	ctx := context.Background()
	descriptor := proto.TerminalDescriptor{WorkspaceID: "WS", SurfaceID: "SF", Title: "bash"}
	termID := descriptor.TerminalID(host.SessionID)

	// Host shares a terminal targeted at the viewer's participantID.
	if err := host.Send(ctx, proto.TerminalOpen{
		Type: proto.TypeTerminalOpen, TerminalID: termID, Descriptor: descriptor,
		FromPeerID: "host", RecipientParticipantIDs: []string{"part-viewer"},
	}); err != nil {
		t.Fatal(err)
	}
	open := waitFrame(t, viewer, proto.TypeTerminalOpen)
	if !open.AddressedTo("part-viewer") {
		t.Fatal("viewer should be addressed by the terminal.open")
	}

	// Host streams output.
	if err := host.Send(ctx, proto.TerminalOutput{
		Type: proto.TypeTerminalOutput, TerminalID: termID, Sequence: 0,
		DataBase64: "aGVsbG8=", FromPeerID: "host",
		RecipientParticipantIDs: []string{"part-viewer"},
	}); err != nil {
		t.Fatal(err)
	}
	out := waitFrame(t, viewer, proto.TypeTerminalOutput)
	var output proto.TerminalOutput
	if err := out.Decode(&output); err != nil {
		t.Fatal(err)
	}
	if output.DataBase64 != "aGVsbG8=" {
		t.Fatalf("output mismatch: %+v", output)
	}

	// Viewer sends input back.
	if err := viewer.Send(ctx, proto.TerminalInput{
		Type: proto.TypeTerminalInput, TerminalID: termID, InputID: "i1",
		DataBase64: "bHM=", FromPeerID: "viewer",
	}); err != nil {
		t.Fatal(err)
	}
	in := waitFrame(t, host, proto.TypeTerminalInput)
	var input proto.TerminalInput
	if err := in.Decode(&input); err != nil {
		t.Fatal(err)
	}
	if input.DataBase64 != "bHM=" {
		t.Fatalf("input mismatch: %+v", input)
	}
}

func TestRecipientTargetingExcludesNonSelected(t *testing.T) {
	srv := relaytest.New()
	defer srv.Close()
	srv.CreateRoom("ROOM0002")

	host := dial(t, srv, "ROOM0002", "host", "part-host")
	alice := dial(t, srv, "ROOM0002", "alice", "part-alice")
	bob := dial(t, srv, "ROOM0002", "bob", "part-bob")
	// Let the host register both viewers.
	waitFrame(t, host, proto.TypePeerJoined)
	waitFrame(t, host, proto.TypePeerJoined)

	ctx := context.Background()
	termID := "ROOM0002:terminal:WS:SF"

	// Output targeted only at alice.
	if err := host.Send(ctx, proto.TerminalOutput{
		Type: proto.TypeTerminalOutput, TerminalID: termID,
		DataBase64: "eA==", FromPeerID: "host",
		RecipientParticipantIDs: []string{"part-alice"},
	}); err != nil {
		t.Fatal(err)
	}
	waitFrame(t, alice, proto.TypeTerminalOutput) // alice receives it

	// bob must NOT receive the targeted output; he should only see a
	// subsequent broadcast. Send a broadcast marker and assert bob's first
	// terminal frame is the broadcast, not the alice-targeted one.
	if err := host.Send(ctx, proto.TerminalOutput{
		Type: proto.TypeTerminalOutput, TerminalID: termID,
		DataBase64: "eQ==", FromPeerID: "host", // no recipients = broadcast
	}); err != nil {
		t.Fatal(err)
	}
	env := waitFrame(t, bob, proto.TypeTerminalOutput)
	var out proto.TerminalOutput
	_ = env.Decode(&out)
	if out.DataBase64 != "eQ==" {
		t.Fatalf("bob received a frame he was not targeted for: %+v", out)
	}
}

func TestHeartbeatNotForwarded(t *testing.T) {
	srv := relaytest.New()
	defer srv.Close()
	srv.CreateRoom("ROOM0003")

	host := dial(t, srv, "ROOM0003", "host", "part-host")
	viewer := dial(t, srv, "ROOM0003", "viewer", "part-viewer")
	waitFrame(t, host, proto.TypePeerJoined)

	ctx := context.Background()
	if err := viewer.Send(ctx, proto.NewHeartbeat()); err != nil {
		t.Fatal(err)
	}
	// Follow the heartbeat with a terminal frame; the host must see the
	// terminal frame and never a heartbeat.
	if err := viewer.Send(ctx, proto.TerminalInput{
		Type: proto.TypeTerminalInput, TerminalID: "ROOM0003:terminal:WS:SF",
		InputID: "i", DataBase64: "eg==", FromPeerID: "viewer",
	}); err != nil {
		t.Fatal(err)
	}
	timeout := time.After(3 * time.Second)
	for {
		select {
		case env, ok := <-host.Frames():
			if !ok {
				t.Fatal("host connection closed")
			}
			if env.Type == proto.TypePeerHeartbeat {
				t.Fatal("heartbeat should not be forwarded")
			}
			if env.Type == proto.TypeTerminalInput {
				return
			}
		case <-timeout:
			t.Fatal("timeout waiting for terminal.input")
		}
	}
}
