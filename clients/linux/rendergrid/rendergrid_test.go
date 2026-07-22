package rendergrid

import (
	"encoding/json"
	"strings"
	"testing"
)

// The expected VT byte strings below are copied verbatim from the Swift test
// suite (MobileTerminalRenderGridTests.swift) so this Go synthesizer is
// proven byte-compatible with the macOS/iOS producer and consumer.

func mustDecode(t *testing.T, obj map[string]any) Frame {
	t.Helper()
	data, err := json.Marshal(obj)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	f, err := Decode(data)
	if err != nil {
		t.Fatalf("decode: %v", err)
	}
	return f
}

// fromPlainRows mirrors the Swift test helper: build a frame from newline text.
func fromPlainRows(t *testing.T, cols, rows int, text string, cursor *Cursor, full bool, changed []int) Frame {
	t.Helper()
	lines := normalizeRows(text, rows)
	included := map[int]bool{}
	if changed == nil {
		for i := 0; i < rows; i++ {
			included[i] = true
		}
	} else {
		for _, r := range changed {
			included[r] = true
		}
	}
	var spans []RowSpan
	for i, line := range lines {
		if !included[i] {
			continue
		}
		trimmed := strings.TrimRight(line, " \t")
		if trimmed == "" {
			continue
		}
		if len(trimmed) > cols {
			trimmed = trimmed[:cols]
		}
		spans = append(spans, RowSpan{Row: i, Column: 0, StyleID: 0, Text: trimmed})
	}
	obj := map[string]any{
		"format": CurrentFormat, "surface_id": "terminal-a", "state_seq": 1,
		"columns": cols, "rows": rows, "full": full, "row_spans": spansToJSON(spans),
	}
	if cursor != nil {
		obj["cursor"] = map[string]any{"row": cursor.Row, "column": cursor.Column}
	}
	if !full {
		obj["cleared_rows"] = changed
	}
	return mustDecode(t, obj)
}

func spansToJSON(spans []RowSpan) []map[string]any {
	out := make([]map[string]any, 0, len(spans))
	for _, s := range spans {
		out = append(out, map[string]any{"row": s.Row, "column": s.Column, "style_id": s.StyleID, "text": s.Text})
	}
	return out
}

func normalizeRows(text string, maxRows int) []string {
	text = strings.ReplaceAll(text, "\r\n", "\n")
	text = strings.ReplaceAll(text, "\r", "\n")
	lines := strings.Split(text, "\n")
	if len(lines) > maxRows && lines[len(lines)-1] == "" {
		lines = lines[:len(lines)-1]
	}
	if len(lines) > maxRows {
		lines = lines[:maxRows]
	}
	for len(lines) < maxRows {
		lines = append(lines, "")
	}
	return lines
}

func TestFullSnapshotMatchesSwift(t *testing.T) {
	frame := fromPlainRows(t, 8, 4, "alpha   \n\n beta\n", &Cursor{Row: 2, Column: 5}, true, nil)
	want := "\x1bc\x1b[3J\x1b[?2026h" +
		"\x1b[?7l\x1b[?25l\x1b[0m" +
		"\x1b[0m\x1b[1Galpha" +
		"\r\n\x1b[0m" +
		"\r\n\x1b[0m\x1b[1G beta" +
		"\r\n\x1b[0m" +
		"\x1b[0m\x1b[2 q\x1b[?25h\x1b[3;6H" +
		"\x1b[?2026l"
	if got := string(frame.VTBytes()); got != want {
		t.Errorf("full snapshot mismatch\n got: %q\nwant: %q", got, want)
	}
}

func TestDeltaClearsOnlyChangedRows(t *testing.T) {
	frame := fromPlainRows(t, 8, 4, "alpha\nchanged\n\nomega", nil, false, []int{1, 2})
	if frame.Full {
		t.Fatal("expected delta frame")
	}
	want := "\x1b[0m\x1b[2;1H\x1b[2K" +
		"\x1b[0m\x1b[3;1H\x1b[2K" +
		"\x1b[2;1H\x1b[0mchanged" +
		"\x1b[0m"
	if got := string(frame.VTBytes()); got != want {
		t.Errorf("delta mismatch\n got: %q\nwant: %q", got, want)
	}
}

func TestPatchPreservesRgbStylesAndCursorShape(t *testing.T) {
	// Mirrors renderGridPatchPreservesRgbStylesAndCursorShape.
	fg1, bg1 := "#C0C0C0", "#101010"
	fg2, bg2 := "#FF0000", "#0000FF"
	obj := map[string]any{
		"format": CurrentFormat, "surface_id": "t", "state_seq": 1,
		"columns": 8, "rows": 4, "full": false,
		"cleared_rows": []int{0, 1},
		"styles": []map[string]any{
			{"id": 0, "foreground": fg1, "background": bg1},
			{"id": 1, "foreground": fg2, "background": bg2, "bold": true, "underline": true},
		},
		"row_spans": []map[string]any{
			{"row": 1, "column": 0, "style_id": 1, "text": "red"},
		},
		"cursor": map[string]any{"row": 1, "column": 2, "style": "bar", "visible": true},
	}
	frame := mustDecode(t, obj)
	vt := string(frame.VTBytes())
	for _, want := range []string{
		"\x1b[0;38;2;192;192;192;48;2;16;16;16m",
		"\x1b[0;1;4;38;2;255;0;0;48;2;0;0;255mred",
		"\x1b[6 q\x1b[?25h\x1b[2;3H",
	} {
		if !strings.Contains(vt, want) {
			t.Errorf("expected VT to contain %q\ngot: %q", want, vt)
		}
	}
}

func TestFullSnapshotClearsScrollbackBeforeReplay(t *testing.T) {
	obj := map[string]any{
		"format": CurrentFormat, "surface_id": "t", "state_seq": 1,
		"columns": 8, "rows": 1, "full": true,
		"row_spans":        []map[string]any{{"row": 0, "column": 0, "text": "live"}},
		"scrollback_rows":  1,
		"scrollback_spans": []map[string]any{{"row": 0, "column": 0, "text": "host-old"}},
	}
	frame := mustDecode(t, obj)
	vt := string(frame.VTBytes())
	clearIdx := strings.Index(vt, "\x1b[3J")
	histIdx := strings.Index(vt, "host-old")
	if clearIdx < 0 || histIdx < 0 || clearIdx >= histIdx {
		t.Errorf("scrollback clear must precede history replay; clear=%d hist=%d", clearIdx, histIdx)
	}
}

func TestFullSnapshotRestoresAlternateScreenAndModes(t *testing.T) {
	obj := map[string]any{
		"format": CurrentFormat, "surface_id": "t", "state_seq": 1,
		"columns": 4, "rows": 1, "full": true,
		"active_screen": "alternate",
		"row_spans":     []map[string]any{{"row": 0, "column": 0, "text": "tui"}},
		"modes": []map[string]any{
			{"code": 2004, "on": true},
			{"code": 1049, "on": true}, // must be skipped (screen-switch code)
		},
	}
	frame := mustDecode(t, obj)
	vt := string(frame.VTBytes())
	if !strings.HasPrefix(vt, "\x1bc\x1b[3J\x1b[?2026h") {
		t.Errorf("missing reset prefix: %q", vt)
	}
	if !strings.HasSuffix(vt, "\x1b[?2026l") {
		t.Errorf("missing sync suffix: %q", vt)
	}
	if !strings.Contains(vt, "\x1b[?1049h") {
		t.Errorf("alternate screen not entered: %q", vt)
	}
	if !strings.Contains(vt, "\x1b[?2004h") {
		t.Errorf("bracketed-paste mode not restored: %q", vt)
	}
	if strings.Count(vt, "1049h") != 1 {
		t.Errorf("mode 1049 must not be double-replayed from modes: %q", vt)
	}
}

func TestLegacyFormatAccepted(t *testing.T) {
	obj := map[string]any{
		"format": "cmux.render-grid.v1", "surface_id": "t", "state_seq": 1,
		"columns": 8, "rows": 1, "row_spans": []map[string]any{{"row": 0, "column": 0, "text": "alpha"}},
	}
	frame := mustDecode(t, obj)
	if frame.Format != CurrentFormat {
		t.Errorf("legacy format not normalized: %q", frame.Format)
	}
}

func TestWideCellSpan(t *testing.T) {
	width := 2
	obj := map[string]any{
		"format": CurrentFormat, "surface_id": "t", "state_seq": 1,
		"columns": 3, "rows": 1,
		"row_spans": []map[string]any{{"row": 0, "column": 0, "text": "界", "cell_width": width}},
	}
	frame := mustDecode(t, obj) // must validate: column(0)+width(2) <= columns(3)
	if len(frame.RowSpans) != 1 || frame.RowSpans[0].gridCellWidth() != 2 {
		t.Errorf("wide cell width not honored: %+v", frame.RowSpans)
	}
}

func TestRejectsInvalidSpanColumn(t *testing.T) {
	obj := map[string]any{
		"format": CurrentFormat, "surface_id": "t", "state_seq": 1,
		"columns": 8, "rows": 1,
		"row_spans": []map[string]any{{"row": 0, "column": 9, "text": "x"}},
	}
	data, _ := json.Marshal(obj)
	if _, err := Decode(data); err == nil {
		t.Fatal("expected invalid-column error")
	}
}

func TestControlCharactersStripped(t *testing.T) {
	// Span text carrying an ESC must not inject a live escape sequence.
	obj := map[string]any{
		"format": CurrentFormat, "surface_id": "t", "state_seq": 1,
		"columns": 8, "rows": 1,
		"row_spans": []map[string]any{{"row": 0, "column": 0, "text": "a\x1b[31mb"}},
	}
	frame := mustDecode(t, obj)
	vt := string(frame.VTBytes())
	// The injected "\x1b[31m" must have been neutralized to spaces.
	if strings.Contains(vt, "a\x1b[31mb") {
		t.Errorf("control characters were not stripped from span text: %q", vt)
	}
}
