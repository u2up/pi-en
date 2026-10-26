# Behavior Specifications

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| BHV-001 | PIEN-FRQ-20261024-215014-001 |
| BHV-002 | PIEN-FRQ-20261024-215016-001 |
| BHV-004 | PIEN-QRQ-20261024-215021-001 |
| BHV-005 | PIEN-FRQ-20261025-054332-001 |
| BHV-006 | PIEN-FRQ-20261025-072024-001 |

Behavior Specifications (BHVs) are project-owned, versioned, executable BDD
examples for public behavior. They complement tests; they are not a replacement
for unit, integration, security, property, or performance testing.

## Ownership and boundaries

A project commits its complete behavior root:

```text
pi-en-behaviors/
  MANIFEST.yaml
  GLOSSARY.yaml
  adapter
  specifications/
```

This is tracked source in the implementation repository. It is deliberately
separate from `.pi-en/`, which is ignored mutable operational state for
sandboxes and coordination working clones. Coordination items may reference a
BHV ID through `related_behaviors`, but must not contain BHV bodies or manage
BHV lifecycle.

Each component repository owns its own BHVs, glossary, adapter, fixtures, and
CI configuration. An umbrella integration repository owns system-level BHVs;
it consumes pinned component artifacts or results and asserts system outcomes,
not component implementation details.

## Model and authoring

`MANIFEST.yaml`, `GLOSSARY.yaml`, and every BHV are versioned YAML documents.
The manifest identifies the repository, local item key, glossary, executable
adapter, and advisory or enforced compliance mode. A runner must reject an
unsupported schema or glossary language version with a local migration/upgrade
message; it must never silently reinterpret a specification.

The glossary declares domain nouns, value types, executable `given`, `when`,
and `then` terms, argument shapes, and logical groups. The adapter's `describe`
output must match those terms. The runner invokes adapter phases with a term, a
JSON input file, and a state directory, so DSL values are data rather than shell
syntax.

Write BHVs in domain language around public outcomes. A feature, rule, and
contrasting scenarios state only the observables they cover; they do not prove
complete implementation equivalence. Characterization or generated scenarios
are useful review inputs, but become acceptance behavior only after a human
reviews their domain meaning and expected outcome.

## Collection, identity, and groups

Reserved control files stay at the root. All BHVs are regular ID-named YAML
files directly in the flat `specifications/` collection. IDs use
`<ITEMKEY>-BHV-<YYYYMMDD-HHMMSS>-<NNN>` and are immutable cross-repository
references; changing a group never changes an ID.

A BHV has one normalized slash-separated logical `group`, such as
`features/checkout/refunds`. Groups are declared by the glossary and describe
capabilities, not directory paths or implementation modules. `list --group`
and `test --group` select a group and its descendants. `regroup` changes only
metadata. `index` produces the derived JSON catalog; do not edit a catalog as a
source artifact. `document` renders a readable Markdown catalog from the same
metadata, grouping features and rules by logical group without exposing adapter
internals.

## Discovery and review workflow

Keep discovery local to the implementation repository. Product or domain
participants propose a public outcome, shared terms, and contrasting examples;
implementation participants confirm that the terms are executable and the
adapter can observe the stated result. Review the generated
`pien behavior document` output with the BHV change: it provides navigable
logical groups, feature/rule intent, acceptance references, and scenario names
without requiring coordination state. Commit the approved glossary and BHV
changes together, then run `lint` and `test` in ordinary CI.

Characterization examples record known observable behavior and are valuable
review inputs, but are not intended acceptance behavior merely because they
pass. Promote one only after a domain reviewer confirms its terminology,
public outcome, and expected result; give it a stable scenario title and commit
that review as an explicit BHV/glossary change. Keep uncertain examples clearly
identified as characterization work or out of the active acceptance suite.

## Adoption and CI

Initialization is additive: it never overwrites an existing manifest, glossary,
or BHV. A project may pin its Pi-en runner version for reproducible CI. Start
with a small reviewed slice, then run ordinary CI:

```bash
pien behavior init
# set repository_id/item_key, vocabulary, groups, and adapter in pi-en-behaviors/
pien behavior new --id SHOP-BHV-20261026-120000-001 \
  --group features/checkout --title 'Customer completes checkout'
pien behavior lint
pien behavior test
pien behavior index > pi-en-behaviors/catalog.json
pien behavior document > pi-en-behaviors/BEHAVIOR_DOCUMENTATION.md
```

Snapshots and requirement coverage are optional. To opt into traceability,
explicitly supply a clean coordination checkout and repository ID; this writes
only the local tracked snapshot:

```bash
pien behavior requirements snapshot --coord-dir ../coordination --repo-id shop
pien behavior coverage
```

Coverage is advisory unless the manifest selects enforced compliance. On runner
upgrade, pin the previous runner or explicitly migrate and review the versioned
artifacts before changing CI. No coordination checkout is required for init,
new, lint, test, grouping, or catalog generation.

## Deferred advanced tooling proposals

Do not implement the following proposals until v1 has been used and reviewed
in external projects. Record demand as concrete authoring or assurance problems
from those projects, including the affected public outcome, the current manual
workaround, and why the existing YAML BHV model is insufficient. A proposal
must preserve project-local ownership and ordinary CI execution; it must not
make a coordination checkout, Gherkin parser, or inference service a v1
requirement.

### Adapter conformance fixtures

**Problem to validate:** adapter authors can accidentally implement a glossary
term with the wrong phase, argument shape, state handling, or observable result
while still passing their own BHVs.

**Candidate scope:** publish versioned, runner-owned fixture suites that invoke
an adapter through the documented `describe`, `given`, `when`, and `then`
protocol. Fixtures would assert protocol conformance only, with a small set of
portable success/failure adapters and no project domain vocabulary. Projects
would opt in with a separate command or CI target.

**Costs and safeguards:** fixtures must version with the runner protocol and
must distinguish a runner-protocol failure from a project behavior failure.
They must not require network access, execute untrusted fixture inputs outside
the existing sandbox model, or expose adapter internals in living
documentation. Compatibility requires an explicit fixture/protocol version
matrix and a retained runner pin or reviewed migration path.

### Reviewed recording and characterization helpers

**Problem to validate:** teams need a low-friction way to turn observed public
interactions into reviewable candidate examples without treating recordings as
requirements.

**Candidate scope:** add an explicitly experimental helper that captures only
user-approved, redacted public inputs and outputs, then emits a draft BHV with
the `characterization` tag and conspicuous review metadata. It may never add a
draft directly to the active acceptance suite or remove that tag; promotion
remains a reviewed glossary/BHV commit.

**Costs and safeguards:** require an opt-in output directory, stable and
inspectable serialization, redaction hooks, and no default capture of secrets,
tokens, personal data, or ambient environment. Define retention and access
rules per adopting project. The helper needs compatibility tests against each
supported schema version and clear failure behavior when it cannot safely
redact or represent a value.

### Rich scenario syntax and Gherkin interchange

**Problem to validate:** repeated external-project demand demonstrates that
scenario outlines, example tables, tags, backgrounds, or Gherkin
import/export convey public behavior more clearly than current explicit YAML
scenarios.

**Candidate scope:** evaluate each construct independently, starting with a
lossless import/export prototype and fixtures showing its mapping to the
current glossary and logical groups. Do not adopt a whole Gherkin grammar by
default. Tags must not replace the single logical group taxonomy, and any
outline/table expansion must retain stable scenario identity and readable
review diffs.

**Costs and safeguards:** specify escaping, type conversion, duplicate names,
background state isolation, unsupported constructs, and round-trip loss policy
before enabling interchange. New syntax must have a declared language version,
an explicit migration command, and an old-runner pin path; importing external
text must be parsed as data, never evaluated as shell. Adoption requires
maintainer evidence that the added grammar and parser maintenance cost is
justified.

### Complementary assurance integrations

**Problem to validate:** users need guidance or narrow integrations for
assurance gaps that BHVs intentionally do not cover.

**Candidate scope:** document and prototype optional links from a BHV's public
outcome to property/model-based, contract, security, performance/load, and
mutation test evidence. These tests remain independent suites: properties
explore input spaces, models compare defined state behavior, contracts check
service boundaries, security and load testing assess adversarial and capacity
risks, and mutation testing assesses test sensitivity. None may be reported as
BHV conformance or replace scenario review.

**Costs and safeguards:** integrations must avoid importing test-framework
lock-in into the generic runner and must not publish sensitive security or load
artifacts by default. Each integration needs a reproducible tool/version pin,
separate failure reporting, bounded resource settings, and an explicit policy
for CI secrets and test environments.

### Umbrella system-level BHVs

**Problem to validate:** a system spanning independently released components
needs outcome-focused acceptance evidence that component-local BHVs cannot
provide.

**Candidate scope:** define an umbrella repository that owns its own glossary,
adapter, and system-level BHVs. It consumes immutable, pinned component
artifacts, attestations, or result contracts and asserts only cross-component
public outcomes. Component repositories retain their component BHVs and are
not required to expose implementation details.

**Costs and safeguards:** the proposal must define artifact provenance,
digest/lock-file pinning, compatibility matrices, test-data isolation, secret
boundaries, rollback, and how stale component results are identified. It must
also establish maintenance ownership and release cadence so umbrella failures
can be assigned without making every component change block unrelated systems.

For any proposal, submit a separately scoped implementation issue only after
recording external evidence, compatibility and migration behavior, security
review, expected maintenance owner, and executable acceptance tests. Keep the
proposal optional and additive unless a later decision explicitly changes the
BHV compatibility contract.
