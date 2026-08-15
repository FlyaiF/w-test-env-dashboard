# Log viewer selection research (日志文件)

Status: **research notes, no decisions** (2026-08-15). Research only — no code changed.

Question: how well does the current `SelectionArea` + `ListView.builder` rendering of the remote
log viewer actually behave under a rotating ring buffer, what do primary sources (Flutter API docs,
framework source, flutter/flutter issues) say, and what existing implementations could we adopt or
learn from. Companion to [remote-file-viewer.md](remote-file-viewer.md) (locked decision 6 covers
the current 64-line-chunk rendering).

## Current implementation (baseline)

- `apps/env_viewer/lib/pages/remote_files/remote_file_viewer.dart` — `_LineList`: `SelectionArea`
  wrapping a `ListView.builder` (`reverse: true` in 跟随 mode). Items are 64-line chunks, each one
  `Text.rich` paragraph, because `SelectionArea` joins per-widget selections without `\n`. A
  near-zero-height `\n` span is appended at chunk boundaries so copies keep line breaks.
- `apps/env_viewer/lib/services/remote_file/line_buffer.dart` — `LineBuffer`: ring of 10,000
  raw-byte lines; eviction is `_lines.removeRange(0, ...)` from the front, so once the buffer is
  full every retained line's index shifts on each committed line. `totalAppended` counts lines ever
  appended, including evicted ones.
- The session notifies listeners per stream chunk (unless 暂停), so the ListView rebuilds its built
  items on effectively every network chunk while tailing.

### Flutter version context

`apps/env_viewer/pubspec.yaml` pins Dart `sdk: ^3.11.4`; the local toolchain is Flutter 3.44.0
stable (Dart 3.12.0, 2026-05). The newer selection APIs discussed below (`SelectionListener`,
`SelectableRegionSelectionStatus`) shipped in **Flutter 3.29** (March 2025,
[What's new in Flutter 3.29](https://blog.flutter.dev/whats-new-in-flutter-3-29-f90c380c2317)), so
they are available to this repo without an SDK bump.

## Q1 — SelectionArea + ListView.builder, per primary sources

### How the framework stores a selection (and what rotation does to it)

Per the framework source
([`packages/flutter/lib/src/rendering/paragraph.dart`](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/rendering/paragraph.dart)):

- Each selectable paragraph registers `_SelectableFragment`s whose selection is stored as
  **`TextPosition` offsets** (`_textSelectionStart` / `_textSelectionEnd`) into that paragraph's
  text — not geometry. Selection geometry is recomputed from the offsets on demand
  (`getBoxesForSelection`).
- The `RenderParagraph.text` setter switches on `RenderComparison`. When the new text differs at
  layout level — which any changed line content is — it calls
  `_removeSelectionRegistrarSubscription(); _disposeSelectableFragments();
  _updateSelectionRegistrarSubscription();` i.e. **the old fragments (and any selection inside
  them) are destroyed and fresh, unselected fragments are registered**.
- If the text is *identical*, relayout preserves the selection (`performLayout` only calls
  `didChangeParagraphLayout()` on the surviving fragments).

So the answer to "does selection stick to geometry or to text offsets?" is: **offsets, per
paragraph — and it doesn't survive the paragraph's text changing at all**. It is not shifted, not
re-anchored, simply dropped for that paragraph, while untouched paragraphs keep theirs. Applied to
our chunking:

- **At capacity (steady tailing)**: front eviction shifts every line index, so **every** chunk's
  text changes on essentially every appended line → any in-progress or completed selection is wiped
  continuously. Selecting text in a full, fast-moving 跟随 tab is effectively impossible.
- **Below capacity, 跟随 mode**: the chunk-index mapping `chunk = chunkCount - 1 - i` remaps every
  visual item whenever a new chunk starts, so all built paragraphs get new text (selection wiped)
  roughly every 64 lines; between chunk boundaries only the newest chunk changes, so a selection in
  older chunks survives until the next boundary.
- **查看 (static) mode**: content is stable; per-paragraph selection behaves normally.

Additionally, when the ListView disposes items that scroll out of `cacheExtent`, their fragments
unregister from the `SelectableRegion` delegate (`remove()` in
[`selectable_region.dart`](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/selectable_region.dart)
clears the per-selectable internal state) — the selected content silently shrinks to whatever is
still built.

### Selection across virtualized items (select-all in a lazy list)

Known, still-relevant limitations, all from flutter/flutter:

- [#124078](https://github.com/flutter/flutter/issues/124078) — *[SelectionArea] Select all in
  ListView returns "Null check operator used on a null value"*. Select-all then scroll → crash;
  **open** as of 2026-08, P2, `c: crash`, `f: selection`, tracked under the team's "SelectableRegion
  Improvements" project. Related root cause:
  [#122725](https://github.com/flutter/flutter/issues/122725).
- [#153478](https://github.com/flutter/flutter/issues/153478) — *ListView in SelectionArea poor
  selection behavior and crashes when hitting Ctrl+A with finite cacheExtent*. Confirms Ctrl+A only
  selects what is within the cache range; closed as duplicate (of the above family). The only
  "workaround" noted is an effectively unbounded `cacheExtent`, which defeats virtualization.
- [#115787](https://github.com/flutter/flutter/issues/115787) — the
  `'!_selectionStartsInScrollable'` assertion family when combining SelectionArea with scrollables.

Bottom line: **content that isn't laid out cannot be selected**, select-all is bounded by
`cacheExtent`, and the crash issue is still open. This is why our 复制全部 toolbar action (copies
the whole `LineBuffer` directly) is the correct bulk-copy path, not Ctrl+A.

### Scrolling / rebuild interactions

- [#120892](https://github.com/flutter/flutter/issues/120892) — scrolling *on* selected text
  cleared the selection; **fixed** (PR #128765), so plain scrolling no longer drops selection.
- [#152420](https://github.com/flutter/flutter/issues/152420) — SelectionArea-in-scrollable jank,
  fixed and cherry-picked in 2024. Both are resolved in any Flutter this repo would use.
- [#154253](https://github.com/flutter/flutter/issues/154253) — line breaks lost when selecting via
  drag *handles* (touch); fixed. The desktop mouse path still concatenates **per-widget** plain
  text without separators — the documented reason for our 64-line chunks — and that behavior is in
  the selection plumbing, not fixed by the above.

### `reverse: true` and selection gestures

No primary source documents a selection defect specific to `reverse: true`. The only reversed-list
selection report found is [#141369](https://github.com/flutter/flutter/issues/141369) (reversed
ListView + text input: long-press selection steals focus/closes keyboard — mobile, not our
scenario). `reverse: true` only transforms scroll coordinates; the per-paragraph selection model
above is unaffected. Word/paragraph double- and triple-click gestures operate inside a single
paragraph and were not found to have reverse-specific issues. The real cost of `reverse: true` here
is indirect: it forces the shifting `chunkCount - 1 - i` index mapping that churns paragraph
contents (see above), and it's the reason chunk text changes even before the ring is full.

### Team guidance / newer selection APIs

- [`SelectableRegion` docs](https://api.flutter.dev/flutter/widgets/SelectableRegion-class.html)
  describe the selection tree (`SelectionContainer` / `Selectable` / `SelectionRegistrar`) and the
  supported actions (Copy, Select All). Notably, **neither the SelectableRegion nor the
  [`SelectionArea`](https://api.flutter.dev/flutter/material/SelectionArea-class.html) docs mention
  the lazy-scrollable limitation** — the issues above are the only authoritative record.
- Flutter 3.29 added observation APIs (announced in the
  [3.29 blog post](https://blog.flutter.dev/whats-new-in-flutter-3-29-f90c380c2317)):
  [`SelectionListener`](https://api.flutter.dev/flutter/widgets/SelectionListener-class.html)
  exposes `SelectionDetails` (start/end offsets, has-selection, collapsed) for a wrapped subtree,
  and `SelectableRegionSelectionStatusScope` exposes a `ValueListenable<SelectableRegionSelectionStatus>`
  that is `changing` during a mouse drag and `finalized` on release. These are **observation**
  APIs — they do not preserve a selection across content changes — but they make
  "freeze-the-buffer-while-selecting" trivial to detect.
- There is still no API to programmatically restore/re-anchor a `SelectionArea` selection after a
  rebuild, which rules out "save offsets, rotate, re-apply" schemes.

### Keyboard copy and context menu on desktop

`SelectableRegion` registers `CopySelectionTextIntent` and `SelectAllTextIntent` actions, so
Cmd/Ctrl+C and Cmd/Ctrl+A work when the region has focus (bindings come from
`DefaultTextEditingShortcuts`). Right-click (`_handleRightClickDown` in
[`selectable_region.dart`](https://github.com/flutter/flutter/blob/master/packages/flutter/lib/src/widgets/selectable_region.dart)):
on macOS/Linux/Windows, a right-click inside an existing selection shows the toolbar at the click;
outside it, the selection is first collapsed/moved. `SelectionArea.contextMenuBuilder` customizes
the menu. Known desktop quirk: right-click deselects other widgets'
selections ([#150268](https://github.com/flutter/flutter/issues/150268), and a web-specific
post-context-menu gesture bug [#169149](https://github.com/flutter/flutter/issues/169149)).
Practical consequence for us: Cmd/Ctrl+C on a drag selection works; Cmd/Ctrl+A is the dangerous
path (cache-bounded + open crash #124078) and 复制全部 should remain the promoted bulk action.

## Q2 — Survey of existing implementations

### xterm.dart (`xterm` on pub.dev)

[pub.dev/packages/xterm](https://pub.dev/packages/xterm) — full terminal emulator widget.
v4.0.0, published ~2024 (about 2 years old as of 2026-08); 237 likes, ~291k downloads; MIT;
verified publisher terminal.studio; all six platforms including Windows/macOS/Linux.

- **Feeding it**: `terminal.write(...)` works without a PTY
  ([README](https://github.com/TerminalStudio/xterm.dart)) — we could decode our `LineBuffer` lines
  and write them (converting `\n` → `\r\n`, using ANSI SGR codes for the ERROR/WARN coloring).
- **Ring + selection done right**: the scrollback is a fixed-capacity circular buffer
  (`IndexAwareCircularBuffer<BufferLine>` in
  [`lib/src/core/buffer/buffer.dart`](https://github.com/TerminalStudio/xterm.dart/blob/master/lib/src/core/buffer/buffer.dart));
  cell anchors (used for selection) are tracked against absolute buffer positions, so **selection
  survives — and correctly follows — buffer rotation**, the exact property `SelectionArea` lacks.
  `TerminalController` exposes `selection` (a `BufferRange`), `setSelection`, `clearSelection`, and
  block/line selection modes
  ([API docs](https://pub.dev/documentation/xterm/latest/xterm/TerminalController-class.html));
  the app extracts selected text from the buffer range and wires its own copy shortcut.
- **Costs**: terminal semantics (fixed column width with terminal-style hard wrapping, no native
  free-form text layout), copy/shortcut wiring is manual, the widget is a custom render object so
  it does not participate in `SelectionArea`/platform text services, and v4.0.0 has had no release
  in ~2 years (repo still receives commits/issues; 77 open issues).

### Flutter DevTools console & logging views (production precedent)

Source read from [flutter/devtools](https://github.com/flutter/devtools), `packages/devtools_app`:

- **Debugger console** (`lib/src/shared/console/console.dart`, used by
  `widgets/console_pane.dart`): `Scrollbar > SelectionArea > ListView.separated` with **one
  `Text.rich` per line** (ANSI escape parsing into spans). Follow mode is **not** `reverse: true`:
  a normal top-down list plus explicit auto-scroll — a post-frame `autoScrollToBottom()` gated by a
  `_scrollToBottom` flag, with an `_onScrollChanged` listener that detects the user scrolling up
  and disables sticking (`_considerScrollAtBottom = false`). Bulk copy is a dedicated
  `CopyToClipboardControl` whose `dataProvider` joins the whole backing buffer with `\n` — i.e.
  the Flutter team also **does not rely on in-list selection for bulk copy**, and lives with the
  per-widget-selection newline-join limitation for drag selections.
- **Logging screen** (`lib/src/screens/logging/`): the table rows are plain `RichText`
  (`_message_column.dart`) — *not selectable at all*; selection/copy happens in the details pane
  (`_log_details.dart`), which wraps a single `Text.rich` of one log record in a `SelectionArea`
  plus a copy button. Pattern: **select in a small, stable detail surface; never in the streaming
  list**.

### In-app log viewer packages

- [`talker_flutter`](https://pub.dev/packages/talker_flutter) 5.1.20 (2026-07), 659 likes, MIT:
  `TalkerScreen` renders each entry as a card of plain `Text` widgets with a **per-entry copy
  button** (`data_card.dart` in [Frezyx/talker](https://github.com/Frezyx/talker)) plus share/save
  of full history. No free text selection.
- [`logarte`](https://pub.dev/packages/logarte) 1.5.0 (2026-07), 248 likes, MIT: in-app console
  with copy/export actions (incl. copy-as-cURL); again action-based copying, not selection.
- [`flutter_logs`](https://pub.dev/packages/flutter_logs) 2.2.7, Apache-2.0: file-based logging,
  ships no viewer UI at all.

Conclusion: no surveyed log package solves in-stream selection; they all route copying through
explicit per-entry or whole-buffer actions.

### List/selection alternatives

- [`super_sliver_list`](https://pub.dev/packages/super_sliver_list) 0.4.1 (~2024), 299 likes, MIT
  (matejknopp.com): better variable-extent layout and jump-to-index for huge lists. Its pub.dev
  docs make **no claim about SelectionArea integration** — it does not change the
  selection-vs-virtualization story, only scrolling quality. Useful only if we ever render one
  `Text` per line and need robust jump-to-line.
- [`selectable`](https://pub.dev/packages/selectable) 0.6.5 (2026-07), 79 likes, MIT: a pre-
  `SelectableRegion` custom selection toolkit that works inside a scrollable (needs the
  `ScrollController`); maintained for existing production apps, but its own README recommends
  evaluating Flutter's native selection first. It selects only laid-out text too, so it does not
  beat `SelectionArea` for our problem.

### The single-giant-paragraph approach

One `SelectableText.rich`/`Text.rich` holding all 10k lines in a `SingleChildScrollView` would fix
copy fidelity (one paragraph → real newlines, whole-buffer select-all) but fails on primary
evidence:

- [#52651](https://github.com/flutter/flutter/issues/52651) — TextPainter layout cost grows with
  total content length *even when the rendered display is unchanged*; there is no incremental
  relayout, so a tail append relays out the entire paragraph.
- [#114158](https://github.com/flutter/flutter/issues/114158) — editable text with thousands of
  lines / many `TextSpan`s becomes seconds-slow per change; our span count (per-line WARN/ERROR
  styling → up to 10k spans) is in that regime.
- [#92173](https://github.com/flutter/flutter/issues/92173) — `paragraph.layout()` is expensive in
  general.

No primary source pins an exact line-count threshold; the pattern in the issues is that cost is
O(total text) per change, which a `tail -f` stream pays per chunk. On top of that, every append is
a layout-level text change, so (per the `RenderParagraph` analysis above) **the selection would be
wiped on every appended line anyway** — worse than the current chunking. Rejected.

### Custom render object approaches

xterm.dart is the working existence proof (custom `RenderObject` + own buffer/selection/anchor
model). Nothing lighter-weight and maintained was found that provides "text-offset selection over a
rotating buffer" as a reusable widget outside a terminal emulator.

## Q3 — "Clear" over a rotating buffer (design precedent, brief)

Secondary sources are fine here:

- **Chrome DevTools console**: clear is a *view* operation (toolbar/`console.clear()`); the
  "Preserve log" toggle decides whether navigation wipes the view
  ([console reference](https://developer.chrome.com/docs/devtools/console/reference)). The
  underlying producer is unaffected; the console just drops what it displays.
- **VS Code output panel**: each output channel keeps a bounded scrollback (a ring — old lines fall
  off) and "Clear Output" empties the *view*; the extension keeps writing into the same channel.

The transferable model: when the producer rotates independently of the view (our `tail -f` + ring),
"clear" should be a **marker, not a buffer wipe** — remember the clear point and render only lines
after it. `LineBuffer.totalAppended` is already a monotonically increasing absolute line number, so
a clear marker is just `clearedBefore = totalAppended`, and it also survives ring eviction
naturally. (Not currently a feature; recorded as precedent in case 清空 is ever requested.)

## Implications for env_viewer (ranked options)

1. **Keep the chunked SelectionArea, fix chunk identity + freeze-on-select (recommended).**
   - Anchor chunks to *absolute* line numbers (derived from `totalAppended`) instead of buffer
     indices, and evict in whole-chunk multiples, so an existing chunk's text never changes once it
     is full — only the newest chunk mutates and eviction removes whole old chunks. Per the
     `RenderParagraph` source, identical text ⇒ fragments and selections survive rebuilds; that
     alone fixes "selection evaporates while tailing" everywhere except the live-edge chunk.
   - Use `SelectableRegionSelectionStatusScope` (available at this repo's Flutter) to suppress
     buffer-driven rebuilds while status is `changing` — the drag can't race rotation. Optionally
     auto-engage the existing 暂停 while a selection exists.
   - Route Cmd/Ctrl+A away from the region's cache-bounded select-all (open crash #124078) — e.g.
     map it to 复制全部 or a "select nothing, hint at 复制全部" behavior, mirroring DevTools's
     copy-all escape hatch.
   - Trade-offs: cross-chunk drags into the mutating newest chunk still drop; select-all semantics
     remain non-native; but the change is small, local, and keeps native look/feel and IME-free
     desktop selection.
2. **Freeze-only variant** (subset of 1): just pause-on-selection without re-anchoring chunks.
   Cheapest possible fix; selection still dies at every 64-line boundary while streaming below
   capacity, so it only really helps together with the chunk-identity fix — do both.
3. **Adopt xterm.dart for 跟随 tabs.** Structurally correct: circular buffer with absolute-position
   selection anchors means selection survives rotation by design; battle-tested rendering at 60fps.
   Costs: v4.0.0 is ~2 years without a release; terminal-style hard wrapping and column model;
   manual copy/shortcut wiring; ERROR/WARN coloring must become ANSI; two text stacks in one app
   (查看 mode would likely stay as-is). Justified only if selection-under-fast-tail becomes a hard
   requirement that option 1 doesn't satisfy.
4. **DevTools-style restructuring**: drop `reverse: true` for an explicit auto-scroll-to-bottom
   controller (removes the index remapping churn as a side effect) and/or add a per-range "detail"
   selection surface. Worth stealing the ideas — DevTools validates the copy-all escape hatch and
   the non-reversed follow — but as a whole it solves less than option 1 for more churn, and
   DevTools's per-line `Text` rendering re-introduces the missing-`\n` join we chunk to avoid.
5. **Single giant paragraph**: rejected outright — O(total) relayout per appended line (#52651,
   #114158) *and* full selection wipe on every append (RenderParagraph layout-change disposal).
