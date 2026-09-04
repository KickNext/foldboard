# Board behaviour

Foldboard lets a person and an AI agent edit the same plan without sharing the
whole plan as context. The person works on one visible level; the agent reads
and edits bounded areas through [WebMCP](webmcp.md).

## Context model

- A project is one complete plan.
- The board root and every fold are levels.
- Only one level is open for human editing.
- Overview and Trace read across levels without changing the board.
- Agent reads do not navigate the interface. Navigation is explicit.
- A request captures its target, level, revision and viewport when writing
  starts.

## Projects and storage

Projects are independent boards stored in the browser. The first launch creates
`My project` with id `main`.

- **New project** creates an empty board.
- **Duplicate project** copies the board but not agent requests.
- **Remove project** removes it from the catalogue; the notice can restore it.
- The current board is saved before switching. A failed save blocks the switch.
- A damaged catalogue is reported and never overwritten automatically.

The catalogue is stored in `foldboard.projects`; boards use
`foldboard.project.<id>.board`. There are no format migrations.

## Editing a level

- **Add block** creates one plan item.
- **Add fold** creates a card with its own inner level.
- **Open fold** enters that level; the back button goes up or returns to
  Projects from the root.
- **Details** edits a card's name and description. **Move to level** reparents
  it.
- **Draw arrow** connects two blocks or folds. `Escape` cancels.
- **Tidy** arranges only the current level. Child levels and the camera stay
  unchanged; **Fit** remains a separate action.

The bottom dock contains selection, panning and creation tools. Level path,
Undo and Redo are at the top left; zoom is at the bottom right. Search, export,
requests and settings are in the header.

## Connections and external cards

An arrow cannot connect a card to itself or to a fold that contains it,
including any ancestor. UI edits, imports and WebMCP writes enforce this
atomically. Peer cycles remain allowed.

A connection crossing a fold boundary appears inside it as an **external
card**. The card points to the original rather than duplicating it.

- Click once to select; double-click to open the original.
- Editing it edits the original.
- Disconnecting it removes only connections to the current level.
- It cannot be moved or copied as an independent object.

Several underlying connections may appear as one projected arrow. Deleting it
states how many connections will be removed.

## Search and navigation

`Ctrl/⌘ F` searches names and descriptions across the whole project. Results
show the item type and fold path. `Enter` reveals the selected result on its
level; `Escape` closes search. Search never changes board data.

Keyboard navigation:

- `Tab` focuses visible cards.
- `Enter` opens details, enters a fold or follows an external card.
- Arrow keys move an ordinary card by 10 units; `Shift` moves it by 40.
- `?` opens the shortcut reference.

## History and write safety

- Undo and Redo keep the last 100 actions per project until the tab reloads.
- A drag is one action; continuous typing is merged.
- One tab owns write access through Web Locks. Other tabs are read-only.
- Storage versions are checked before writes. Conflicts never overwrite newer
  data.
- Agent writes are rejected while the person is dragging.
- Agent batches can be undone as one action, but never after a later human
  change.

**Import JSON** validates files up to 10 MB before replacing the current board,
asks for confirmation and supports Undo. Other projects are unaffected.

## Duplicate and clipboard

**Duplicate** (`Ctrl/⌘ D`) copies a block or a complete fold next to the
original. A fold copy includes nested folds, cards and arrows fully contained
inside it. Boundary-crossing arrows are not copied.

**Copy / Paste** (`Ctrl/⌘ C`, `Ctrl/⌘ V`) uses a snapshot taken at copy time and
can paste it into another level. New ids are generated and the whole operation
is one Undo step. External cards cannot be copied.

## Overview

Overview is a flat, read-only map of the project. It shows every block on one
canvas, hides folds and replaces paths through folds with direct arrows. It can
be panned and zoomed but never edits the board.

## Trace

Trace turns one path across levels into a line without changing the board.

- Steps follow arrow order; external cards resolve to their originals.
- Crossed folds appear as collapsible bands.
- The longest continuation is shown first; alternatives remain as branches.
- Cross-level arrows are marked.
- `Read` shows full names and descriptions; `Copy as Markdown` copies them.

Press `T` with one selected card to trace through it. Two selected cards trace
the segment between them; no selection traces the longest chain. Either end can
be pinned to any card. Using the same card at both ends traces its loop once.
`Enter` opens a step at its source level and `Esc` returns to the previous view.

Editing names or descriptions in `Read` changes the source cards. Step order is
not editable because it comes from arrows.

## Requests

**Ask agent** attaches a request to a card or arrow. With no selection, a
request created from **Agent requests** targets the current level.

Pending requests appear on the board and in the request panel. Handled requests
keep the agent's response. Removing a request never removes board objects.
Failed saves preserve the draft, and leaving with an unsaved draft requires
confirmation.

Saving a request does not start an agent. Requests are stored separately in
`foldboard.project.<projectId>.requests`; they do not change the board revision,
participate in Undo or appear in JSON exports.

## Export

**Export project** provides:

- **JSON** — exact, re-importable board; the backup format.
- **PNG** — the current level without interface controls or selection.
- **Mermaid** — a `flowchart LR` with folds as nested `subgraph`s.
- **Markdown** — a coordinate-free plan for people and agents.

Exports do not include agent requests or replies.

## Settings and runtime

Settings control Dark, Light or System appearance, grid visibility and agent
access. Preferences are stored separately from projects in
`foldboard.settings`. Resetting settings does not reset boards.

The interface locale is en-US. Strings live in `lib/l10n/app_en.arb`; generated
files in `lib/l10n/generated` must not be edited by hand.

CanvasKit cannot use system fonts. Inter is bundled in `assets/fonts`; release
builds must use `--no-web-resources-cdn` so CanvasKit and fallback fonts are
served locally. A correct release build makes no third-party requests.

`web/index.html` contains the splash, manifest links and social metadata.
Replace the relative `og-image.png` URLs with absolute URLs after choosing the
production domain.

## Verification

```bash
dart analyze
flutter test
flutter build web --release --no-web-resources-cdn
```
