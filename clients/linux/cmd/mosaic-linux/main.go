// Command mosaic-linux is a minimal Linux/WSL participant client for Mosaic
// collaboration rooms. It can join a room to watch and drive a shared
// terminal pane (`join`), and share a local shell into a room (`host`).
//
// It speaks the collaboration relay protocol used by the macOS app
// (workers/collaboration + Sources/CollaborationRuntime.swift) and needs no
// account: possession of the room code is the only credential the relay
// checks.
package main

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/emergent-inc/mosaic/clients/linux/relay"
)

var version = "dev"

const defaultColorPalette = "#7A5CFF,#0A84FF,#34C759,#FF9F0A,#FF375F"

func main() {
	if len(os.Args) < 2 {
		usage()
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "join":
		err = runJoin(os.Args[2:])
	case "host":
		err = runHost(os.Args[2:])
	case "version", "--version", "-v":
		fmt.Println("mosaic-linux", version)
	case "help", "--help", "-h":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "unknown command %q\n\n", os.Args[1])
		usage()
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "mosaic-linux:", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `mosaic-linux — Mosaic collaboration client for Linux/WSL

Usage:
  mosaic-linux join <code> [flags]   join a room and attach to a shared terminal
  mosaic-linux host [flags]          share a local shell into a room
  mosaic-linux version

Join flags:
  -relay URL        relay base URL (default %s, env MOSAIC_RELAY_URL)
  -name NAME        display name (default $USER@hostname)
  -terminal MATCH   attach to the terminal whose id or title contains MATCH
  -read-only        never send keystrokes
  While attached: type normally to send input; press Ctrl-] to detach.

Host flags:
  -relay URL        relay base URL (as above)
  -code CODE        join an existing room instead of creating one
  -name NAME        display name (default $USER@hostname)
  -title TITLE      shared pane title (default the shell name)
  -shell PATH       program to run (default $SHELL, falls back to /bin/sh)
  -allow-input      let room peers type into the shared shell (default view-only)
`, relay.DefaultRelayURL)
}

func defaultRelayURL() string {
	if v := os.Getenv("MOSAIC_RELAY_URL"); v != "" {
		return v
	}
	return relay.DefaultRelayURL
}

func defaultDisplayName() string {
	user := os.Getenv("USER")
	if user == "" {
		user = "linux"
	}
	host, err := os.Hostname()
	if err != nil || host == "" {
		return user
	}
	return user + "@" + host
}

// colorFor mirrors the macOS palette selection: sum the UTF-8 bytes of the
// identity and pick from the default palette.
func colorFor(identity string) string {
	palette := strings.Split(defaultColorPalette, ",")
	sum := 0
	for _, b := range []byte(identity) {
		sum += int(b)
	}
	return palette[sum%len(palette)]
}

// stableParticipantID returns a participant identity that survives
// reconnects, so a macOS host's recipient selection keeps matching this
// client. It is persisted under the user config dir; failing that, the
// ephemeral fallback still works for a single session.
func stableParticipantID() string {
	dir, err := os.UserConfigDir()
	if err == nil {
		path := filepath.Join(dir, "mosaic-linux", "participant-id")
		if data, err := os.ReadFile(path); err == nil {
			if id := strings.TrimSpace(string(data)); id != "" {
				return id
			}
		}
		id := "linux-" + relay.NewPeerID()
		if os.MkdirAll(filepath.Dir(path), 0o700) == nil &&
			os.WriteFile(path, []byte(id+"\n"), 0o600) == nil {
			return id
		}
		return id
	}
	return "linux-" + relay.NewPeerID()
}

func newUUID() string {
	var buf [16]byte
	if _, err := rand.Read(buf[:]); err != nil {
		panic(err)
	}
	buf[6] = buf[6]&0x0F | 0x40 // version 4
	buf[8] = buf[8]&0x3F | 0x80 // RFC 4122 variant
	h := hex.EncodeToString(buf[:])
	return strings.ToUpper(h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:32])
}

func b64(data []byte) string { return base64.StdEncoding.EncodeToString(data) }
func unb64(s string) []byte {
	data, err := base64.StdEncoding.DecodeString(s)
	if err != nil {
		return nil
	}
	return data
}
