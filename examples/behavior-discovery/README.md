# External-project behavior discovery example

This is a complete behavior root that an external project can copy into its own
repository. It has no `.pi-en/` directory, coordination checkout, or
coordination references. The project owns its glossary, executable adapter, and
acceptance examples.

```bash
cd /path/to/external-project
pien behavior --project-root . lint
pien behavior --project-root . test
pien behavior --project-root . document \
  > pi-en-behaviors/BEHAVIOR_DOCUMENTATION.md
```

Use the generated document in a discovery/review session: domain participants
propose outcome-focused examples and glossary vocabulary; implementation
participants confirm that the adapter can observe them. Review and commit the
resulting glossary, BHV, and document changes together.

The `known-current-result` scenario is a characterization input. It must not be
promoted as intended acceptance behavior merely because it passes. A domain
reviewer must confirm its terms, public outcome, and expected result before
removing its `characterization` tag or relying on it as an acceptance contract.

The adapter is intentionally tiny and only demonstrates the runner protocol.
A real project adapter invokes its public interface, not internal modules.
