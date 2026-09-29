# Contributing

harn's core is small on purpose: resolve a source, build an environment and an argv, exec. A new
harness or provider is a config entry, not a code change. Changes that grow the core need an
issue first.

Before a pull request: `/bin/bash tests/run.sh` passes, `shellcheck --shell=bash bin/harn
tests/*.sh` is clean, and the title is a Conventional Commit. Do not edit CHANGELOG.md;
release-please writes it. You must understand every line you submit, including any an agent
wrote.
