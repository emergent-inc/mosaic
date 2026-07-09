// Package proto mirrors the Mosaic collaboration relay wire schema.
//
// The schema is defined by the Swift Codable structs in
// Sources/CollaborationRuntime.swift and enforced (loosely) by
// workers/collaboration/src/protocol.ts. All frames are JSON text WebSocket
// messages with a required string "type" discriminator; the relay forwards
// unknown types opaquely, adding "fromPeerID" and "receivedAt". Terminal
// frames may carry "recipientParticipantIDs" to target delivery; an absent
// field means broadcast, an empty array means deliver to nobody.
package proto

import (
	"encoding/json"
	"fmt"
	"strings"
)

// Frame type discriminators understood by this client. The relay itself only
// interprets peer.heartbeat and peer.update; everything else is peer-to-peer.
const (
	TypeSessionJoined     = "session.joined"
	TypePeerJoined        = "peer.joined"
	TypePeerUpdate        = "peer.update"
	TypePeerLeft          = "peer.left"
	TypePeerHeartbeat     = "peer.heartbeat"
	TypeTerminalOpen      = "terminal.open"
	TypeTerminalOutput    = "terminal.output"
	TypeTerminalInput     = "terminal.input"
	TypeTerminalDims      = "terminal.dimensions"
	TypeTerminalGrid      = "terminal.render_grid"
	TypeTerminalGridReq   = "terminal.render_grid.request"
	TypeTerminalPointer   = "terminal.pointer"
	TypeTerminalSelection = "terminal.selection"
	TypeTerminalClose     = "terminal.close"
)

// MaxFrameBytes is the relay's hard envelope cap (protocol.ts parseEnvelope
// rejects anything larger and closes the socket with 1003).
const MaxFrameBytes = 1 << 20

// Peer is the roster entry shared in session.joined / peer.joined /
// peer.update frames (Swift: CollaborationPeerWire).
type Peer struct {
	PeerID        string `json:"peerID"`
	ParticipantID string `json:"participantID,omitempty"`
	DisplayName   string `json:"displayName"`
	Color         string `json:"color"`
	ImageURL      string `json:"imageURL,omitempty"`
}

// EffectiveParticipantID returns the participant identity used for terminal
// recipient targeting; the relay defaults it to the peerID when absent.
func (p Peer) EffectiveParticipantID() string {
	if p.ParticipantID != "" {
		return p.ParticipantID
	}
	return p.PeerID
}

// SessionJoined is the relay's join acknowledgement, sent immediately after
// the WebSocket is accepted. If it does not arrive promptly the join must be
// treated as failed.
type SessionJoined struct {
	Type      string `json:"type"`
	SessionID string `json:"sessionID"`
	Peers     []Peer `json:"peers"`
}

// PeerJoined announces another peer entering the room.
type PeerJoined struct {
	Type string `json:"type"`
	Peer Peer   `json:"peer"`
}

// PeerUpdate announces a peer identity change; the relay validates that the
// inner peerID matches the sender.
type PeerUpdate struct {
	Type string `json:"type"`
	Peer Peer   `json:"peer"`
}

// PeerLeft announces a peer disconnecting or timing out.
type PeerLeft struct {
	Type   string `json:"type"`
	PeerID string `json:"peerID"`
	Reason string `json:"reason,omitempty"`
}

// Heartbeat keeps the relay from sweeping the peer (30s server timeout; the
// macOS client sends one every 20s). Not forwarded to other peers.
type Heartbeat struct {
	Type string `json:"type"`
}

// NewHeartbeat returns a ready-to-send heartbeat frame.
func NewHeartbeat() Heartbeat { return Heartbeat{Type: TypePeerHeartbeat} }

// TerminalDescriptor identifies the host surface behind a shared terminal
// (Swift: SharedTerminalDescriptor).
type TerminalDescriptor struct {
	WorkspaceID string `json:"workspaceID"`
	SurfaceID   string `json:"surfaceID"`
	Title       string `json:"title"`
}

// TerminalID derives the wire terminal identifier for a descriptor within a
// session: "<sessionID>:terminal:<workspaceID>:<surfaceID>".
func (d TerminalDescriptor) TerminalID(sessionID string) string {
	return fmt.Sprintf("%s:terminal:%s:%s", sessionID, d.WorkspaceID, d.SurfaceID)
}

// ParseTerminalID splits a wire terminal identifier back into its session and
// descriptor UUID components. The title is not carried in the identifier.
func ParseTerminalID(terminalID string) (sessionID, workspaceID, surfaceID string, ok bool) {
	parts := strings.Split(terminalID, ":")
	if len(parts) != 4 || parts[1] != "terminal" {
		return "", "", "", false
	}
	return parts[0], parts[2], parts[3], true
}

// TerminalOpen announces a shared terminal pane (host -> recipients).
type TerminalOpen struct {
	Type                    string             `json:"type"`
	TerminalID              string             `json:"terminalID"`
	Descriptor              TerminalDescriptor `json:"descriptor"`
	FromPeerID              string             `json:"fromPeerID,omitempty"`
	RecipientParticipantIDs []string           `json:"recipientParticipantIDs,omitempty"`
}

// TerminalOutput carries raw PTY output bytes, base64-encoded. Sequence is a
// cumulative byte offset of the first byte in DataBase64 within the host's
// output stream; receivers use it to trim overlap between a seed replay and
// the live stream.
type TerminalOutput struct {
	Type                    string   `json:"type"`
	TerminalID              string   `json:"terminalID"`
	Sequence                uint64   `json:"sequence"`
	DataBase64              string   `json:"dataBase64"`
	FromPeerID              string   `json:"fromPeerID,omitempty"`
	CaretPeerID             string   `json:"caretPeerID,omitempty"`
	RecipientParticipantIDs []string `json:"recipientParticipantIDs,omitempty"`
}

// TerminalInput carries raw keystroke bytes (viewer -> host), base64-encoded.
// The host writes them verbatim to the PTY if the sender is authorized.
type TerminalInput struct {
	Type                    string   `json:"type"`
	TerminalID              string   `json:"terminalID"`
	InputID                 string   `json:"inputID"`
	DataBase64              string   `json:"dataBase64"`
	FromPeerID              string   `json:"fromPeerID,omitempty"`
	RecipientParticipantIDs []string `json:"recipientParticipantIDs,omitempty"`
}

// TerminalDimensions broadcasts the host grid size so mirrors can lock to it.
type TerminalDimensions struct {
	Type                    string   `json:"type"`
	TerminalID              string   `json:"terminalID"`
	Columns                 int      `json:"columns"`
	Rows                    int      `json:"rows"`
	RecipientParticipantIDs []string `json:"recipientParticipantIDs,omitempty"`
}

// TerminalRenderGrid carries a structured styled-cell snapshot used to seed a
// cold-attaching mirror. The frame schema lives in package rendergrid.
type TerminalRenderGrid struct {
	Type                    string          `json:"type"`
	TerminalID              string          `json:"terminalID"`
	Frame                   json.RawMessage `json:"frame"`
	RecipientParticipantIDs []string        `json:"recipientParticipantIDs,omitempty"`
}

// TerminalRenderGridRequest asks the host to resend the full seed.
type TerminalRenderGridRequest struct {
	Type                    string   `json:"type"`
	TerminalID              string   `json:"terminalID"`
	FromPeerID              string   `json:"fromPeerID,omitempty"`
	RecipientParticipantIDs []string `json:"recipientParticipantIDs,omitempty"`
}

// TerminalClose unshares a terminal pane.
type TerminalClose struct {
	Type                    string   `json:"type"`
	TerminalID              string   `json:"terminalID"`
	RecipientParticipantIDs []string `json:"recipientParticipantIDs,omitempty"`
}

// Envelope is a partially decoded relay frame: the discriminator plus the
// relay-stamped metadata, with the raw bytes retained for full decoding.
type Envelope struct {
	Type                    string   `json:"type"`
	FromPeerID              string   `json:"fromPeerID,omitempty"`
	ReceivedAt              int64    `json:"receivedAt,omitempty"`
	RecipientParticipantIDs []string `json:"recipientParticipantIDs,omitempty"`
	// HasRecipients distinguishes an absent recipient list (broadcast) from
	// an explicit empty list (deliver to nobody).
	HasRecipients bool            `json:"-"`
	Raw           json.RawMessage `json:"-"`
}

// DecodeEnvelope parses the discriminator and relay metadata out of a frame.
func DecodeEnvelope(data []byte) (Envelope, error) {
	var probe struct {
		Type                    string           `json:"type"`
		FromPeerID              string           `json:"fromPeerID"`
		ReceivedAt              int64            `json:"receivedAt"`
		RecipientParticipantIDs *json.RawMessage `json:"recipientParticipantIDs"`
	}
	if err := json.Unmarshal(data, &probe); err != nil {
		return Envelope{}, fmt.Errorf("proto: invalid frame: %w", err)
	}
	if probe.Type == "" {
		return Envelope{}, fmt.Errorf("proto: frame missing type")
	}
	env := Envelope{
		Type:       probe.Type,
		FromPeerID: probe.FromPeerID,
		ReceivedAt: probe.ReceivedAt,
		Raw:        append(json.RawMessage(nil), data...),
	}
	if probe.RecipientParticipantIDs != nil {
		env.HasRecipients = true
		if err := json.Unmarshal(*probe.RecipientParticipantIDs, &env.RecipientParticipantIDs); err != nil {
			return Envelope{}, fmt.Errorf("proto: invalid recipientParticipantIDs: %w", err)
		}
	}
	return env, nil
}

// AddressedTo reports whether a frame should be applied by the given
// participant: broadcast frames (no recipient list) match everyone; targeted
// frames match only listed participants. The relay already filters delivery
// of terminal.* frames, so this is defense in depth.
func (e Envelope) AddressedTo(participantID string) bool {
	if !e.HasRecipients {
		return true
	}
	for _, id := range e.RecipientParticipantIDs {
		if id == participantID {
			return true
		}
	}
	return false
}

// Decode unmarshals the full frame into the given typed struct.
func (e Envelope) Decode(v any) error {
	return json.Unmarshal(e.Raw, v)
}
