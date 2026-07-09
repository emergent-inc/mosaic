package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"sync"
	"syscall"

	"golang.org/x/term"

	"github.com/emergent-inc/mosaic/clients/linux/proto"
	"github.com/emergent-inc/mosaic/clients/linux/relay"
	"github.com/emergent-inc/mosaic/clients/linux/rendergrid"
)

// detachKey is Ctrl-] — the keystroke that leaves an attached session
// without being forwarded to the host.
const detachKey = 0x1D

func runJoin(args []string) error {
	// The room code is the leading positional argument; the Go flag package
	// stops at the first non-flag token, so extract the code before parsing
	// the remaining flags (this allows `join <code> -relay ...`).
	if len(args) == 0 || strings.HasPrefix(args[0], "-") {
		return errors.New("join requires a room code: mosaic-linux join <code> [flags]")
	}
	code := args[0]

	fs := flag.NewFlagSet("join", flag.ContinueOnError)
	relayURL := fs.String("relay", defaultRelayURL(), "relay base URL")
	name := fs.String("name", defaultDisplayName(), "display name")
	match := fs.String("terminal", "", "attach to the terminal whose id or title contains this substring")
	readOnly := fs.Bool("read-only", false, "never send keystrokes")
	if err := fs.Parse(args[1:]); err != nil {
		return err
	}

	participantID := stableParticipantID()
	self := proto.Peer{
		PeerID:        relay.NewPeerID(),
		ParticipantID: participantID,
		DisplayName:   *name,
		Color:         colorFor(participantID),
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	conn, err := relay.Dial(ctx, *relayURL, code, self)
	if err != nil {
		return err
	}
	defer conn.Close()

	fmt.Fprintf(os.Stderr, "Joined room %s as %s. Waiting for a shared terminal…\r\n", conn.SessionID, self.DisplayName)
	fmt.Fprintf(os.Stderr, "(press Ctrl-] to detach)\r\n")

	v := &viewer{
		conn:     conn,
		self:     self,
		match:    *match,
		readOnly: *readOnly,
		out:      os.Stdout,
	}
	return v.run(ctx)
}

// viewer renders one shared terminal and forwards local keystrokes to it.
type viewer struct {
	conn     *relay.Conn
	self     proto.Peer
	match    string
	readOnly bool
	out      *os.File

	mu         sync.Mutex
	terminalID string // the terminal we are attached to
	haveSeed   bool   // a full render-grid seed has established the screen
}

func (v *viewer) run(ctx context.Context) error {
	// Put the local terminal in raw mode so keystrokes flow through
	// unbuffered and control sequences are not intercepted by the tty.
	var restore func()
	if term.IsTerminal(int(os.Stdin.Fd())) {
		state, err := term.MakeRaw(int(os.Stdin.Fd()))
		if err == nil {
			restore = func() { _ = term.Restore(int(os.Stdin.Fd()), state) }
		}
	}
	if restore != nil {
		defer restore()
	}

	inputErr := make(chan error, 1)
	go func() { inputErr <- v.readLocalInput(ctx) }()

	for {
		select {
		case <-ctx.Done():
			return nil
		case err := <-inputErr:
			return err
		case env, ok := <-v.conn.Frames():
			if !ok {
				if err := v.conn.Err(); err != nil {
					return fmt.Errorf("connection closed: %w", err)
				}
				return nil
			}
			v.handleFrame(ctx, env)
		}
	}
}

func (v *viewer) handleFrame(ctx context.Context, env proto.Envelope) {
	// Defense in depth: honor targeting even though the relay already filters.
	if !env.AddressedTo(v.self.EffectiveParticipantID()) {
		return
	}
	switch env.Type {
	case proto.TypeTerminalOpen:
		var f proto.TerminalOpen
		if env.Decode(&f) != nil {
			return
		}
		v.considerAttach(ctx, f.TerminalID, f.Descriptor.Title)
	case proto.TypeTerminalOutput:
		var f proto.TerminalOutput
		if env.Decode(&f) != nil || !v.isAttached(f.TerminalID) {
			return
		}
		v.write(unb64(f.DataBase64))
	case proto.TypeTerminalGrid:
		var f proto.TerminalRenderGrid
		if env.Decode(&f) != nil {
			return
		}
		v.considerAttach(ctx, f.TerminalID, "")
		if !v.isAttached(f.TerminalID) {
			return
		}
		frame, err := rendergrid.Decode(f.Frame)
		if err != nil {
			return
		}
		v.applySeed(frame)
	case proto.TypeTerminalClose:
		var f proto.TerminalClose
		if env.Decode(&f) == nil && v.isAttached(f.TerminalID) {
			fmt.Fprint(os.Stderr, "\r\nHost closed the shared terminal.\r\n")
			v.detach()
		}
	case proto.TypePeerLeft:
		// If the host leaves, output simply stops; nothing to do here.
	}
}

// considerAttach binds to the first terminal that matches the -terminal
// filter (or the first one seen when no filter is given).
func (v *viewer) considerAttach(ctx context.Context, terminalID, title string) {
	v.mu.Lock()
	if v.terminalID != "" {
		v.mu.Unlock()
		return
	}
	if v.match != "" &&
		!strings.Contains(strings.ToLower(terminalID), strings.ToLower(v.match)) &&
		!strings.Contains(strings.ToLower(title), strings.ToLower(v.match)) {
		v.mu.Unlock()
		return
	}
	v.terminalID = terminalID
	v.mu.Unlock()

	label := title
	if label == "" {
		label = terminalID
	}
	fmt.Fprintf(os.Stderr, "\r\nAttached to %s\r\n", label)
	// Ask the host for a full seed in case terminal.open arrived without one.
	_ = v.conn.Send(ctx, proto.TerminalRenderGridRequest{
		Type:       proto.TypeTerminalGridReq,
		TerminalID: terminalID,
		FromPeerID: v.self.PeerID,
	})
}

func (v *viewer) applySeed(frame rendergrid.Frame) {
	v.mu.Lock()
	if frame.Full {
		v.haveSeed = true
	} else if !v.haveSeed {
		// Ignore deltas until a full seed establishes the screen.
		v.mu.Unlock()
		return
	}
	v.mu.Unlock()
	v.write(frame.VTBytes())
}

func (v *viewer) isAttached(terminalID string) bool {
	v.mu.Lock()
	defer v.mu.Unlock()
	return v.terminalID == terminalID
}

func (v *viewer) currentTerminal() string {
	v.mu.Lock()
	defer v.mu.Unlock()
	return v.terminalID
}

func (v *viewer) detach() {
	v.mu.Lock()
	v.terminalID = ""
	v.haveSeed = false
	v.mu.Unlock()
}

func (v *viewer) write(data []byte) {
	if len(data) == 0 {
		return
	}
	_, _ = v.out.Write(data)
}

func (v *viewer) readLocalInput(ctx context.Context) error {
	buf := make([]byte, 4096)
	for {
		n, err := os.Stdin.Read(buf)
		if n > 0 {
			chunk := buf[:n]
			if i := indexByte(chunk, detachKey); i >= 0 {
				if i > 0 {
					v.sendInput(ctx, chunk[:i])
				}
				fmt.Fprint(os.Stderr, "\r\nDetached.\r\n")
				return nil
			}
			v.sendInput(ctx, chunk)
		}
		if err != nil {
			return nil // stdin closed
		}
		if ctx.Err() != nil {
			return nil
		}
	}
}

func (v *viewer) sendInput(ctx context.Context, data []byte) {
	if v.readOnly || len(data) == 0 {
		return
	}
	terminalID := v.currentTerminal()
	if terminalID == "" {
		return
	}
	_ = v.conn.Send(ctx, proto.TerminalInput{
		Type:       proto.TypeTerminalInput,
		TerminalID: terminalID,
		InputID:    v.self.PeerID + "-" + newUUID(),
		DataBase64: b64(data),
		FromPeerID: v.self.PeerID,
	})
}

func indexByte(data []byte, b byte) int {
	for i, c := range data {
		if c == b {
			return i
		}
	}
	return -1
}
