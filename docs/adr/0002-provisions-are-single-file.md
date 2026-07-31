# Build and first-boot provisions are single-file

Provision scripts cannot import each other. The wscript language has a module
system (`use "./helpers.ws" as h`), but vmlab compiles provisions through
`wscript::compile()`, which is hard-wired to the `NoImports` resolver
(`vmlab/src/scripting/runner.rs:106,145` and `mod.rs:1152`). A path-form `use`
in a provision fails to compile with E0200. Only host modules resolve, which is
why every provision in this repository is exactly `use vmlab`.

This is why shared provision logic is copy-pasted across templates rather than
factored out, and why a single logical fix to the Windows build provision lands
as five identical edits.

## Consequences

Sharing provision logic requires one of: patching vmlab to compile via
`Context::compile_entry` with an `FsResolver` (upstream already exports both),
or generating the scripts on the host before a build. Note that if imports are
enabled, bare-name `use` resolves against `.wscript`, not `.ws` — only the path
form would work with this repository's file extension.

Template definitions have no such limitation: WCL local imports resolve today
(`docs/main.wcl` already composes six files), though vmlab requires the literal
line `import <vmlab.wcl>` in each entry file, and whole `template` blocks cannot
be macro-generated — only the values inside them can be shared.
