# tests

* Depends on neovim, headless or clean neovim as runtime engine.

## README e2e (manual, network only)

`tests/e2e/` fetches a fixed set of real plugin READMEs at pinned commits, takes each lazy.nvim snippet verbatim, installs it in an isolated headless Neovim, fires one trigger, and runs one smoke assertion.
It needs network and is not part of CI:

```sh
make e2e                   # all plugins
make e2e ARGS="oil flash"  # by name
make e2e ARGS=--failed     # last report's failures
make e2e ARGS=--clean      # drop cached installs
```

Each row reports `ok` / `warned` (unsupported field) / `failed` with a reason category (`unsupported_field`, `validation_error`, `install_error`, `runtime_error`, `environment`, `extraction_error`).
This is a diagnosis, not a pass rate.
Reports land in `tests/e2e/report/` (gitignored).

