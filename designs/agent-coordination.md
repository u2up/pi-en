# Agent Coordination Repository Design

This document describes an optional `pi-en` layer for creating and maintaining
Git-backed project coordination repositories.

The goal is to make multi-agent coordination for a selected project easy to
establish while keeping synchronization plain, inspectable, and
tool-independent: Git plus YAML item files with Markdown message bodies. This
layer does not change the core Pi-en invariant: one run operates on one
selected project root mounted at `/workspace` inside the sandbox.

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| UC-023 | PIEN-FRQ-20260612-210000-023 |
| CMD-009 | PIEN-FRQ-20260612-210000-040 |
| CMD-010 | PIEN-FRQ-20260612-210000-041 |
| CMD-011 | PIEN-FRQ-20260612-210000-042 |
| CMD-012 | PIEN-FRQ-20260612-210000-043 |
| CMD-013 | PIEN-FRQ-20260612-210000-044 |
| CMD-014 | PIEN-FRQ-20260612-210000-045 |
| PERF-001 | PIEN-QRQ-20260926-164321-001 |
| CMD-015 | PIEN-FRQ-20260612-210000-046 |
| ENV-006 | PIEN-FRQ-20260612-210000-093 |
| FS-010 | PIEN-FRQ-20260612-210000-062 |
| CRQ-001 | PIEN-CRQ-20260612-210000-001 |
| CRQ-002 | PIEN-CRQ-20260612-210000-002 |
| CRQ-003 | PIEN-CRQ-20260612-210000-003 |
| CRQ-004 | PIEN-CRQ-20260612-210000-004 |
| CRQ-005 | PIEN-CRQ-20260612-210000-005 |

## 1. Concept

An agent coordination repository is a dedicated Git repository that stores
shared agent state for a project:

- issues;
- issue items, including `category: task` work items;
- bugs;
- decisions;
- notes;
- chronological agent event histories;
- optional migration records for related projects.

For multi-agent work on the same project, the coordination repository is the
only synchronization mechanism. Agents pull, edit, commit, and push
coordination state just like source code.

For same-machine use, the shared remote can be a local bare Git repository.

## 2. Scope for `pi-en`

`pi-en` should not become a general tracker or database. It can provide
optional infrastructure and conventions:

- helper commands for initializing and cloning coordination repositories;
- scaffolding for a standard directory layout;
- simple issue and TODO templates;
- documented Git synchronization protocol;
- environment variables for selecting a project coordination domain;
- optional instructions that tell agents where the coordination repo is and how to sync it.

The coordination repositories themselves should remain normal Git repositories containing plain text: YAML coordination items, Markdown message bodies, and small metadata files.

## 3. Coordination domains

Use this rule:

```text
one bare coordination repo == one coordination domain
```

A coordination domain may span multiple implementation repositories. Each
Pi-en invocation still selects exactly one implementation project root for
`/workspace`, and each issue belongs to exactly one repo namespace by path. If
projects are unrelated and should not share requirements, decisions, or domain
notes, use separate bare coordination repositories.

Example:

```text
/path/to/project/
  .pi-en/
    coordination/
    agent-remotes/
      project-coordination.git

/path/to/another-project/
  .pi-en/
    coordination/
    agent-remotes/
      another-project-coordination.git
```

## 4. Project-local Pi-en operational root

Fresh pi-en-generated operational artifacts that belong to one selected
project should live under a single project-local `.pi-en/` directory. This
keeps Pi-en state discoverable while avoiding root-level clutter:

```text
.pi-en/
  coordination/          # working coordination clone
  agent-remotes/         # local bare coordination remotes
  logs/                  # optional automation logs
  locks/                 # local process locks
```

The default coordination clone is `.pi-en/coordination`; the default local
bare remote root is `.pi-en/agent-remotes`.

Do not merge project-owned Pi resources into `.pi-en/`. Project-specific
rules, skills, prompts, roles, extensions, and settings stay in `AGENTS.md` and
`.pi/` because those resources may be committed with the project.

Sensitive sandbox Pi state is not part of this default operational root. It
continues to live outside the project by default under the XDG state location,
because it may contain copied auth files, settings, sessions, imported common
agent resources, and caches. Users can explicitly opt into project-local state
with `PI_EN_BWRAP_STATE_DIR=$PWD/.pi-en/state` when they accept the locality and
ignore-policy implications.

## 5. Repository layout

Recommended coordination-domain layout inside `.pi-en/coordination`:

```text
.pi-en/coordination/
  AGENTS.md
  README.md
  PROJECT.md
  docs/
    SYNC_PROTOCOL.md
    ITEM_FORMAT.md
  .pi/
    skills/
      agent-coordination/
        SKILL.md
  repos/
    pi-en/
      REPO.md
      issues/
        open/
        blocked/
        done/
        closed/
  requirements/
  todos/
  decisions/
  notes/
  agents/
    agent-a.md
    agent-b.md
```

`repos/{repo_id}/REPO.md` is the registry manifest for an implementation repo.
It records the canonical repo id, optional aliases/remotes, and whether the repo
is active or retired. Older `repositories.yaml` registry data can be treated as
compatibility input, but manifest records are authoritative. Implementation
repos may commit a root attachment hint so helpers can find the shared domain:

```yaml
version: 1
coordination_domain: my-product
coordination_remote: git@example.com:org/my-product-coordination.git
repo_id: backend-api
```

The manifest may also declare domain-wide generated files that are committed
by that implementation repo. Paths are relative to the implementation repo
root:

```yaml
# repos/backend-api/REPO.md
---
repo_id: backend-api
status: active
domain_generated_files:
  - REQUIREMENTS.md
  - REQUIREMENTS_COVERAGE.md
---
```

Each active repo whose manifest lists a generated path may regenerate and
commit its own copy. Duplicate listings are allowed when a coordination domain
intentionally keeps the same generated view in more than one implementation
repo. Requirement items, decisions, and notes remain the source coordination
state; generated files are secondary views stored in implementation repos for
human review and downstream tooling.

Repo-id lifecycle operations are explicit: add creates the manifest and issue
status directories, rename moves the namespace and records aliases with
warnings, and retire preserves history while blocking new issues by default.


`AGENTS.md` and `.pi/skills/agent-coordination/SKILL.md` are generated from `pi-en` templates by `pi-en-coord-init`. After initialization, the copies in the coordination repository are authoritative for that project coordination domain and can be edited/versioned like any other coordination state.

Use project-local `AGENTS.md`, `.pi/skills`, `.pi/prompts`, and `.pi/extensions`
for codebase-specific Pi behavior. Keep issue, TODO, and cross-agent
synchronization state in the coordination repository. Requirements, decisions,
and notes are common to the domain; issue workflow state is scoped to an
implementation repo under `repos/{repo_id}/issues/{status}/`.

## 6. Item IDs and state

Use stable ID-only filenames. New items use type-coded timestamp IDs to avoid
number allocation races while preserving creation-time information:

```text
<PROJECTKEY>-<TYPECODE>-<YYYYMMDD-HHMMSS>-<NNN>.yaml
```

`PROJECTKEY` should be uppercase alphanumeric text. Built-in type codes are
`ISS` for issue, `FRQ` for functional requirement, `QRQ` for quality
requirement, `CRQ` for constraint requirement, `TODO` for todo, `DEC` for
decision, and `NOTE` for note. Generic `REQ` requirement IDs are legacy-only
unless an explicit supersession or migration decision says otherwise. `NNN` is
a three-digit
collision/order suffix for the exact UTC
timestamp and starts at `001`. Domain item keys are stored in top-level
`PROJECT.md` as `item_key`; repo-scoped issue keys may come from
`repos/{repo_id}/REPO.md`. New Pi-en project coordination creates a repo
namespace for the selected implementation project.

Default key resolution for `pi-en-coord-new` should be:

1. explicit `--project-key`;
2. stored `item_key` in root `PROJECT.md`;
3. `PI_EN_COORD_PROJECT_KEY` when no stored key exists;
4. derive from `--project` / `PI_EN_COORD_PROJECT` for project items;
5. derive from the coordination directory name when no project name is set.

Derived keys are uppercased and all delimiters, whitespace, pipes, slashes,
backslashes, and other non-alphanumeric characters are removed.

Examples:

```text
<PROJECTKEY>-ISS-<YYYYMMDD-HHMMSS>-<NNN>.yaml
<PROJECTKEY>-FRQ-<YYYYMMDD-HHMMSS>-<NNN>.yaml
```

Historical items may keep legacy IDs and slug filenames. Do not rename or
renumber existing items only to satisfy a newer naming convention.

Each item should be a YAML file with top-level current state, chronological
events, and Markdown message bodies linked to those events:

```yaml
schema: coordination-item/v1
id: <PROJECTKEY>-ISS-<YYYYMMDD-HHMMSS>-<NNN>
type: issue
status: open
project: pi-en
title: Document pi config behavior
owner: null
priority: medium
created: 2026-06-05T14:30:22Z
updated: 2026-06-05T14:30:22Z
done: null
closed: null
reviewed: false
verified: false
testable: yes
testability_note: null
related: []
current:
  event: evt-0001
  message: msg-0001
events:
  - id: evt-0001
    type: opened
    at: 2026-06-05T14:30:22Z
    actor:
      id: agent-a
      role: architect
    message: msg-0001
messages:
  - id: msg-0001
    event: evt-0001
    body: |-
      # Document pi config behavior

      ## Context

      ## Acceptance criteria

      - [ ] README explains host `pi config`
      - [ ] README explains sandbox `pi-en-bwrap -- config`
```

Keep issue work in developer-centric state directories under the owning repo
namespace and keep current `status` in the YAML file:

```text
repos/{repo_id}/issues/open/
repos/{repo_id}/issues/blocked/
repos/{repo_id}/issues/done/
repos/{repo_id}/issues/closed/
```

Other item types live under domain-shared semantic type directories such as
`requirements/`, `todos/`, `decisions/`, and `notes/`. Functional, quality,
constraint requirement items share root-level `requirements/` while preserving
their item ID type codes. TODO items use `todos/`, the `TODO` ID type code,
and single-body YAML records. Preserve historical IDs and filenames; do not
silently renumber, rewrite, or move old items just to satisfy a newer taxonomy.

The state names are developer-centric: `open` means developer work is needed,
`blocked` means developer work cannot proceed, `done` means the developer
believes implementation is complete, and `closed` means final acceptance after
review and verification. New items start with `reviewed: false` and
`verified: false`, and declare `testable: yes` or `testable: no` with a
`testability_note` when direct item-matched testing is not required.
Item-matched tests live in the owning implementation repository under
`tests/items/` and match the item ID by filename stem. Issue tests live under
`tests/items/issues/`; requirement tests live under `tests/items/requirements/`.
Tests intentionally do not mirror issue status directories or repo namespaces.

When marking an issue done, move it with `git mv`, set `status: done`, set
`done:`, reset `reviewed: false` and `verified: false`, update `current:`,
and append a `done` event/message. Done or link events should include
structured implementation refs when possible: `repo: pi-en`, `branch: main`,
and the full `commit` hash. When final-closing an issue after review and
verification, move it to `closed/` in the same repo namespace, set
`status: closed`, set `closed:`, and append a final `closed` event/message.
Cross-repo implementation work should be represented by one issue per affected
repo and linked with stable item IDs in `related:` or messages rather than
path-only links, so repo-id renames do not require reference rewrites.

## 7. Git synchronization protocol

Agents should use a simple protocol:

```text
1. pull/rebase before reading or selecting work;
2. claim one item by editing current YAML fields;
3. append a claimed event and linked Markdown message;
4. commit and push the claim immediately;
5. do project work in the relevant project clone;
6. pull/rebase the coordination repo again;
7. append progress, link, result, or status events/messages;
8. commit and push immediately.
```

Example claim flow:

```bash
cd "${PI_EN_COORD_DIR:-.pi-en/coordination}"
git pull --rebase
# edit item: status: claimed, owner: agent-a, current: evt-0002/msg-0002
# append a claimed event and message
path=repos/<repo_id>/issues/open/<PROJECTKEY>-ISS-<YYYYMMDD-HHMMSS>-<NNN>.yaml
git add "$path"
git commit -m "Claim <PROJECTKEY>-ISS-<YYYYMMDD-HHMMSS>-<NNN>"
git push
```

If two agents claim the same file, Git push/rebase conflicts become the locking mechanism.

Recommended per-clone Git settings:

```bash
git config pull.rebase true
git config rebase.autoStash true
```

## 8. Proposed `pi-en` helper commands

`pi-en` could expose a small helper CLI or a set of shell commands:

```text
pi-en-bootstrap-coordination
                      infer defaults and initialize via pi-en-coord-init
pi-en-coord-init      create a local bare coordination remote
pi-en-coord-clone     clone a coordination remote for the current project
pi-en-coord-status    show sync status and current open/claimed items
pi-en-coord-list      list issues, todos, notes, decisions, or requirement
                      classes by status
pi-en-coord-pull      run git pull --rebase in the coordination clone
pi-en-coord-push      commit/push coordination changes
pi-en-coord-new       create a new templated item
pi-en-coord-lint      lint item IDs, status, and item-matched tests
pi-en-coord-claim     claim an item
pi-en-coord-done      mark developer work done and move it to done/
pi-en-coord-review    mark review pass/fail and reopen on failure
pi-en-coord-verify    mark verification pass/fail and reopen on failure
pi-en-coord-close     final-close a reviewed and verified done item
pi-en-coord-upgrade-rules
                      preview/apply rule template updates
```

A minimal first implementation could include only:

```text
pi-en-coord-init
pi-en-coord-clone
pi-en-coord-new
```

Everything else can remain normal Git commands until real usage proves that more automation is needed.

## 9. Proposed environment variables

```bash
PI_EN_COORD_REMOTE=/workspace/.pi-en/agent-remotes/pi-en-coordination.git # exact Git remote URL/path
PI_EN_COORD_PROJECT=pi-en                        # coordination project/domain name
PI_EN_COORD_DIR=/workspace/.pi-en/coordination   # clone directory for this project
PI_EN_COORD_AGENT_ID=agent-a              # agent identity for item ownership/events
PI_EN_COORD_ROLE=architect                # optional active role for role-aware commits
PI_EN_COORD_PROJECT_KEY=PIEN             # optional generated item ID prefix
```

`pi-en-bootstrap-coordination` can print and apply inferred values for these
variables when they are not already set, including when pointed at another
project root with `--project-root`, and record the selected remote as
`.pi-en-coordination.yaml` `coordination_remote`. If the coordination clone
already exists but the planned local bare remote is missing or empty, it can
restore that remote from committed clone history without changing item state.
With `PI_EN_COORD_REMOTE` set, `pi-en-coord-clone` can infer:

```text
$PI_EN_COORD_REMOTE -> $PI_EN_COORD_DIR
```

When no exact remote is configured and `--root` is omitted, helpers should
prefer the project-visible `.pi-en/agent-remotes` directory. Inside the Pi-en
sandbox, or when `/workspace` resolves to the current project root, that default
should be `/workspace/.pi-en/agent-remotes` so the same bare remote is usable
from inside and outside Bubblewrap for this project.

### 9.1 Optional role-aware identity

If a role-template extension is active, coordination helpers may use
`PI_EN_COORD_ROLE` or an explicit `--role ROLE` option to make coordination
actions attributable to the role that performed them. Item events store the
agent ID and role explicitly; helper Git commits can still use an effective
actor such as `pi/architect` through per-command identity overrides such
as:

```bash
git -c user.name=pi/architect \
    -c user.email=pi+architect@coordination.local \
    commit -m "Claim <PROJECTKEY>-ISS-<YYYYMMDD-HHMMSS>-<NNN>"
```

Role-aware identity should apply to the coordination repository only. It should
not change project repository Git identity unless the user explicitly opts in.
Default `pi-en` startup must still avoid automatic claims, closes, commits, or pushes.

## 10. Coordination rules installed by `pi-en-coord-init`

Because `pi-en` is a Pi-related project, the default agent rules should be provided as Pi skill templates and scaffolded instructions. The `pi-en` source tree should keep these defaults under a clear template directory such as:

```text
pi-skill-templates/
  agent-coordination/
    SKILL.md
    AGENTS.md
    SYNC_PROTOCOL.md
    ITEM_FORMAT.md
```

`pi-en-coord-init` should install those templates into a newly initialized coordination repository as at least:

```text
.pi-en/coordination/AGENTS.md
.pi-en/coordination/docs/SYNC_PROTOCOL.md
.pi-en/coordination/docs/ITEM_FORMAT.md
.pi-en/coordination/.pi/skills/agent-coordination/SKILL.md
```

The installed files are the project coordination domain's authoritative rules. `pi-en` templates are only defaults; after initialization, updates to rules should be committed to the coordination repository so all agents receive them via Git.

### 10.1 Required `AGENTS.md` rules

The generated `.pi-en/coordination/AGENTS.md` should instruct agents:

1. Treat the coordination repository as the only shared synchronization source for agent work state.
2. Pull/rebase before inspecting, selecting, creating, claiming, blocking, marking done, reviewing, verifying, closing, or otherwise modifying items.
3. Commit and push coordination changes immediately after changing shared state.
4. Never force-push, rewrite public history, delete done or closed items, or renumber item IDs.
5. Prefer one claimed item per agent unless explicitly instructed otherwise.
6. Do not edit another agent's claimed item except to resolve a Git conflict, add clearly relevant factual information, or when the coordination domain rules define it as stale/abandoned.
7. Record all meaningful state transitions as chronological item events with linked Markdown messages.
8. Link developer-completed work to concrete structured implementation refs with `repo`, `branch`, and full `commit` fields.
9. Keep coordination changes small and reviewable.
10. Keep all Git commit, tag, and other Git message text readable in standard terminals: subject/summary lines should be at most 72 characters, and body paragraphs should be hard-wrapped at 72 characters where practical.
11. If a push/rebase conflict occurs, resolve it conservatively and preserve both agents' factual updates when possible.

### 10.2 Item manipulation rules

Agents should use these state transitions:

- create: add a new issue YAML item under
  `repos/{repo_id}/issues/open/` or add a non-issue item under the
  appropriate domain-shared typed directory, with `reviewed: false`,
  `verified: false`, and an `opened` event/message;
- claim: set `status: claimed`, set `owner: <agent-id>`, update `current:`, append a `claimed` event/message, commit, push;
- block: move to `blocked/` when needed, set `status: blocked`, document blocker and owner expectations in a `blocked` event/message;
- resume/unblock: move back to `open/` or keep claimed if the same agent continues, and append `reopened` or `updated` history;
- done: use `git mv` into `done/`, set `status: done`, set `done: <timestamp>`, reset `reviewed: false` and `verified: false`, append a `done` event/message with structured implementation refs;
- review pass/fail: set `reviewed: true` on pass, or move back to `open/` and append a `review_failed` event on failure;
- verify pass/fail: set `verified: true` on pass, or move back to `open/` and append a `verification_failed` event on failure;
- close: after `status: done`, `reviewed: true`, and `verified: true`, use `git mv` into `closed/`, set `status: closed`, set `closed: <timestamp>`, and append a final `closed` event/message;
- split: create new linked items and mark the relationship in `related:` / `split_from:` fields and an `updated` event;
- supersede: leave the old item in place, mark `status: closed` or `superseded`, and link to the replacement.

Do not encode important state only in a commit message. The file content must remain understandable from a checkout.

### 10.3 Required Pi skill template

`pi-en` should ship the canonical skill source as `pi-skill-templates/agent-coordination/SKILL.md`. `pi-en-coord-init` should copy it to `.pi-en/coordination/.pi/skills/agent-coordination/SKILL.md`. A generated skill should look like this in spirit:

```markdown
# Agent Coordination

Use this skill when working in a project that contains a Git-backed agent coordination repository, when asked to find/claim/update work, or before making changes that affect shared agent state.

## Coordination repository

The coordination repository is the only synchronization source for agent issue,
TODO, and coordination state. For fresh Pi-en projects and automatic workflows,
find the clone at `<project>/.pi-en/coordination`; `PI_EN_COORD_DIR` should
resolve to that project-local checkout. External coordination working clones are
not part of the automatic Pi-en workflow. The configured `coordination_remote`
in `.pi-en-coordination.yaml` is the source of truth for the Git remote,
including external local bare remotes, and any `.pi-en/agent-remotes/` entries
for those remotes are derived operational aliases.

## Required protocol

1. `cd "${PI_EN_COORD_DIR:-.pi-en/coordination}" && git pull --rebase` before
   reading or modifying coordination state, or use the `pi-en-coord-*` helpers
   with their default coordination directory resolution.
2. Inspect open/claimed/blocked/done YAML items relevant to the current project.
3. Claim at most one item unless instructed otherwise.
4. Commit and push immediately after claiming or changing status.
5. Do project work in the project repository.
6. Return to the coordination repo, pull/rebase, mark developer-completed work as done with results and implementation refs, then commit and push.
7. Reviewers and testers update `reviewed` and `verified` flags on done items; failures reopen developer work.
8. Move items to closed only after they are done, reviewed, and verified.

## Safety rules

- Never force-push.
- Never rewrite coordination history.
- Never renumber IDs.
- Never delete done or closed items.
- Keep Git commit/tag message subject lines at or below 72 characters and hard-wrap body text at 72 characters where practical.
- Preserve other agents' factual updates during conflict resolution.
- Do not weaken unrelated previously passing tests to make a new done item pass verification.
- Ask the user when ownership, stale claims, or conflicts are ambiguous.
```

The skill should complement, not replace, `.pi-en/coordination/AGENTS.md`. If they differ, the checked-in coordination repository rules win.

### 10.4 Template ownership and updates

`pi-en` may update its built-in templates over time. Existing coordination repositories should not be silently overwritten. If template upgrade support is added, it should be explicit, diffable, and commit-based, for example:

```bash
pi-en-coord-upgrade-rules --preview
pi-en-coord-upgrade-rules
```

## 11. Optional Pi integration

Default `pi-en` startup should not mutate coordination state automatically.

Possible safe integrations:

- print a reminder when `.pi-en/coordination` exists;
- provide generated/scaffolded coordination `AGENTS.md`, docs, and Pi skill templates through `pi-en-coord-init`;
- provide an optional prompt/context snippet explaining the Git sync protocol;
- allow users to mount/select the coordination repository explicitly when it is outside the project root.

Any automatic claim, mark-done, review, verify, close, commit, or push behavior should be opt-in and implemented outside the default `pi-en` startup path.

## 12. Non-goals

Initial infrastructure should avoid:

- daemons;
- databases;
- non-Git locking services;
- complex dependency solvers;
- automatic background pushes;
- hidden state outside the coordination repository, except local Git clone metadata;
- making `pi-en` itself responsible for deciding what agents should work on.

The value of the design is that humans and agents can inspect, edit, and recover everything with standard Git and text tools.
