package proto

import (
	"encoding/json"
	"testing"
)

func TestTerminalIDRoundTrip(t *testing.T) {
	d := TerminalDescriptor{WorkspaceID: "WS", SurfaceID: "SF", Title: "shell"}
	id := d.TerminalID("SESS")
	if id != "SESS:terminal:WS:SF" {
		t.Fatalf("unexpected terminal id: %q", id)
	}
	sess, ws, sf, ok := ParseTerminalID(id)
	if !ok || sess != "SESS" || ws != "WS" || sf != "SF" {
		t.Fatalf("parse mismatch: %q %q %q %v", sess, ws, sf, ok)
	}
	if _, _, _, ok := ParseTerminalID("nope"); ok {
		t.Fatal("expected parse failure on malformed id")
	}
}

func TestEnvelopeBroadcastVsTargeted(t *testing.T) {
	// Absent recipient list = broadcast.
	env, err := DecodeEnvelope([]byte(`{"type":"terminal.output","dataBase64":"aGk="}`))
	if err != nil {
		t.Fatal(err)
	}
	if env.HasRecipients {
		t.Fatal("absent recipient list should be broadcast")
	}
	if !env.AddressedTo("anyone") {
		t.Fatal("broadcast frame should address everyone")
	}

	// Explicit empty list = deliver to nobody.
	env, err = DecodeEnvelope([]byte(`{"type":"terminal.output","recipientParticipantIDs":[]}`))
	if err != nil {
		t.Fatal(err)
	}
	if !env.HasRecipients {
		t.Fatal("empty list should be recognized as explicit recipients")
	}
	if env.AddressedTo("anyone") {
		t.Fatal("empty recipient list should address nobody")
	}

	// Targeted list.
	env, _ = DecodeEnvelope([]byte(`{"type":"terminal.input","recipientParticipantIDs":["alice","bob"]}`))
	if !env.AddressedTo("bob") || env.AddressedTo("carol") {
		t.Fatal("targeting mismatch")
	}
}

func TestEnvelopeRejectsMissingType(t *testing.T) {
	if _, err := DecodeEnvelope([]byte(`{"dataBase64":"x"}`)); err == nil {
		t.Fatal("expected error for frame without type")
	}
	if _, err := DecodeEnvelope([]byte(`not json`)); err == nil {
		t.Fatal("expected error for invalid json")
	}
}

func TestEnvelopeDecodeTyped(t *testing.T) {
	raw := `{"type":"terminal.output","terminalID":"T","sequence":42,"dataBase64":"aGVsbG8=","fromPeerID":"host"}`
	env, err := DecodeEnvelope([]byte(raw))
	if err != nil {
		t.Fatal(err)
	}
	if env.Type != TypeTerminalOutput || env.FromPeerID != "host" {
		t.Fatalf("envelope metadata wrong: %+v", env)
	}
	var out TerminalOutput
	if err := env.Decode(&out); err != nil {
		t.Fatal(err)
	}
	if out.Sequence != 42 || out.DataBase64 != "aGVsbG8=" {
		t.Fatalf("typed decode wrong: %+v", out)
	}
}

func TestPeerEffectiveParticipantID(t *testing.T) {
	if got := (Peer{PeerID: "p"}).EffectiveParticipantID(); got != "p" {
		t.Fatalf("want peerID fallback, got %q", got)
	}
	if got := (Peer{PeerID: "p", ParticipantID: "part"}).EffectiveParticipantID(); got != "part" {
		t.Fatalf("want participantID, got %q", got)
	}
}

func TestFrameMarshalsWithoutEmptyRecipients(t *testing.T) {
	// omitempty must keep recipientParticipantIDs off the wire when nil, so a
	// broadcast frame stays a broadcast (nil != empty-array semantics).
	data, _ := json.Marshal(TerminalOutput{Type: TypeTerminalOutput, TerminalID: "T", DataBase64: "x"})
	if got := string(data); contains(got, "recipientParticipantIDs") {
		t.Fatalf("nil recipients should be omitted: %s", got)
	}
}

func contains(s, sub string) bool {
	for i := 0; i+len(sub) <= len(s); i++ {
		if s[i:i+len(sub)] == sub {
			return true
		}
	}
	return false
}
