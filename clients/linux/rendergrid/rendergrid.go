// Package rendergrid decodes Mosaic terminal render-grid snapshot frames and
// synthesizes the VT byte stream that reproduces them, byte-compatible with
// the Swift implementation in
// Packages/Shared/MosaicMobileCore/Sources/MosaicMobileCore/
// (MobileTerminalRenderGrid.swift + MobileTerminalRenderGridReplay.swift).
//
// A full frame is a cold-attach snapshot: reset, restore dynamic colors,
// flow scrollback + viewport, restore the active screen and modes, restore
// the cursor. A delta frame clears and repaints only the changed rows.
package rendergrid

import (
	"encoding/json"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
)

// CurrentFormat is the format tag GhosttyKit emits today.
const CurrentFormat = "mosaic.render-grid.v1"

// legacyFormat remains accepted so cached frames from older builds decode.
const legacyFormat = "cmux.render-grid.v1"

// Screen selects which terminal screen a full snapshot represents.
type Screen string

const (
	ScreenPrimary   Screen = "primary"
	ScreenAlternate Screen = "alternate"
)

// CursorStyle mirrors the Swift Cursor.Style enum.
type CursorStyle string

const (
	CursorBlock       CursorStyle = "block"
	CursorBar         CursorStyle = "bar"
	CursorUnderline   CursorStyle = "underline"
	CursorBlockHollow CursorStyle = "block_hollow"
)

// Cursor is the cursor position and shape carried by a frame.
type Cursor struct {
	Row      int         `json:"row"`
	Column   int         `json:"column"`
	Visible  bool        `json:"visible"`
	Style    CursorStyle `json:"style"`
	Blinking bool        `json:"blinking"`
}

func (c *Cursor) UnmarshalJSON(data []byte) error {
	type wire struct {
		Row      int          `json:"row"`
		Column   int          `json:"column"`
		Visible  *bool        `json:"visible"`
		Style    *CursorStyle `json:"style"`
		Blinking *bool        `json:"blinking"`
	}
	var w wire
	if err := json.Unmarshal(data, &w); err != nil {
		return err
	}
	c.Row, c.Column = w.Row, w.Column
	c.Visible = w.Visible == nil || *w.Visible
	c.Style = CursorBlock
	if w.Style != nil {
		c.Style = *w.Style
	}
	c.Blinking = w.Blinking != nil && *w.Blinking
	return nil
}

// Style is one entry of the frame's style table. Colors are "#rrggbb" (or
// bare "rrggbb") strings; nil means the terminal default.
type Style struct {
	ID            int     `json:"id"`
	Foreground    *string `json:"foreground,omitempty"`
	Background    *string `json:"background,omitempty"`
	Bold          bool    `json:"bold"`
	Faint         bool    `json:"faint"`
	Italic        bool    `json:"italic"`
	Underline     bool    `json:"underline"`
	Blink         bool    `json:"blink"`
	Inverse       bool    `json:"inverse"`
	Invisible     bool    `json:"invisible"`
	Strikethrough bool    `json:"strikethrough"`
	Overline      bool    `json:"overline"`
}

// RowSpan is a run of styled text at a grid position.
type RowSpan struct {
	Row       int    `json:"row"`
	Column    int    `json:"column"`
	StyleID   int    `json:"style_id"`
	Text      string `json:"text"`
	CellWidth *int   `json:"cell_width,omitempty"`
}

func (s RowSpan) gridCellWidth() int {
	if s.CellWidth != nil {
		return *s.CellWidth
	}
	return utf8.RuneCountInString(s.Text)
}

// ModeSetting is one DEC private or ANSI mode restored on a full snapshot.
type ModeSetting struct {
	Code int  `json:"code"`
	ANSI bool `json:"ansi"`
	On   bool `json:"on"`
}

// Frame is the render-grid snapshot DTO (wire keys are snake_case).
type Frame struct {
	Format              string        `json:"format"`
	SurfaceID           string        `json:"surface_id"`
	StateSeq            uint64        `json:"state_seq"`
	Columns             int           `json:"columns"`
	Rows                int           `json:"rows"`
	Cursor              *Cursor       `json:"cursor,omitempty"`
	Full                bool          `json:"full"`
	ClearedRows         []int         `json:"cleared_rows"`
	Styles              []Style       `json:"styles"`
	RowSpans            []RowSpan     `json:"row_spans"`
	ActiveScreen        Screen        `json:"active_screen"`
	Modes               []ModeSetting `json:"modes"`
	TerminalForeground  *string       `json:"terminal_foreground,omitempty"`
	TerminalBackground  *string       `json:"terminal_background,omitempty"`
	TerminalCursorColor *string       `json:"terminal_cursor_color,omitempty"`
	ScrollbackRows      int           `json:"scrollback_rows"`
	ScrollbackSpans     []RowSpan     `json:"scrollback_spans"`
}

// Decode parses and validates a render-grid frame, applying the same decode
// defaults as the Swift implementation (full=true, styles=[default], ...).
func Decode(data []byte) (Frame, error) {
	type wire struct {
		Format              string        `json:"format"`
		SurfaceID           string        `json:"surface_id"`
		StateSeq            uint64        `json:"state_seq"`
		Columns             int           `json:"columns"`
		Rows                int           `json:"rows"`
		Cursor              *Cursor       `json:"cursor"`
		Full                *bool         `json:"full"`
		ClearedRows         []int         `json:"cleared_rows"`
		Styles              []Style       `json:"styles"`
		RowSpans            []RowSpan     `json:"row_spans"`
		ActiveScreen        *Screen       `json:"active_screen"`
		Modes               []ModeSetting `json:"modes"`
		TerminalForeground  *string       `json:"terminal_foreground"`
		TerminalBackground  *string       `json:"terminal_background"`
		TerminalCursorColor *string       `json:"terminal_cursor_color"`
		ScrollbackRows      *int          `json:"scrollback_rows"`
		ScrollbackSpans     []RowSpan     `json:"scrollback_spans"`
	}
	var w wire
	if err := json.Unmarshal(data, &w); err != nil {
		return Frame{}, fmt.Errorf("rendergrid: %w", err)
	}
	f := Frame{
		Format:              w.Format,
		SurfaceID:           w.SurfaceID,
		StateSeq:            w.StateSeq,
		Columns:             w.Columns,
		Rows:                w.Rows,
		Cursor:              w.Cursor,
		Full:                w.Full == nil || *w.Full,
		ClearedRows:         w.ClearedRows,
		Styles:              w.Styles,
		RowSpans:            w.RowSpans,
		ActiveScreen:        ScreenPrimary,
		Modes:               w.Modes,
		TerminalForeground:  w.TerminalForeground,
		TerminalBackground:  w.TerminalBackground,
		TerminalCursorColor: w.TerminalCursorColor,
		ScrollbackSpans:     w.ScrollbackSpans,
	}
	if w.ActiveScreen != nil {
		f.ActiveScreen = *w.ActiveScreen
	}
	if w.ScrollbackRows != nil {
		f.ScrollbackRows = *w.ScrollbackRows
	}
	if err := f.normalize(); err != nil {
		return Frame{}, err
	}
	return f, nil
}

// normalize applies the Swift initializer's validation and canonicalization.
func (f *Frame) normalize() error {
	if f.Format != CurrentFormat && f.Format != legacyFormat {
		return fmt.Errorf("rendergrid: invalid format %q", f.Format)
	}
	f.Format = CurrentFormat
	if f.Columns <= 0 || f.Rows <= 0 {
		return fmt.Errorf("rendergrid: invalid dimensions %dx%d", f.Columns, f.Rows)
	}
	if c := f.Cursor; c != nil && (c.Row < 0 || c.Row >= f.Rows || c.Column < 0 || c.Column >= f.Columns) {
		return fmt.Errorf("rendergrid: invalid cursor %d,%d", c.Row, c.Column)
	}
	for _, row := range f.ClearedRows {
		if row < 0 || row >= f.Rows {
			return fmt.Errorf("rendergrid: invalid row %d", row)
		}
	}
	if len(f.Styles) == 0 {
		f.Styles = []Style{{ID: 0}}
	}
	styleIDs := make(map[int]bool, len(f.Styles))
	for _, s := range f.Styles {
		styleIDs[s.ID] = true
	}
	validateSpans := func(spans []RowSpan, rows int) error {
		for _, span := range spans {
			if span.Row < 0 || span.Row >= rows {
				return fmt.Errorf("rendergrid: invalid row %d", span.Row)
			}
			if span.Column < 0 || span.Column >= f.Columns {
				return fmt.Errorf("rendergrid: invalid column %d", span.Column)
			}
			if !styleIDs[span.StyleID] {
				return fmt.Errorf("rendergrid: invalid style id %d", span.StyleID)
			}
			width := span.gridCellWidth()
			if width <= 0 || span.Column+width > f.Columns {
				return fmt.Errorf("rendergrid: invalid span width %d at %d,%d", width, span.Row, span.Column)
			}
		}
		return nil
	}
	if err := validateSpans(f.RowSpans, f.Rows); err != nil {
		return err
	}
	if f.ScrollbackRows < 0 {
		f.ScrollbackRows = 0
	}
	if err := validateSpans(f.ScrollbackSpans, f.ScrollbackRows); err != nil {
		return err
	}
	if f.Full {
		f.ClearedRows = nil
	} else {
		f.ClearedRows = uniqueSorted(f.ClearedRows)
		f.ScrollbackRows = 0
		f.ScrollbackSpans = nil
	}
	return nil
}

func uniqueSorted(values []int) []int {
	seen := make(map[int]bool, len(values))
	out := make([]int, 0, len(values))
	for _, v := range values {
		if !seen[v] {
			seen[v] = true
			out = append(out, v)
		}
	}
	sort.Ints(out)
	return out
}

// screenSwitchModeCodes are never replayed from Modes; the active screen is
// restored explicitly (replaying them would double-switch).
var screenSwitchModeCodes = map[int]bool{47: true, 1047: true, 1048: true, 1049: true}

// VTBytes synthesizes the escape-sequence byte stream that reproduces the
// frame when fed to a terminal emulator (Swift: vtPatchBytes /
// vtReplacementBytes — the stream both replaces a full screen and patches a
// delta depending on Full).
func (f Frame) VTBytes() []byte {
	if f.Full {
		return f.fullSnapshotBytes()
	}
	return f.deltaPatchBytes()
}

func (f Frame) stylesByID() map[int]Style {
	m := make(map[int]Style, len(f.Styles))
	for _, s := range f.Styles {
		m[s.ID] = s
	}
	return m
}

func (f Frame) deltaPatchBytes() []byte {
	var b []byte
	styles := f.stylesByID()
	defaultStyle := styles[0]
	rowSet := make(map[int]bool, len(f.ClearedRows)+len(f.RowSpans))
	for _, r := range f.ClearedRows {
		rowSet[r] = true
	}
	for _, s := range f.RowSpans {
		rowSet[s.Row] = true
	}
	rows := make([]int, 0, len(rowSet))
	for r := range rowSet {
		rows = append(rows, r)
	}
	sort.Ints(rows)
	for _, row := range rows {
		b = append(b, sgrBytes(defaultStyle)...)
		b = append(b, fmt.Sprintf("\x1b[%d;1H\x1b[2K", row+1)...)
	}
	activeStyleID := -1
	for _, span := range f.RowSpans {
		b = append(b, fmt.Sprintf("\x1b[%d;%dH", span.Row+1, span.Column+1)...)
		if activeStyleID != span.StyleID {
			if style, ok := styles[span.StyleID]; ok {
				b = append(b, sgrBytes(style)...)
				activeStyleID = span.StyleID
			}
		}
		b = append(b, vtPrintableBytes(span.Text)...)
	}
	b = append(b, sgrBytes(defaultStyle)...)
	// A delta never hides the cursor while painting, so it leaves a nil
	// cursor untouched instead of forcing it visible.
	if c := f.Cursor; c != nil {
		b = append(b, cursorStyleBytes(*c)...)
		if c.Visible {
			b = append(b, fmt.Sprintf("\x1b[?25h\x1b[%d;%dH", c.Row+1, c.Column+1)...)
		} else {
			b = append(b, "\x1b[?25l"...)
		}
	}
	return b
}

func (f Frame) fullSnapshotBytes() []byte {
	var b []byte
	styles := f.stylesByID()
	defaultStyle := styles[0]

	// Reset to a known state and clear the client's saved lines before
	// flowing the host scrollback (RIS alone does not reliably erase
	// emulator scrollback).
	b = append(b, "\x1bc\x1b[3J"...)
	b = append(b, "\x1b[?2026h"...)

	// Dynamic default colors (OSC 10/11/12).
	b = append(b, oscColorBytes(10, f.TerminalForeground)...)
	b = append(b, oscColorBytes(11, f.TerminalBackground)...)
	b = append(b, oscColorBytes(12, f.TerminalCursorColor)...)

	// Paint with autowrap and the cursor off.
	b = append(b, "\x1b[?7l\x1b[?25l"...)
	b = append(b, sgrBytes(defaultStyle)...)

	if f.ActiveScreen == ScreenAlternate {
		// Scrollback belongs to the primary screen; flow it there first,
		// then enter the alternate screen and paint the TUI viewport.
		b = f.appendFlowLines(b, f.ScrollbackSpans, f.ScrollbackRows, styles, defaultStyle, true)
		b = append(b, "\x1b[?1049h"...)
		b = append(b, sgrBytes(defaultStyle)...)
		b = f.appendFlowLines(b, f.RowSpans, f.Rows, styles, defaultStyle, false)
	} else {
		// Primary: scrollback then the viewport as one continuous flow.
		offset := make([]RowSpan, 0, len(f.ScrollbackSpans)+len(f.RowSpans))
		offset = append(offset, f.ScrollbackSpans...)
		for _, span := range f.RowSpans {
			span.Row += f.ScrollbackRows
			offset = append(offset, span)
		}
		b = f.appendFlowLines(b, offset, f.ScrollbackRows+f.Rows, styles, defaultStyle, false)
	}

	// Reapply modes last so autowrap returns to its captured value.
	for _, mode := range f.Modes {
		if screenSwitchModeCodes[mode.Code] {
			continue
		}
		b = append(b, modeBytes(mode)...)
	}

	b = f.appendCursorRestore(b, defaultStyle)
	b = append(b, "\x1b[?2026l"...)
	return b
}

// appendFlowLines paints lines 0..lineCount as a natural scrolling flow:
// each line resets to the default style, positions its spans with CHA, and
// is separated from the next by CRLF.
func (f Frame) appendFlowLines(b []byte, spans []RowSpan, lineCount int, styles map[int]Style, defaultStyle Style, terminateLast bool) []byte {
	if lineCount <= 0 {
		return b
	}
	spansByRow := make(map[int][]RowSpan)
	for _, span := range spans {
		spansByRow[span.Row] = append(spansByRow[span.Row], span)
	}
	for line := 0; line < lineCount; line++ {
		if line > 0 {
			b = append(b, "\r\n"...)
		}
		b = append(b, sgrBytes(defaultStyle)...)
		activeStyleID := 0
		lineSpans := append([]RowSpan(nil), spansByRow[line]...)
		sort.SliceStable(lineSpans, func(i, j int) bool { return lineSpans[i].Column < lineSpans[j].Column })
		for _, span := range lineSpans {
			b = append(b, fmt.Sprintf("\x1b[%dG", span.Column+1)...)
			if activeStyleID != span.StyleID {
				if style, ok := styles[span.StyleID]; ok {
					b = append(b, sgrBytes(style)...)
					activeStyleID = span.StyleID
				}
			}
			b = append(b, vtPrintableBytes(span.Text)...)
		}
	}
	if terminateLast {
		b = append(b, "\r\n"...)
	}
	return b
}

func (f Frame) appendCursorRestore(b []byte, defaultStyle Style) []byte {
	b = append(b, sgrBytes(defaultStyle)...)
	c := f.Cursor
	if c == nil {
		return append(b, "\x1b[?25h"...)
	}
	b = append(b, cursorStyleBytes(*c)...)
	if c.Visible {
		b = append(b, fmt.Sprintf("\x1b[?25h\x1b[%d;%dH", c.Row+1, c.Column+1)...)
	} else {
		b = append(b, fmt.Sprintf("\x1b[?25l\x1b[%d;%dH", c.Row+1, c.Column+1)...)
	}
	return b
}

func modeBytes(mode ModeSetting) []byte {
	prefix := "\x1b[?"
	if mode.ANSI {
		prefix = "\x1b["
	}
	suffix := "l"
	if mode.On {
		suffix = "h"
	}
	return []byte(prefix + strconv.Itoa(mode.Code) + suffix)
}

func oscColorBytes(ps int, hex *string) []byte {
	r, g, bl, ok := rgbComponents(hex)
	if !ok {
		return nil
	}
	return []byte(fmt.Sprintf("\x1b]%d;rgb:%02x/%02x/%02x\x1b\\", ps, r, g, bl))
}

// vtPrintableBytes strips control characters so span text cannot inject
// escape sequences; anything below 0x20 or DEL becomes a space.
func vtPrintableBytes(text string) []byte {
	var sb strings.Builder
	sb.Grow(len(text))
	for _, r := range text {
		if r >= 0x20 && r != 0x7F {
			sb.WriteRune(r)
		} else {
			sb.WriteByte(' ')
		}
	}
	return []byte(sb.String())
}

func sgrBytes(style Style) []byte {
	codes := []string{"0"}
	if style.Bold {
		codes = append(codes, "1")
	}
	if style.Faint {
		codes = append(codes, "2")
	}
	if style.Italic {
		codes = append(codes, "3")
	}
	if style.Underline {
		codes = append(codes, "4")
	}
	if style.Blink {
		codes = append(codes, "5")
	}
	if style.Inverse {
		codes = append(codes, "7")
	}
	if style.Invisible {
		codes = append(codes, "8")
	}
	if style.Strikethrough {
		codes = append(codes, "9")
	}
	if style.Overline {
		codes = append(codes, "53")
	}
	if r, g, b, ok := rgbComponents(style.Foreground); ok {
		codes = append(codes, fmt.Sprintf("38;2;%d;%d;%d", r, g, b))
	}
	if r, g, b, ok := rgbComponents(style.Background); ok {
		codes = append(codes, fmt.Sprintf("48;2;%d;%d;%d", r, g, b))
	}
	return []byte("\x1b[" + strings.Join(codes, ";") + "m")
}

func cursorStyleBytes(c Cursor) []byte {
	var parameter int
	switch c.Style {
	case CursorUnderline:
		parameter = 4
		if c.Blinking {
			parameter = 3
		}
	case CursorBar:
		parameter = 6
		if c.Blinking {
			parameter = 5
		}
	default: // block, block_hollow
		parameter = 2
		if c.Blinking {
			parameter = 1
		}
	}
	return []byte(fmt.Sprintf("\x1b[%d q", parameter))
}

func rgbComponents(value *string) (r, g, b int, ok bool) {
	if value == nil {
		return 0, 0, 0, false
	}
	v := strings.TrimPrefix(*value, "#")
	if len(v) != 6 {
		return 0, 0, 0, false
	}
	raw, err := strconv.ParseInt(v, 16, 32)
	if err != nil {
		return 0, 0, 0, false
	}
	return int(raw >> 16 & 0xFF), int(raw >> 8 & 0xFF), int(raw & 0xFF), true
}
