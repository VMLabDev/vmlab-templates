# The publication gate is hand-authored, not derived

A template appears on the template-library site only if someone has written
presentation copy for it in `docs/data/meta.wcl`. Existence of a template
directory, and even a successful publish to the registry, is deliberately not
enough. Publishing to the site is an editorial act: the description, category,
and feature list are prose that has to be written by a person.

## Consequences

Templates accumulate in the repository without appearing on the site, and that
is expected rather than a bug. Any drift check should report ungated templates
as information, not as a failure.
