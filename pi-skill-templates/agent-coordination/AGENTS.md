# Agent Coordination Rules

This repository is the authoritative coordination state for its coordination domain.
A domain can cover one or more implementation repositories, but each pi session
works in one implementation repository. Issue items belong to exactly one
registered repository namespace by path.

## Required rules

When Pi is launched through Pi-en and coordination helpers are available,
prefer the `pien coord ...` namespace, or the matching `pi-en-coord-*` helper,
over hand-editing item lifecycle state, repo registry structure, lint checks,
or generated coordination outputs. Use direct edits only for content the helpers
do not manage, and keep the file format rules below intact.

1. Treat this coordination repository as the only shared synchronization
   source for agent work state.
2. Pull/rebase before inspecting, selecting, creating, claiming, blocking,
   marking done, reviewing, verifying, closing, or otherwise modifying
   items.
3. Commit and push coordination changes immediately after changing shared
   state.
4. Never force-push, rewrite public history, delete done or closed items,
   or renumber item IDs. New naming rules do not justify rewriting
   historical items.
5. Prefer one claimed item per agent unless explicitly instructed
   otherwise.
6. Do not edit another agent's claimed item except to resolve a Git
   conflict, add clearly relevant factual information, or when coordination
   domain rules define it as stale or abandoned.
7. Record every meaningful state transition as a chronological YAML event
   with a linked Markdown message in the item file.
8. Link developer-completed work from done/link events to concrete
   structured implementation references with `repo`, `branch`, and
   `commit` fields.
9. Keep coordination changes small and reviewable.
10. Keep Git commit, tag, and other Git message text readable in standard
    terminals. Subject or summary lines should be at most 72 characters,
    and body paragraphs should be hard-wrapped at 72 characters where
    practical.
11. If a push or rebase conflict occurs, resolve it conservatively and
    preserve both agents' factual updates when possible.

## Item keys and IDs

Use the stored `item_key` for the project key portion of generated
coordination item IDs:

- coordination-domain defaults use top-level `PROJECT.md`;
- repo-scoped issue items use `repos/{repo_id}/REPO.md`.

Do not invent, rename, or silently change item keys. If a project key is
missing, derive it from the project name by uppercasing it and removing
delimiters and other non-alphanumeric characters, then commit that key in the
project metadata file. Changing an existing `item_key` requires an explicit
coordination-domain decision.

New item IDs use this shape and filenames use the item ID only:

```text
<PROJECTKEY>-<TYPECODE>-<YYYYMMDD-HHMMSS>-<NNN>.yaml
```

Built-in type codes are `ISS` for `issue`, `FRQ` for
`functional-requirement`, `QRQ` for `quality-requirement`, `CRQ` for
`constraint-requirement`, `TODO` for `todo`, `DEC` for `decision`, and `NOTE`
for `note`. The UTC timestamp records creation time.
The `NNN` collision/order suffix starts at `001` for each timestamp and is not
a global sequence number. Historical items may keep legacy IDs and slug
filenames.

## Item types and directories

Issue directory names are intentionally developer-centric and live under the
owning implementation repo namespace:

- `repos/{repo_id}/issues/open/`: developer work is available or required.
- `repos/{repo_id}/issues/blocked/`: developer work is required but cannot proceed yet.
- `repos/{repo_id}/issues/done/`: the developer believes implementation is complete; review
  and verification are still pending or in progress.
- `repos/{repo_id}/issues/closed/`: final accepted state after the item is done, reviewed,
  and verified.

Historical root `issues/{status}/` paths may exist during migration, but new
issue work should use `repos/{repo_id}/issues/{status}/`.

The completion metric for managers, reviewers, and testers is therefore not
"done". It is `status: closed` with `reviewed: true` and `verified: true`.

Other item types live under semantic type directories shared by the coordination
domain. All requirement classes use the single root-level `requirements/`
directory while preserving FRQ, QRQ, CRQ item-ID type codes. Decisions, domain
notes, and TODO items are also domain-common unless a local rule says
otherwise; TODO items use `todos/` and the `TODO` item-ID type code. Do not mirror issue
status directories in project test paths, and do not silently renumber or
rewrite historical items to fit newer conventions.

## Item format

Coordination items are YAML files under repo-scoped issue status directories or
shared semantic type directories.
Issue current state is stored near the top (`status`, `owner`, `updated`,
`done`, `closed`, `reviewed`, `verified`, `testable`, `testability_note`, and
`current`), while authoritative issue history is stored in chronological
`events` and linked Markdown `messages` entries. Requirement items are
current-state records under `requirements/`: they keep requirement metadata and
one top-level renderable `body: |-` block. For requirements, `id` is the
generated coordination item ID, while `requirement_key` is the stable public
requirement identifier such as `UC-001`, `CMD-004`, `AUTH-001`, `TEST-001`, or
`CRQ-001`; do not use generated item IDs as requirement keys. TODO items are
current-state records under `todos/` with one top-level `body: |-` block.
Requirement and TODO items must not contain top-level `current`, `events`, or
`messages` sections.

When changing requirements, update the corresponding requirement item first.
Then consult the current implementation repo's `repos/{repo_id}/REPO.md`
`domain_generated_files` metadata to see which domain-wide generated outputs,
such as `REQUIREMENTS.md` and `REQUIREMENTS_COVERAGE.md`, this repo commits.
Regenerate and commit only the generated files listed for the current repo; if
no matching path is declared, ask before updating generated outputs. Do not
edit generated files as the primary source for a requirement that already has
an active coordination requirement item.

Do not add or maintain a separate Markdown `## Activity` section in item files.
It duplicates issue event history and will drift.

## Behavior specification references

Issues may include `related_behaviors` containing immutable project-owned BHV
IDs. Keep the actual BHV YAML, glossary, adapter, fixtures, and lifecycle in
the implementation repository's tracked `pi-en-behaviors/` root; do not embed
BHV bodies in coordination items or use coordination lifecycle commands to
manage them.

## Testability and tests

Every item should declare either:

```yaml
testable: yes
testability_note: null
```

or:

```yaml
testable: no
testability_note: 'Brief rationale.'
```

Use `testable: yes` when the item requires a directly item-matched executable
bash script in the project repository. Use `testable: no` only for special
cases such as documentation-only work, policy decisions, legacy closed items
predating the convention, or explicit coverage by another requirement item.

Item-matched tests live in the owning implementation repo under `tests/items/`
and match the item ID exactly by filename stem. They mirror the root item type,
but not issue lifecycle status or repo namespace:

```text
tests/items/issues/<item-id>.sh
tests/items/requirements/<item-id>.sh
tests/items/todos/<item-id>.sh
```

Verification events should record exact commands run and pass/fail evidence.
Do not weaken unrelated previously passing tests to make a new done item pass
verification.

## State transitions

- Create: add a new YAML item under `repos/{repo_id}/issues/open/` or the
  appropriate shared typed directory, with `reviewed: false`,
  `verified: false`, `testable: yes` or `testable: no`, an `opened` event,
  and an initial message.
- Claim: keep the issue item under `open/`, set `status: claimed`, set
  `owner: <agent-id>`, update `updated:` and `current:`, append a `claimed`
  event and linked message, commit, and push.
- Block: move an issue to `blocked/` when needed, set `status: blocked`,
  document blocker details in a `blocked` event/message, commit, and push.
- Resume or unblock: move an issue back to `open/`, or keep claimed if the
  same agent continues the work, and append a `reopened` or `updated` event.
- Done: use `git mv` into `done/`, set `status: done`, set
  `done: <timestamp>`, keep `closed: null`, reset `reviewed: false` and
  `verified: false`, append a `done` event/message, and include structured
  implementation refs where possible: `repo: pi-en`, `branch: main`, and the
  full `commit` hash.
- Review pass: keep the item in `done/`, set `reviewed: true`, append a
  `reviewed` event/message, commit, and push.
- Review fail: move the item back to `open/`, set `status: open`, clear
  `owner: null`, reset `done: null`, `reviewed: false`, and
  `verified: false`, append a `review_failed` event/message explaining what
  must be fixed, commit, and push.
- Verification pass: keep the item in `done/`, set `verified: true`, append a
  `verified` event/message with test evidence, commit, and push.
- Verification fail: move the item back to `open/`, set `status: open`, clear
  `owner: null`, reset `done: null`, `reviewed: false`, and
  `verified: false`, append a `verification_failed` event/message with failing
  tests/items, commit, and push. Developers must fix their solution rather
  than weakening unrelated previously passing tests.
- Close: after `status: done`, `reviewed: true`, and `verified: true`, use
  `git mv` into `closed/`, set `status: closed`, set
  `closed: <timestamp>`, append a final `closed` event/message, commit, and
  push.
- Split: create new linked items and mark the relationship in `related:` or
  `split_from:` fields and an `updated` event.
- Supersede: leave the old item in place, mark it closed or superseded, and
  link to the replacement.

Do not encode important state only in a commit message. The file content must
remain understandable from a checkout.
