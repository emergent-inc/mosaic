package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"sync"
	"sync/atomic"
	"syscall"

	"github.com/creack/pty"
	"golang.org/x/term"

	"github.com/emergent-inc/mosaic/clients/linux/proto"
	"github.com/emergent-inc/mosaic/clients/linux/relay"
)

func runHost(args []string) error {
	fs := flag.NewFlagSet("host", flag.ContinueOnError)
	relayURL := fs.String("relay", defaultRelayURL(), "relay base URL")
	code := fs.String("code", "", "join an existing room instead of creating one")
	name := fs.String("name", defaultDisplayName(), "display name")
	title := fs.String("title", "", "shared pane title")
	shellPath := fs.String("shell", "", "program to run (default $SHELL)")
	allowInput := fs.Bool("allow-input", false, "let room peers type into the shared shell")
	if err := fs.Parse(args); err != nil {
		return err
	}

	shell := *shellPath
	if shell == "" {
		shell = os.Getenv("SHELL")
	}
	if shell == "" {
		shell = "/bin/sh"
	}
	paneTitle := *title
	if paneTitle == "" {
		paneTitle = filepath.Base(shell)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Create or reuse a room.
	roomCode := *code
	if roomCode == "" {
		created, err := relay.CreateSession(ctx, *relayURL)
		if err != nil {
			return err
		}
		roomCode = created
	}

	participantID := stableParticipantID()
	self := proto.Peer{
		PeerID:        relay.NewPeerID(),
		ParticipantID: participantID,
		DisplayName:   *name,
		Color:         colorFor(participantID),
	}
	conn, err := relay.Dial(ctx, *relayURL, roomCode, self)
	if err != nil {
		return err
	}
	defer conn.Close()

	h := &host{
		conn:       conn,
		self:       self,
		allowInput: *allowInput,
	}
	descriptor := proto.TerminalDescriptor{
		WorkspaceID: newUUID(),
		SurfaceID:   newUUID(),
		Title:       paneTitle,
	}
	h.terminalID = descriptor.TerminalID(conn.SessionID)

	// Launch the shell under a PTY.
	cmd := exec.Command(shell)
	cmd.Env = append(os.Environ(), "TERM=xterm-256color")
	ptmx, err := pty.Start(cmd)
	if err != nil {
		return fmt.Errorf("start shell: %w", err)
	}
	defer func() { _ = ptmx.Close() }()
	h.ptmx = ptmx

	// Mirror the local terminal size onto the PTY and track changes.
	cols, rows := syncPTYSize(ptmx)
	h.cols, h.rows = cols, rows

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

	fmt.Fprintf(os.Stderr, "Sharing %q in room %s\r\n", paneTitle, roomCode)
	fmt.Fprintf(os.Stderr, "Join from another machine with:  mosaic-linux join %s\r\n", roomCode)
	if h.allowInput {
		fmt.Fprintf(os.Stderr, "Remote input is ENABLED for everyone in the room.\r\n")
	} else {
		fmt.Fprintf(os.Stderr, "Remote input is disabled (view-only). Use -allow-input to permit typing.\r\n")
	}
	fmt.Fprintf(os.Stderr, "----\r\n")

	h.descriptor = descriptor
	// Announce the shared terminal and its size to whoever is already here.
	h.announce(ctx)

	// Handle window resizes on the local terminal.
	winch := make(chan os.Signal, 1)
	signal.Notify(winch, syscall.SIGWINCH)
	defer signal.Stop(winch)
	go func() {
		for range winch {
			c, r := syncPTYSize(ptmx)
			h.mu.Lock()
			h.cols, h.rows = c, r
			h.mu.Unlock()
			h.sendDimensions(ctx)
		}
	}()

	// Fan PTY output to the local screen and to the room.
	outErr := make(chan error, 1)
	go func() { outErr <- h.pumpOutput(ctx) }()

	// Handle incoming frames (remote input, seed requests).
	go h.handleFrames(ctx)

	// Local keystrokes drive the shell too.
	go h.pumpLocalInput(ctx)

	select {
	case <-ctx.Done():
	case err := <-outErr:
		if err != nil && !errors.Is(err, os.ErrClosed) {
			fmt.Fprintf(os.Stderr, "\r\nshell ended: %v\r\n", err)
		}
	}
	_ = conn.Send(context.Background(), proto.TerminalClose{Type: proto.TypeTerminalClose, TerminalID: h.terminalID})
	return nil
}

type host struct {
	conn       *relay.Conn
	self       proto.Peer
	ptmx       *os.File
	terminalID string
	descriptor proto.TerminalDescriptor
	allowInput bool

	sequence atomic.Uint64

	mu   sync.Mutex
	cols int
	rows int
}

func (h *host) pumpOutput(ctx context.Context) error {
	buf := make([]byte, 32*1024)
	for {
		n, err := h.ptmx.Read(buf)
		if n > 0 {
			chunk := buf[:n]
			_, _ = os.Stdout.Write(chunk)
			seq := h.sequence.Add(uint64(n)) - uint64(n)
			_ = h.conn.Send(ctx, proto.TerminalOutput{
				Type:       proto.TypeTerminalOutput,
				TerminalID: h.terminalID,
				Sequence:   seq,
				DataBase64: b64(chunk),
				FromPeerID: h.self.PeerID,
			})
		}
		if err != nil {
			return err
		}
		if ctx.Err() != nil {
			return nil
		}
	}
}

func (h *host) pumpLocalInput(ctx context.Context) {
	buf := make([]byte, 4096)
	for {
		n, err := os.Stdin.Read(buf)
		if n > 0 {
			_, _ = h.ptmx.Write(buf[:n])
		}
		if err != nil || ctx.Err() != nil {
			return
		}
	}
}

func (h *host) handleFrames(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case env, ok := <-h.conn.Frames():
			if !ok {
				return
			}
			switch env.Type {
			case proto.TypePeerJoined:
				// A new participant arrived after our initial announcement;
				// re-announce so late joiners discover and seed the pane.
				h.announce(ctx)
			case proto.TypeTerminalInput:
				if !h.allowInput {
					continue
				}
				var f proto.TerminalInput
				if env.Decode(&f) == nil && f.TerminalID == h.terminalID {
					_, _ = h.ptmx.Write(unb64(f.DataBase64))
				}
			case proto.TypeTerminalGridReq:
				var f proto.TerminalRenderGridRequest
				if env.Decode(&f) == nil && f.TerminalID == h.terminalID {
					// A fresh viewer joined mid-stream. We don't reconstruct a
					// styled grid from the raw PTY; re-announce dimensions and
					// nudge the shell to repaint so the newcomer catches up.
					h.sendDimensions(ctx)
					h.repaint()
				}
			}
		}
	}
}

// announce (re)broadcasts the shared terminal, its dimensions, and nudges a
// repaint so a newly joined viewer can attach and catch up. It is safe to
// call repeatedly.
func (h *host) announce(ctx context.Context) {
	_ = h.conn.Send(ctx, proto.TerminalOpen{
		Type:       proto.TypeTerminalOpen,
		TerminalID: h.terminalID,
		Descriptor: h.descriptor,
		FromPeerID: h.self.PeerID,
	})
	h.sendDimensions(ctx)
	h.repaint()
}

// repaint asks the running program to redraw (Ctrl-L for shells/full-screen
// apps). This is a best-effort catch-up for late joiners without a styled
// snapshot producer.
func (h *host) repaint() {
	_, _ = h.ptmx.Write([]byte{0x0C})
}

func (h *host) sendDimensions(ctx context.Context) {
	h.mu.Lock()
	cols, rows := h.cols, h.rows
	h.mu.Unlock()
	if cols <= 0 || rows <= 0 {
		return
	}
	_ = h.conn.Send(ctx, proto.TerminalDimensions{
		Type:       proto.TypeTerminalDims,
		TerminalID: h.terminalID,
		Columns:    cols,
		Rows:       rows,
	})
}

// syncPTYSize copies the controlling terminal's size onto the PTY and returns
// the dimensions; when stdin is not a terminal it falls back to 80x24.
func syncPTYSize(ptmx *os.File) (cols, rows int) {
	if term.IsTerminal(int(os.Stdin.Fd())) {
		if w, h, err := term.GetSize(int(os.Stdin.Fd())); err == nil {
			_ = pty.Setsize(ptmx, &pty.Winsize{Rows: uint16(h), Cols: uint16(w)})
			return w, h
		}
	}
	_ = pty.Setsize(ptmx, &pty.Winsize{Rows: 24, Cols: 80})
	return 80, 24
}
