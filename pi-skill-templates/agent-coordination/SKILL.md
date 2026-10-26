# Agent Coordination

Use this skill when working in a project that contains a Git-backed agent
coordination repository, when asked to find, claim, or update work, or before
making changes that affect shared agent state. Pi-en coordination is attached
at the project-local `.pi-en/coordination` working clone by default. External
coordination working clones are not part of the automatic Pi-en workflow. A
coordination domain may span multiple implementation repositories, but each pi
session works in one implementation repository.

## Coordination repository

The coordination repository is the only synchronization source for agent issue,
TODO, and coordination state in its domain. Issues are repo-scoped under
`repos/{repo_id}/issues/{status}/`; requirements, decisions, and domain notes
remain shared at the domain root. Domain-wide generated files that are committed
to an implementation repo are declared in that repo's `repos/{repo_id}/REPO.md`
under `domain_generated_files`; ask before regenerating them when no matching
path is declared. For fresh Pi-en projects and automatic workflows, find the
clone at `<project>/.pi-en/coordination`; `PI_EN_COORD_DIR` should resolve to
that project-local checkout. The configured `coordination_remote` in
`.pi-en-coordination.yaml` is the source of truth for the Git remote, including
external local bare remotes, and any `.pi-en/agent-remotes/` entries for those
remotes are derived operational aliases.

## Required protocol

1. `cd "${PI_EN_COORD_DIR:-.pi-en/coordination}" && git pull --rebase` before
   reading or modifying coordination state, or use the `pi-en-coord-*` helpers
   with their default coordination directory resolution.
2. Inspect open, claimed, blocked, and done YAML issue items in the current
   repo namespace. Also inspect related requirement or decision items when
   they affect acceptance criteria.
3. Claim at most one issue item unless instructed otherwise.
4. When an active role is in effect, preserve it for coordination helpers with
   `--role ROLE` or `PI_EN_COORD_ROLE=ROLE`; item events should store the actor ID
   and role explicitly.
5. Commit and push immediately after claiming or changing status.
6. Do project work in the project repository.
7. Return to the coordination repo, pull/rebase, mark developer-completed work
   as `done` with a new event/message and implementation refs, then commit and
   push.
8. Review and verification act on `done` items. Review failures or test
   failures move the item back to `open` with factual failure evidence.
9. Move an item to `closed` only after it is `done`, `reviewed: true`, and
   `verified: true`.

## Repo namespaces, item keys, and IDs

Resolve the current repo id from `--repo-id`, `PI_EN_COORD_REPO_ID`, the
implementation root's `.pi-en-coordination.yaml`, or registry remote data.
The attachment file is a hint only; `repos/{repo_id}/REPO.md` and compatible
registry data are authoritative. Alias use should warn so callers update to the
canonical repo id. Cross-repo work should be split into one issue per repo and
linked by stable item IDs, not by paths that would change on repo rename.

Minimal implementation attachment file:

```yaml
version: 1
coordination_domain: my-product
coordination_remote: git@example.com:org/my-product-coordination.git
repo_id: backend-api
```

Use `pi-en-coord-repo add`, `rename`, and `retire` for repo-id lifecycle
changes. Add creates the manifest and issue status directories, rename moves
the namespace and records old ids as aliases, and retire preserves history
while blocking new issue creation by default.

## Item keys and IDs

Use stored `item_key` metadata when creating items. Domain item keys live in top-level `PROJECT.md`; repo issue keys may come from
`repos/{repo_id}/REPO.md`. Do not invent or silently change keys.

New item IDs and filenames use:

```text
<PROJECTKEY>-<TYPECODE>-<YYYYMMDD-HHMMSS>-<NNN>.yaml
```

Use `ISS` for issue, `FRQ` for functional requirement, `QRQ` for quality
requirement, `CRQ` for constraint requirement, `TODO` for todo, `DEC` for
decision, and `NOTE` for note. The `NNN`
suffix starts at
`001` for each UTC timestamp. Historical items may keep legacy IDs; do not
rename, renumber, rewrite, or move them unless explicitly directed. For
functional, quality, and constraint requirement items, pass an explicit
`--requirement-key`; the generated `id` is the coordination item ID, while
`requirement_key` is the stable public requirement identifier such as
`UC-001`, `CMD-004`, `AUTH-001`, `TEST-001`, or `CRQ-001`.

`pi-en-coord-list notes` and `pi-en-coord-list todos` report note and TODO
items by their YAML `status` values. `pi-en-coord-list requirements` reports
functional, quality, and constraint requirement items. Use `functional`,
`quality`, or `constraint` for class-specific listings.

## Item history

Coordination items are YAML files. Issue item top-level fields show current
state; chronological `events:` entries define authoritative issue history;
linked `messages:` entries contain Markdown text. Requirement and TODO items
are current-state records with one top-level `body: |-` block and no embedded
`current:`, `events:`, or `messages:` sections. State group names are
developer-centric: `open` means developer work is needed, `blocked` means it
cannot proceed yet, `done` means the developer believes implementation is
complete, and `closed` means final acceptance after review and verification. Do
not add a separate `## Activity` section.

For developer-completed work, prefer structured implementation refs on the
`done` event:

```yaml
implementation_refs:
  - repo: pi-en
    branch: main
    commit: 32225e01ffebef26b1aeca098e7081ff913066cc
```

## Behavior specification references

Issue items may use `related_behaviors` to reference immutable BHV IDs. BHV
bodies, glossaries, adapters, fixtures, and lifecycle remain tracked in the
implementation repository's `pi-en-behaviors/` root, not in coordination.
Never embed a BHV body in an issue or use coordination lifecycle commands to
manage one.

## Testability

Every item should declare `testable: yes` or `testable: no`. If `testable: no`,
include a non-empty `testability_note` explaining why an item-matched test is
not required.

Item-matched tests are executable bash scripts in the owning implementation
repo, not the coordination repo. Match the filename stem to the item ID and
mirror the root item type, not issue status or repo namespace:

```text
tests/items/issues/<item-id>.sh
tests/items/requirements/<item-id>.sh
tests/items/todos/<item-id>.sh
```

Verification messages should record exact commands and results. When available,
run this from the project root to check item metadata and test linkage:

```bash
pi-en-coord-lint --coord-dir "${PI_EN_COORD_DIR:-.pi-en/coordination}" --project-root .
```

Use `--require-done-or-closed` for release gates that require all issue items
to be done or closed.

## Safety rules

- Never force-push.
- Never rewrite coordination history.
- Never renumber IDs.
- Never delete done or closed items.
- Keep Git commit or tag subject lines at or below 72 characters and hard-wrap
  body text at 72 characters where practical.
- Preserve other agents' factual updates during conflict resolution.
- Do not weaken unrelated previously passing tests to make a new done item pass
  verification.
- Ask the user when ownership, stale claims, or conflicts are ambiguous.

This skill complements, but does not replace, `.pi-en/coordination/AGENTS.md`. If
these files differ, the checked-in coordination repository rules win.
