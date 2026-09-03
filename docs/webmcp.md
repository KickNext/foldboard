# WebMCP contract

Foldboard exposes one plan to a person and an AI agent while keeping each task
inside a bounded context. Agents inspect the outline, read only the required
area and apply revision-checked changes without taking over the person's view.

Foldboard registers 17 tools through
`document.modelContext.registerTool`, using the
[WebMCP draft API](https://webmachinelearning.github.io/webmcp/). Registration
is retried when the API appears late or the page regains focus. Registered tools
are not duplicated. The interface works without a WebMCP client.

## Collaboration rules

- Start with `get-outline`, then use `get-area` for the required fold.
- Reading never navigates the person's interface.
- Use `reveal-card` only when the person should be taken to a result.
- Validate writes and pass `expectedRevision` to reject stale context.
- Treat a plan as a directed flow, not a spatial list. Trace follows arrows;
  placing cards near each other does not connect them.
- Unless the person explicitly requests independent notes, connect every new
  card to the plan with `from` → `to` arrows in the same atomic batch.
- After a write, repair every `unconnected-card` warning and run
  `validate-architecture`.
- Writes are atomic and are rejected while the person is dragging.
- People can attach requests to cards, arrows or the current level.

Every board response includes `project`. Pass its `id` as `projectId` in later
calls so a project switch cannot redirect a write. On the Projects screen, open
a project before calling board tools.

## Tools

### Projects

- `list-projects` — list saved projects and `activeProjectId`.
- `create-project` — create and open a project. Use `clientRequestId` to make
  retries idempotent.
- `open-project` — save the current board and open another project. A failed
  save cancels the switch.

### Requests

- `list-requests` — list pending, handled or all requests. Default limit 20,
  maximum 100.
- `get-request` — get full text, targets, captured context, version and reply.
- `resolve-request` — mark a request handled using `expectedVersion`; optionally
  include a response up to 4000 characters.

### Reading and navigation

- `get-outline` — compact fold tree with names and counts. `maxDepth` defaults
  to 8; omitted branches are marked `truncated`.
- `get-area` — bounded, paginated projection of the root, a block or a fold.
- `get-architecture` — full document, revision and current-level view.
- `search-architecture` — paginated search over names and descriptions.
- `get-user-context` — current level, selection, mode, viewport, zoom and
  request counters.
- `reveal-card` — open a card's parent level, select it and move the camera.
  This changes navigation, not board data.
- `validate-architecture` — paginated warnings for disconnected cards, missing
  text, duplicate names and excessive nesting. It never edits the board.
- `get-changes` — compact patch or revision events since `sinceRevision`.
- `export-architecture` — export the whole board or one area as JSON.

### Writing

- `apply-changes` — apply one atomic batch or validate it without writing.
- `auto-arrange` — arrange the root, one fold or the person's current level.
  Child levels are unchanged.

## Recommended cycle

```text
list-projects
→ open-project when needed
→ get-outline
→ get-area
→ apply-changes(validate: true)
→ apply-changes(expectedRevision)
→ repair warnings when present
→ validate-architecture
→ get-changes(sinceRevision, historyId)
```

Use `get-architecture` only when the whole document is required. Write
responses default to `return: "summary"`; request `return: "full"` explicitly
when needed.

## Bounded context reads

`get-area` defaults:

- `maxDepth: 1` (range 0–8)
- `offset: 0`, `limit: 20` (maximum 100)
- `edgeOffset: 0`, `edgeLimit: 20` (maximum 100)
- `descriptionLimit: 500` (range 0–10000)
- `includeCoordinates: false`
- `includeView: false`

For a fold, its card is the first item and `maxDepth` controls how far its
contents expand. `nextOffset`, `nextEdgeOffset` and `depthTruncated` indicate
more data. Reset `edgeOffset` when changing `offset`. If `revision` changes
between pages, restart the read.

Results may reference ids outside the page and therefore carry `partial: true`.
Titles are limited to 160 characters and descriptions to `descriptionLimit`;
truncation flags identify cuts. `childCount` reports fold size.

Use `get-area(id, return: "full")` for the recursive area with neighbours and
ancestors. Without `id`, full mode returns the whole document.
`includeView: true` adds the entire level without paging and should be requested
only when required.

## Writing and dry runs

```json
{
  "expectedRevision": 0,
  "changes": {
    "nodes": [
      {
        "id": "editor",
        "title": "Editor",
        "description": "Works on the board",
        "x": 100,
        "y": 200
      },
      {
        "id": "graph",
        "title": "Graph",
        "x": 600,
        "y": 200
      }
    ],
    "edges": [
      {
        "id": "edit-graph",
        "from": "editor",
        "to": "graph"
      }
    ]
  }
}
```

Updates are matched by `id`; send only changed fields. `deleteIds` removes
objects and their dependencies. `parentId: null` moves an object to the root.
`replace: true` performs a full import. Invalid references or revision conflicts
cancel the whole batch.

An edge is directional: `from` is the upstream/source card and `to` is the
downstream/next card. Every related set of cards should form a traversable path;
branches and merges are valid. Isolated cards are appropriate only when the
person explicitly asks for independent notes. `apply-changes` returns a
`warnings` list when cards created by that batch have no connection. A warning
does not cancel the atomic write, so add the missing arrows in a follow-up batch.

Set `validate: true` to build and check the candidate without changing storage,
revision, Undo, selection or highlights. A dry run is allowed in read-only mode
but does not reserve its revision. Send the real write with the same
`expectedRevision` and handle `revision-conflict` if the board changed.

## Revisions and diffs

Human edits, agent edits, Undo and Redo share one revision log. History is kept
in memory for 128 revisions or one million JSON characters. Reloading or
reopening the project creates a new `historyId`.

To apply a diff locally:

1. Remove `deleteIds` from every collection without cascading.
2. Merge rows by `id`.
3. Replace `referencePositions` when present, including an empty object.

Compact mode returns one composed patch. Event mode returns each revision and
patch. If history is unavailable, the result is `history-expired`, never a
partial diff.

## Document schema

A document contains:

- `nodes`
- `groups`
- `edges`
- `revision`
- optional `referencePositions`

**Fold** is the product term; serialized folds live in `groups` and use
`parentId`. Group coordinates position the fold card on its parent level.
Arrows may reference node or group ids.

`view.cards` and `view.connections` are read-only projections. Do not import or
create them; edit projected connections through their `sourceEdgeIds`. Other
document shapes are rejected. There is no format version field.

## Requests from people

When writing starts, a request captures target ids and names, level, board
revision and viewport. Later selection changes do not redirect it. A request
may survive deletion of its target, which is then reported in
`missingTargetIds`.

Agent cycle:

```text
list-requests
→ get-request
→ inspect the current board
→ validate or apply changes
→ resolve-request(expectedVersion)
```

Resolving a request does not edit the board. Request versions are independent
of board revisions. Requests are stored separately, do not participate in Undo
and are not included in architecture JSON exports.

## Safety and errors

Errors return `ok: false`, a message, stable `code` and the current revision
when available. Main codes:

- `revision-conflict`
- `request-conflict`
- `unknown-id`
- `ancestor-arrow`
- `invalid-arguments`
- `read-only`
- `user-busy`
- `history-expired`
- `storage-conflict`
- `project-conflict`
- `no-project`
- `internal-error`

Never repeat a conflicting write blindly. Read the latest changes or request
first.

`Settings → Agent access → View only` blocks project creation, board writes,
request resolution and Tidy through WebMCP. Reads, export and explicit
navigation remain available. This controls the API, not browser UI automation.

After an agent write, changed cards and arrow endpoints are highlighted. The
person may undo the complete batch until another change follows it.

## Verification

```bash
node --test test/webmcp_registration_test.cjs
flutter test test/agent_protocol_test.dart test/token_budget_test.dart
```
