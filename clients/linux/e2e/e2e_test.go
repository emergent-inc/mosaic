package e2e

import (
	"bytes"
	"os"
	"os/exec"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/creack/pty"

	"github.com/emergent-inc/mosaic/clients/linux/relay/relaytest"
)

// bin is the path to the pre-built client binary (set via MOSAIC_LINUX_BIN).
func bin(t *testing.T) string {
	t.Helper()
	p := os.Getenv("MOSAIC_LINUX_BIN")
	if p == "" {
		t.Skip("MOSAIC_LINUX_BIN not set")
	}
	return p
}

// ptyReader continuously drains a PTY into a mutex-guarded buffer.
type ptyReader struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (r *ptyReader) drain(f *os.File) {
	b := make([]byte, 4096)
	for {
		n, err := f.Read(b)
		if n > 0 {
			r.mu.Lock()
			r.buf.Write(b[:n])
			r.mu.Unlock()
		}
		if err != nil {
			return
		}
	}
}

func (r *ptyReader) contains(s string) bool {
	r.mu.Lock()
	defer r.mu.Unlock()
	return strings.Contains(r.buf.String(), s)
}

func (r *ptyReader) String() string {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.buf.String()
}

func waitFor(t *testing.T, r *ptyReader, s string, d time.Duration) {
	t.Helper()
	deadline := time.After(d)
	tick := time.NewTicker(20 * time.Millisecond)
	defer tick.Stop()
	for {
		if r.contains(s) {
			return
		}
		select {
		case <-deadline:
			t.Fatalf("timeout waiting for %q; buffer so far:\n%s", s, r.String())
		case <-tick.C:
		}
	}
}

// TestHostAndViewerRoundTrip drives the real binaries end to end: a host
// shares /bin/sh into a room over the in-process relay, a viewer joins,
// output flows host->viewer, and (with -allow-input) input flows
// viewer->host and echoes back.
func TestHostAndViewerRoundTrip(t *testing.T) {
	binary := bin(t)

	srv := relaytest.New()
	defer srv.Close()
	srv.CreateRoom("E2ETEST0")

	// --- host: share /bin/sh, allow remote input ---
	hostCmd := exec.Command(binary, "host",
		"-relay", srv.URL, "-code", "E2ETEST0",
		"-name", "host", "-shell", "/bin/sh", "-allow-input")
	hostCmd.Env = append(os.Environ(), "PS1=$ ", "MOSAIC_RELAY_URL="+srv.URL)
	hostPTY, err := pty.Start(hostCmd)
	if err != nil {
		t.Fatalf("start host: %v", err)
	}
	defer hostCmd.Process.Kill()
	defer hostPTY.Close()
	_ = pty.Setsize(hostPTY, &pty.Winsize{Rows: 24, Cols: 80})
	hostOut := &ptyReader{}
	go hostOut.drain(hostPTY)

	waitFor(t, hostOut, "Sharing", 5*time.Second)

	// --- viewer: join the room ---
	viewerCmd := exec.Command(binary, "join", "E2ETEST0", "-relay", srv.URL, "-name", "viewer")
	viewerPTY, err := pty.Start(viewerCmd)
	if err != nil {
		t.Fatalf("start viewer: %v", err)
	}
	defer viewerCmd.Process.Kill()
	defer viewerPTY.Close()
	_ = pty.Setsize(viewerPTY, &pty.Winsize{Rows: 24, Cols: 80})
	viewerOut := &ptyReader{}
	go viewerOut.drain(viewerPTY)

	waitFor(t, viewerOut, "Attached", 5*time.Second)

	// Host types a command locally; viewer must see the output.
	time.Sleep(300 * time.Millisecond)
	if _, err := hostPTY.Write([]byte("echo host-says-hello\n")); err != nil {
		t.Fatal(err)
	}
	waitFor(t, viewerOut, "host-says-hello", 5*time.Second)

	// Viewer types a command; host applies it and output echoes to the viewer.
	if _, err := viewerPTY.Write([]byte("echo viewer-typed-this\n")); err != nil {
		t.Fatal(err)
	}
	waitFor(t, viewerOut, "viewer-typed-this", 5*time.Second)
	// And the host's own screen shows the viewer-driven command too.
	waitFor(t, hostOut, "viewer-typed-this", 5*time.Second)
}

// TestViewerReadOnlyCannotType verifies a -read-only viewer's keystrokes
// never reach the host shell.
func TestViewerReadOnlyCannotType(t *testing.T) {
	binary := bin(t)

	srv := relaytest.New()
	defer srv.Close()
	srv.CreateRoom("E2ETEST1")

	hostCmd := exec.Command(binary, "host",
		"-relay", srv.URL, "-code", "E2ETEST1", "-shell", "/bin/sh", "-allow-input")
	hostPTY, err := pty.Start(hostCmd)
	if err != nil {
		t.Fatal(err)
	}
	defer hostCmd.Process.Kill()
	defer hostPTY.Close()
	hostOut := &ptyReader{}
	go hostOut.drain(hostPTY)
	waitFor(t, hostOut, "Sharing", 5*time.Second)

	viewerCmd := exec.Command(binary, "join", "E2ETEST1", "-relay", srv.URL, "-read-only")
	viewerPTY, err := pty.Start(viewerCmd)
	if err != nil {
		t.Fatal(err)
	}
	defer viewerCmd.Process.Kill()
	defer viewerPTY.Close()
	viewerOut := &ptyReader{}
	go viewerOut.drain(viewerPTY)
	waitFor(t, viewerOut, "Attached", 5*time.Second)

	time.Sleep(300 * time.Millisecond)
	_, _ = viewerPTY.Write([]byte("echo SHOULD-NOT-APPEAR\n"))
	time.Sleep(1500 * time.Millisecond)
	if hostOut.contains("SHOULD-NOT-APPEAR") {
		t.Fatalf("read-only viewer input reached the host shell:\n%s", hostOut.String())
	}
}
