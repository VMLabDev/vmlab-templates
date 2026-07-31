# CI builds the site only, and never touches templates

The one workflow in this repository renders the site from the committed
generated data and deploys it. It does not refresh registry facts and does not
build any template image. Refreshing facts needs the `vmlab` binary and GHCR
credentials; building needs KVM, and enabling hardware virtualisation on
GitHub-hosted runners is a breach of the Actions terms of service, not merely
slow. Template images are therefore built only on self-hosted machines, and
registry facts are refreshed locally with `just docs-data` and committed.

## Consequences

Nothing in CI observes templates, provisions, or the justfile, so every
consistency property in this repository is currently maintained by hand. A drift
check that needs neither KVM nor registry access can still run in CI, and is the
only kind that can.
