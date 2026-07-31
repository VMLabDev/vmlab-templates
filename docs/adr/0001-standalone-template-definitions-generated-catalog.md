# Template definitions are standalone; the catalog is generated

Each template is a self-contained directory that can be built by `cd`-ing into
it and running `vmlab template build`, with no dependency on the repository
root. The catalog at the root exists because the Web UI needs a single document
listing every template, and it is generated from the standalone definitions by
`scripts/generate-unified-wcl.sh` rather than authored.

## Consequences

The catalog is a build artefact that is nevertheless committed, so it can go
stale against the definitions it was generated from. Editing it directly is
always wrong — edit the per-template definition and regenerate.
