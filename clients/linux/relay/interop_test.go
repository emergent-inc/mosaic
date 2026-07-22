package relay_test

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/emergent-inc/mosaic/clients/linux/proto"
	"github.com/emergent-inc/mosaic/clients/linux/relay"
)

// TestRealRelayRoundTrip exercises the client against the DEPLOYED Mosaic
// collaboration relay (a third-party Cloudflare worker), not the in-process
// double. It is skipped unless MOSAIC_INTEROP=1 so CI and offline runs stay
// hermetic. It creates one ephemeral room, joins with two clients, and
// round-trips a terminal.output + terminal.input frame — the single test that
// proves this client actually interoperates with real Mosaic infrastructure.
func TestRealRelayRoundTrip(t *testing.T) {
	if os.Getenv("MOSAIC_INTEROP") != "1" {
		t.Skip("set MOSAIC_INTEROP=1 to test against the real relay")
	}
	base := os.Getenv("MOSAIC_RELAY_URL")
	if base == "" {
		base = relay.DefaultRelayURL
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	code, err := relay.CreateSession(ctx, base)
	if err != nil {
		t.Fatalf("create session on real relay: %v", err)
	}
	t.Logf("created room %s on %s", code, base)

	host, err := relay.Dial(ctx, base, code, proto.Peer{
		PeerID: relay.NewPeerID(), ParticipantID: "interop-host",
		DisplayName: "interop-host", Color: "#7A5CFF",
	})
	if err != nil {
		t.Fatalf("host dial: %v", err)
	}
	defer host.Close()

	viewer, err := relay.Dial(ctx, base, code, proto.Peer{
		PeerID: relay.NewPeerID(), ParticipantID: "interop-viewer",
		DisplayName: "interop-viewer", Color: "#0A84FF",
	})
	if err != nil {
		t.Fatalf("viewer dial: %v", err)
	}
	defer viewer.Close()

	// Host observes the viewer join.
	waitFrame(t, host, proto.TypePeerJoined)

	termID := "interop:terminal:WS:SF"
	// Broadcast (no recipient list) so we don't depend on targeting details.
	if err := host.Send(ctx, proto.TerminalOutput{
		Type: proto.TypeTerminalOutput, TerminalID: termID,
		DataBase64: "aW50ZXJvcA==", FromPeerID: "interop-host", // "interop"
	}); err != nil {
		t.Fatal(err)
	}
	out := waitFrame(t, viewer, proto.TypeTerminalOutput)
	var output proto.TerminalOutput
	if err := out.Decode(&output); err != nil {
		t.Fatal(err)
	}
	if output.DataBase64 != "aW50ZXJvcA==" {
		t.Fatalf("real relay mangled the output frame: %+v", output)
	}
	if out.FromPeerID == "" {
		t.Error("real relay did not stamp fromPeerID (protocol assumption wrong)")
	}

	// Viewer input reaches the host.
	if err := viewer.Send(ctx, proto.TerminalInput{
		Type: proto.TypeTerminalInput, TerminalID: termID, InputID: "i1",
		DataBase64: "eA==", FromPeerID: "interop-viewer",
	}); err != nil {
		t.Fatal(err)
	}
	in := waitFrame(t, host, proto.TypeTerminalInput)
	var input proto.TerminalInput
	_ = in.Decode(&input)
	if input.DataBase64 != "eA==" {
		t.Fatalf("real relay mangled the input frame: %+v", input)
	}
	t.Log("real-relay round-trip OK: create + join x2 + output + input")
}
