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
metadata. `index` produces the derived catalog; do not edit a catalog as a
source artifact.

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
