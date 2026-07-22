// Package relaytest provides an in-process implementation of the Mosaic
// collaboration relay for tests, replicating the forwarding semantics of
// workers/collaboration/src/session-state.ts:
//
//   - session.joined is sent immediately on connect with the current roster;
//   - peer.heartbeat is swallowed (liveness only, never forwarded);
//   - peer.update validates the inner peerID and is broadcast;
//   - every other frame is forwarded to the other peers with fromPeerID and
//     receivedAt stamped on;
//   - terminal.* frames honor recipientParticipantIDs (absent = broadcast,
//     empty = nobody, otherwise only listed participantIDs).
package relaytest

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"time"

	"nhooyr.io/websocket"
)

type peerConn struct {
	peerID        string
	participantID string
	displayName   string
	color         string
	imageURL      string
	ws            *websocket.Conn
	writeMu       sync.Mutex
}

func (p *peerConn) roster() map[string]any {
	entry := map[string]any{
		"peerID":        p.peerID,
		"participantID": p.participantID,
		"displayName":   p.displayName,
		"color":         p.color,
	}
	if p.imageURL != "" {
		entry["imageURL"] = p.imageURL
	}
	return entry
}

func (p *peerConn) send(ctx context.Context, v any) error {
	data, err := json.Marshal(v)
	if err != nil {
		return err
	}
	p.writeMu.Lock()
	defer p.writeMu.Unlock()
	return p.ws.Write(ctx, websocket.MessageText, data)
}

type room struct {
	mu    sync.Mutex
	peers map[string]*peerConn
}

// Server is an httptest-backed relay double.
type Server struct {
	*httptest.Server

	mu     sync.Mutex
	rooms  map[string]*room
	nextID int
}

// New starts an in-process relay.
func New() *Server {
	s := &Server{rooms: map[string]*room{}}
	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{"ok": true, "service": "mosaic-collaboration"})
	})
	mux.HandleFunc("/v1/collaboration/sessions", s.handleCreate)
	mux.HandleFunc("/v1/collaboration/sessions/", s.handleConnect)
	s.Server = httptest.NewServer(mux)
	return s
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func (s *Server) handleCreate(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.NotFound(w, r)
		return
	}
	s.mu.Lock()
	s.nextID++
	code := fmt.Sprintf("TEST%04d", s.nextID)
	s.rooms[code] = &room{peers: map[string]*peerConn{}}
	s.mu.Unlock()
	writeJSON(w, http.StatusCreated, map[string]any{"sessionID": code, "sessionCode": code})
}

// CreateRoom pre-creates a room with a fixed code for tests.
func (s *Server) CreateRoom(code string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.rooms[code] = &room{peers: map[string]*peerConn{}}
}

func (s *Server) handleConnect(w http.ResponseWriter, r *http.Request) {
	path := strings.TrimPrefix(r.URL.Path, "/v1/collaboration/sessions/")
	code, rest, ok := strings.Cut(path, "/")
	if !ok || rest != "connect" {
		http.NotFound(w, r)
		return
	}
	s.mu.Lock()
	rm := s.rooms[code]
	s.mu.Unlock()
	if rm == nil {
		writeJSON(w, http.StatusNotFound, map[string]any{"error": "session_not_found"})
		return
	}
	q := r.URL.Query()
	peer := &peerConn{
		peerID:        q.Get("peerID"),
		participantID: q.Get("participantID"),
		displayName:   q.Get("displayName"),
		color:         q.Get("color"),
		imageURL:      q.Get("imageURL"),
	}
	if peer.peerID == "" || peer.displayName == "" || peer.color == "" {
		writeJSON(w, http.StatusBadRequest, map[string]any{"error": "invalid_peer"})
		return
	}
	if peer.participantID == "" {
		peer.participantID = peer.peerID
	}
	ws, err := websocket.Accept(w, r, nil)
	if err != nil {
		return
	}
	peer.ws = ws
	ctx := context.Background()

	rm.mu.Lock()
	roster := []map[string]any{peer.roster()}
	for _, other := range rm.peers {
		roster = append(roster, other.roster())
	}
	rm.peers[peer.peerID] = peer
	others := rm.others(peer.peerID)
	rm.mu.Unlock()

	_ = peer.send(ctx, map[string]any{"type": "session.joined", "sessionID": code, "peers": roster})
	for _, other := range others {
		_ = other.send(ctx, map[string]any{"type": "peer.joined", "peer": peer.roster()})
	}

	go s.readLoop(ctx, rm, peer)
}

func (r *room) others(peerID string) []*peerConn {
	out := make([]*peerConn, 0, len(r.peers))
	for id, p := range r.peers {
		if id != peerID {
			out = append(out, p)
		}
	}
	return out
}

func (s *Server) readLoop(ctx context.Context, rm *room, peer *peerConn) {
	defer func() {
		rm.mu.Lock()
		delete(rm.peers, peer.peerID)
		others := rm.others(peer.peerID)
		rm.mu.Unlock()
		for _, other := range others {
			_ = other.send(ctx, map[string]any{"type": "peer.left", "peerID": peer.peerID, "reason": "disconnect"})
		}
		_ = peer.ws.Close(websocket.StatusNormalClosure, "")
	}()
	for {
		_, data, err := peer.ws.Read(ctx)
		if err != nil {
			return
		}
		var envelope map[string]any
		if err := json.Unmarshal(data, &envelope); err != nil {
			peer.ws.Close(websocket.StatusUnsupportedData, "invalid frame")
			return
		}
		frameType, _ := envelope["type"].(string)
		if frameType == "" {
			peer.ws.Close(websocket.StatusUnsupportedData, "invalid frame")
			return
		}
		if frameType == "peer.heartbeat" {
			continue
		}
		if frameType == "peer.update" {
			inner, _ := envelope["peer"].(map[string]any)
			if id, _ := inner["peerID"].(string); id != peer.peerID {
				continue
			}
		}
		envelope["fromPeerID"] = peer.peerID
		envelope["receivedAt"] = time.Now().UnixMilli()

		var recipients []string
		hasRecipients := false
		if strings.HasPrefix(frameType, "terminal.") {
			if raw, present := envelope["recipientParticipantIDs"]; present && raw != nil {
				hasRecipients = true
				if list, ok := raw.([]any); ok {
					for _, item := range list {
						if id, ok := item.(string); ok {
							recipients = append(recipients, id)
						}
					}
				}
			}
		}

		rm.mu.Lock()
		targets := rm.others(peer.peerID)
		rm.mu.Unlock()
		for _, target := range targets {
			if hasRecipients && !contains(recipients, target.participantID) {
				continue
			}
			_ = target.send(ctx, envelope)
		}
	}
}

func contains(list []string, v string) bool {
	for _, item := range list {
		if item == v {
			return true
		}
	}
	return false
}
