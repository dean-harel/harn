# Contributing

harn's core is small on purpose: resolve a source, build an environment and an argv, exec. A new
harness or provider is a config entry, not a code change. Changes that grow the core need an
issue first.

Before a pull request: `/bin/bash tests/run.sh` and `go test ./...` pass, `go vet ./...` and
`shellcheck --shell=bash tests/*.sh` are clean, `gofmt -l .` prints nothing, and the title is a
Conventional Commit. You must understand every line you submit, including any an agent wrote.
