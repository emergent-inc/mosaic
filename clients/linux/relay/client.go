// Package relay implements a client for the Mosaic collaboration relay
// (workers/collaboration): create a room, join by code, exchange JSON frames.
//
// The relay has no account auth — possession of the session code is the only
// gate. The connect query string is the hello; the server's session.joined
// frame is the join acknowledgement and must arrive promptly or the join is
// treated as failed (mirroring the macOS client's acknowledgement gate).
package relay

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"nhooyr.io/websocket"

	"github.com/emergent-inc/mosaic/clients/linux/proto"
)

// DefaultRelayURL is the production relay shipped in the macOS client
// (Sources/CollaborationRuntime.swift defaultRelayURLString).
const DefaultRelayURL = "https://mosaic-collaboration-worker.dorsa-rohani.workers.dev"

// heartbeatInterval matches the macOS client cadence (server timeout is 30s).
const heartbeatInterval = 20 * time.Second

// joinAckTimeout bounds the wait for the relay's session.joined frame.
const joinAckTimeout = 10 * time.Second

// NormalizeSessionCode uppercases and strips non-alphanumerics, accepting
// 4-, 5- and 8-character codes (workers/collaboration/src/protocol.ts).
func NormalizeSessionCode(raw string) (string, error) {
	var sb strings.Builder
	for _, r := range strings.ToUpper(raw) {
		if (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') {
			sb.WriteRune(r)
		}
	}
	code := sb.String()
	switch len(code) {
	case 4, 5, 8:
		return code, nil
	}
	return "", fmt.Errorf("relay: invalid session code %q (want 4, 5 or 8 chars of A-Z0-9)", raw)
}

// CreateSession creates a new room and returns its shareable code.
func CreateSession(ctx context.Context, baseURL string) (string, error) {
	endpoint := strings.TrimSuffix(baseURL, "/") + "/v1/collaboration/sessions"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, nil)
	if err != nil {
		return "", err
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return "", fmt.Errorf("relay: create session: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusCreated && resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("relay: create session: unexpected status %s", resp.Status)
	}
	var body struct {
		SessionID   string `json:"sessionID"`
		SessionCode string `json:"sessionCode"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return "", fmt.Errorf("relay: create session: %w", err)
	}
	if body.SessionCode == "" {
		return "", errors.New("relay: create session: empty sessionCode")
	}
	return body.SessionCode, nil
}

// NewPeerID returns a fresh random peer identifier for one connection.
func NewPeerID() string {
	var buf [16]byte
	if _, err := rand.Read(buf[:]); err != nil {
		panic(err) // crypto/rand failure is not recoverable
	}
	return hex.EncodeToString(buf[:])
}

// Conn is a live connection to a collaboration room.
type Conn struct {
	SessionID string
	Self      proto.Peer

	ws     *websocket.Conn
	frames chan proto.Envelope

	// writeMu serializes writes: nhooyr.io/websocket permits only one writer
	// at a time, and Send is called from the read, heartbeat, and caller
	// goroutines concurrently.
	writeMu sync.Mutex

	mu     sync.Mutex
	peers  map[string]proto.Peer // by peerID
	err    error
	closed bool
	cancel context.CancelFunc
}

// Dial joins the room identified by code, waits for the session.joined
// acknowledgement, and starts the read and heartbeat loops.
func Dial(ctx context.Context, baseURL, code string, self proto.Peer) (*Conn, error) {
	code, err := NormalizeSessionCode(code)
	if err != nil {
		return nil, err
	}
	if self.PeerID == "" || self.DisplayName == "" || self.Color == "" {
		return nil, errors.New("relay: peerID, displayName and color are required")
	}
	u, err := url.Parse(strings.TrimSuffix(baseURL, "/"))
	if err != nil {
		return nil, fmt.Errorf("relay: invalid relay URL: %w", err)
	}
	switch u.Scheme {
	case "https":
		u.Scheme = "wss"
	case "http":
		u.Scheme = "ws"
	}
	u.Path += "/v1/collaboration/sessions/" + code + "/connect"
	q := u.Query()
	q.Set("peerID", self.PeerID)
	if self.ParticipantID != "" {
		q.Set("participantID", self.ParticipantID)
	}
	q.Set("displayName", self.DisplayName)
	q.Set("color", self.Color)
	if self.ImageURL != "" {
		q.Set("imageURL", self.ImageURL)
	}
	u.RawQuery = q.Encode()

	dialCtx, cancelDial := context.WithTimeout(ctx, joinAckTimeout)
	defer cancelDial()
	ws, resp, err := websocket.Dial(dialCtx, u.String(), nil)
	if err != nil {
		if resp != nil && resp.StatusCode == http.StatusNotFound {
			return nil, fmt.Errorf("relay: session %s not found (expired or never created)", code)
		}
		return nil, fmt.Errorf("relay: connect: %w", err)
	}
	// The relay caps envelopes at 1 MiB; leave headroom for overhead.
	ws.SetReadLimit(proto.MaxFrameBytes + 4096)

	// Join acknowledgement gate: the first frame must be session.joined.
	env, err := readEnvelope(dialCtx, ws)
	if err != nil {
		ws.Close(websocket.StatusPolicyViolation, "no join ack")
		return nil, fmt.Errorf("relay: no session.joined acknowledgement: %w", err)
	}
	if env.Type != proto.TypeSessionJoined {
		ws.Close(websocket.StatusPolicyViolation, "unexpected first frame")
		return nil, fmt.Errorf("relay: expected session.joined, got %q", env.Type)
	}
	var joined proto.SessionJoined
	if err := env.Decode(&joined); err != nil {
		ws.Close(websocket.StatusPolicyViolation, "bad join ack")
		return nil, fmt.Errorf("relay: malformed session.joined: %w", err)
	}

	runCtx, cancel := context.WithCancel(context.Background())
	c := &Conn{
		SessionID: joined.SessionID,
		Self:      self,
		ws:        ws,
		frames:    make(chan proto.Envelope, 64),
		peers:     make(map[string]proto.Peer, len(joined.Peers)),
		cancel:    cancel,
	}
	for _, p := range joined.Peers {
		if p.PeerID != self.PeerID {
			c.peers[p.PeerID] = p
		}
	}
	go c.readLoop(runCtx)
	go c.heartbeatLoop(runCtx)
	return c, nil
}

func readEnvelope(ctx context.Context, ws *websocket.Conn) (proto.Envelope, error) {
	_, data, err := ws.Read(ctx)
	if err != nil {
		return proto.Envelope{}, err
	}
	return proto.DecodeEnvelope(data)
}

// Frames returns the stream of decoded incoming frames. The channel closes
// when the connection ends; check Err afterwards.
func (c *Conn) Frames() <-chan proto.Envelope { return c.frames }

// Err reports why the connection ended, nil on clean close.
func (c *Conn) Err() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.err
}

// Peers returns a snapshot of the current roster (excluding self).
func (c *Conn) Peers() []proto.Peer {
	c.mu.Lock()
	defer c.mu.Unlock()
	out := make([]proto.Peer, 0, len(c.peers))
	for _, p := range c.peers {
		out = append(out, p)
	}
	return out
}

// PeerByID looks up a roster entry by peerID.
func (c *Conn) PeerByID(peerID string) (proto.Peer, bool) {
	c.mu.Lock()
	defer c.mu.Unlock()
	p, ok := c.peers[peerID]
	return p, ok
}

// Send marshals and writes one frame.
func (c *Conn) Send(ctx context.Context, v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	if len(data) > proto.MaxFrameBytes {
		return fmt.Errorf("relay: frame of %d bytes exceeds the %d relay cap", len(data), proto.MaxFrameBytes)
	}
	c.writeMu.Lock()
	defer c.writeMu.Unlock()
	return c.ws.Write(ctx, websocket.MessageText, data)
}

// Close ends the connection gracefully.
func (c *Conn) Close() error {
	c.cancel()
	return c.ws.Close(websocket.StatusNormalClosure, "bye")
}

func (c *Conn) readLoop(ctx context.Context) {
	defer close(c.frames)
	for {
		env, err := readEnvelope(ctx, c.ws)
		if err != nil {
			c.mu.Lock()
			if !c.closed {
				c.closed = true
				if ctx.Err() == nil && websocket.CloseStatus(err) != websocket.StatusNormalClosure {
					c.err = err
				}
			}
			c.mu.Unlock()
			return
		}
		c.trackRoster(env)
		select {
		case c.frames <- env:
		case <-ctx.Done():
			return
		}
	}
}

// trackRoster keeps the peer table in sync from roster frames.
func (c *Conn) trackRoster(env proto.Envelope) {
	switch env.Type {
	case proto.TypePeerJoined, proto.TypePeerUpdate:
		var f proto.PeerJoined
		if env.Decode(&f) == nil && f.Peer.PeerID != "" && f.Peer.PeerID != c.Self.PeerID {
			c.mu.Lock()
			c.peers[f.Peer.PeerID] = f.Peer
			c.mu.Unlock()
		}
	case proto.TypePeerLeft:
		var f proto.PeerLeft
		if env.Decode(&f) == nil {
			c.mu.Lock()
			delete(c.peers, f.PeerID)
			c.mu.Unlock()
		}
	}
}

func (c *Conn) heartbeatLoop(ctx context.Context) {
	ticker := time.NewTicker(heartbeatInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := c.Send(ctx, proto.NewHeartbeat()); err != nil {
				return
			}
		}
	}
}
