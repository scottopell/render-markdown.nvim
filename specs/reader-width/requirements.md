# Reader Width Feature

## User Story

As a markdown reader/writer, I need my markdown content to be constrained to a readable width and centered in my editor window, so that I have a comfortable, book-like reading experience without needing to manually resize my editor window or read across excessively wide lines.

## Requirements

### REQ-RW-001: Content Width Constraint

WHEN user sets `reader_width` to a positive integer (e.g., 80)
THE SYSTEM SHALL constrain all rendered markdown elements to that column width

WHEN user sets `reader_width` to 0
THE SYSTEM SHALL render content at full window width without constraint

WHEN rendered element would exceed `reader_width`
THE SYSTEM SHALL limit the element's width to `reader_width` columns

**Rationale:** Users want to control the maximum width of their markdown content for improved readability, similar to how books and articles use constrained column widths rather than full-page width.

---

### REQ-RW-002: Horizontal Centering

WHEN `reader_width` is set to a positive integer
THE SYSTEM SHALL horizontally center all constrained markdown elements within the window

WHEN window width is less than `reader_width`
THE SYSTEM SHALL render content at full window width without centering

WHEN window is resized
THE SYSTEM SHALL recalculate center offset and update element positions

**Rationale:** Centering the constrained content provides a balanced, aesthetically pleasing reading experience and prevents content from being stuck to the left edge of wide windows.

**Dependencies:** REQ-RW-001 (requires width constraint to determine center position)

---

### REQ-RW-003: Text Wrapping for Long Lines

WHEN `reader_width` is set to a positive integer
THE SYSTEM SHALL enable soft text wrapping (vim `wrap` option)

WHEN `reader_width` is set to a positive integer
THE SYSTEM SHALL enable word-boundary wrapping (vim `linebreak` option)

WHEN `reader_width` is set to a positive integer
THE SYSTEM SHALL enable indent preservation on wrapped lines (vim `breakindent` option)

WHEN `reader_width` is set to a positive integer
THE SYSTEM SHALL configure wrapped line indentation to align with centered content (vim `breakindentopt`)

WHEN user sets `reader_width` back to 0
THE SYSTEM SHALL restore previous window option values

**Rationale:** Long paragraphs need to wrap at word boundaries to maintain readability without horizontal scrolling. Wrapped lines must align with the centered, width-constrained content to preserve the focused reading experience. Note: Vim's wrapping occurs at window width, not at `reader_width` - the centering and width constraint apply to rendered elements, while wrapping ensures long lines remain readable.

**Dependencies:** REQ-RW-001 (text wrapping only makes sense with width constraint)

---

### REQ-RW-004: Configuration Interface

THE SYSTEM SHALL accept `reader_width` configuration as a non-negative integer

WHEN `reader_width` is set to 0 (default)
THE SYSTEM SHALL disable all reader width features

WHEN `reader_width` is set to a positive integer
THE SYSTEM SHALL apply width constraint, centering, and wrapping features

WHEN `reader_width` configuration is changed
THE SYSTEM SHALL apply new settings to currently open markdown buffers

**Rationale:** Users need a simple, documented configuration option to control the feature. Default of 0 ensures existing users see no behavior change until they opt in.

---

### REQ-RW-005: Element Types Coverage

WHEN `reader_width` is enabled
THE SYSTEM SHALL constrain and center paragraphs, headings, code blocks, lists, blockquotes, and horizontal rules to `reader_width`

WHEN `reader_width` is enabled
THE SYSTEM SHALL allow tables to exceed `reader_width` without horizontal centering or width constraint

**Rationale:** Users need a consistent, focused reading experience with all prose and code content centered within a comfortable column width. Tables are exempted because preserving table structure and column alignment is more important than width constraint - forcing tables to wrap within `reader_width` would make them unreadable by breaking column alignment.

---

### REQ-RW-006: Window Option Restoration

WHEN markdown buffer is first loaded with `reader_width` enabled
THE SYSTEM SHALL save current values of `wrap`, `linebreak`, and `breakindent` options

WHEN `reader_width` is disabled or changed to 0
THE SYSTEM SHALL restore saved window option values

WHEN buffer is unloaded or plugin detaches
THE SYSTEM SHALL restore saved window option values

**Rationale:** Users may have specific preferences for these window options. The plugin should not permanently change user settings, only temporarily apply them when reader_width is active.

---

### REQ-RW-007: Performance Constraint

WHEN `reader_width` is enabled on a markdown file
THE SYSTEM SHALL render initial view within 200ms for files under 10MB

WHEN window is resized
THE SYSTEM SHALL update centering within 100ms

**Rationale:** Reader width is a visual enhancement feature. It should not introduce noticeable performance degradation or lag during normal editing.

---

### REQ-RW-008: Edge Case - Narrow Windows

WHEN window width is less than `reader_width`
THE SYSTEM SHALL use full window width without adding horizontal scroll

WHEN window width is exactly `reader_width`
THE SYSTEM SHALL use full window width with no centering offset

**Rationale:** The feature should gracefully degrade on narrow windows. Adding centering padding that causes horizontal scrolling would harm usability.

---

### REQ-RW-009: Multiple Windows

WHEN same markdown buffer is displayed in multiple windows
THE SYSTEM SHALL apply `reader_width` settings independently per window

WHEN windows have different widths
THE SYSTEM SHALL calculate center offset independently per window

**Rationale:** Users may have split windows with different sizes. Each window should independently apply reader_width based on its own dimensions.

---

### REQ-RW-010: Render Elements with Zero User Margins

WHEN `reader_width` is enabled AND an element has zero user-configured margins
THE SYSTEM SHALL still render the element to apply centering

WHEN `reader_width` is disabled (value is 0) AND an element has zero user-configured margins
THE SYSTEM SHALL skip rendering the element (no visual changes needed)

**Rationale:** Users expect all content to be centered when `reader_width` is enabled, regardless of whether they've configured custom margins. Without this, elements with default zero margins would fail to render and wouldn't receive centering, creating an inconsistent reading experience where some content is centered and some is flush-left.

---
