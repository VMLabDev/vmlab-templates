---
status: accepted, not yet implemented
---

# Windows provisions and unattend files will be generated

The modern Windows templates share 25 near-identical script and answer files,
and every bug fix has to be applied five times — a rollout that stopped after
one copy is what caused the sysprep defect recorded in ADR-0006. Provisions
cannot import each other (ADR-0002), so the files will be generated from bases
in `common/windows/` by `scripts/generate-windows-provisions.sh` and committed.

Substitution is `sed` over placeholders, with a second base only where the
difference is structural: `sysprep-unattend.xml` gets a client and a server
base, because the client SKUs pre-create a local account and the servers do not.
No base contains conditionals, so each one stays a valid, lintable file of the
kind it produces.

Only two values per template are supplied by hand — the `ComputerName` and the
product description — and they live in one table at the top of the generator so
the five templates can be read side by side. Everything else derives: the
client/server family and the install image index from `profile`, and the
template name from the definition's own label.

## Consequences

Generated files are committed, so a template directory still builds standalone
per ADR-0001. `just gen-windows` regenerates; `just check` regenerates into a
temporary directory and diffs, so drift fails rather than accumulating, and the
check never mutates the working tree.

`windows-11-arm64` takes only the two files it genuinely shares — its first-boot
provision and the XAML registration payload. Its build provision and answer
files are a different design and stay hand-maintained.
