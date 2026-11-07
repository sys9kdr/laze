# Custom commands

The core ships no commands; [`laze.extra`](extras.md) registers four maintenance commands but only on explicit `setup()`. For anything else, add your own against the compiled table returned by `setup`: 

## Sync (update all)

```lua
vim.api.nvim_create_user_command("Sync", function()
  vim.pack.update()
  vim.notify("laze: synced", vim.log.levels.INFO)
end, { desc = "Sync all plugins" })
```

## Dev mode switch (point to local clone)

```lua
local compiled = laze.setup(specs)   -- keep the compiled table around

vim.api.nvim_create_user_command("LazeDev", function(args)
  local name = args.fargs[1]
  if not name then
    vim.notify("usage: LazeDev <plugin-name>", vim.log.levels.WARN)
    return
  end
  local entry = compiled.registry[name]
  if not entry then
    vim.notify("laze: plugin '" .. name .. "' not found", vim.log.levels.WARN)
    return
  end
  local dev_path = entry.dev_path or (vim.fn.expand("~/projects/") .. name)
  if vim.fn.isdirectory(dev_path) == 0 then
    vim.notify("laze: dev path not found: " .. dev_path, vim.log.levels.WARN)
    return
  end
  vim.pack.add({ { src = dev_path, name = name } })
  vim.notify("laze: dev mode -> " .. dev_path, vim.log.levels.INFO)
end, {
  nargs = 1,
  complete = function() return vim.tbl_keys(compiled.registry) end,
  desc = "Switch plugin to local dev version",
})
```

Note: this is session-scoped. The next startup re-registers the original
`src` from the specs, so the switch does not persist — combine with
`reload_all()` or dev specs (`dev = true` / `dev = "path"`) for persistent
dev mode.

## Hot reload dev plugin

```lua
vim.api.nvim_create_user_command("LazeReload", function(args)
  local name = args.fargs[1]
  if not name then
    vim.notify("usage: LazeReload <plugin-name>", vim.log.levels.WARN)
    return
  end
  package.loaded[name] = nil
  local entry = compiled.registry[name]
  if entry and entry.dev_path then
    vim.pack.add({ { src = entry.dev_path, name = name } })
  end
  local ok, err = pcall(require, name)
  if not ok then
    vim.notify("laze: reload failed: " .. tostring(err), vim.log.levels.ERROR)
  else
    vim.notify("laze: reloaded " .. name, vim.log.levels.INFO)
  end
end, {
  nargs = 1,
  complete = function() return vim.tbl_keys(compiled.registry) end,
  desc = "Hot-reload a dev plugin",
})
```

```lua
vim.api.nvim_create_user_command("LazeReloadAll", function()
  laze.reload_all()   -- rebuild the plan; re-load eager plugins (dev loop)
end, { desc = "Reload all plugins (fresh plan)" })
```

## Pinning versions

No recipe needed: `vim.pack` keeps its own lockfile
(`$XDG_CONFIG_HOME/nvim/nvim-pack-lock.json`) and installs at the locked
revision on a fresh machine. Commit it to version control — that is the
entire workflow. (There is no laze lock module: the native lockfile covers
pinning, verified end-to-end.)

## Store compiled IR for commands

```lua
local compiled = laze.setup(specs)  -- setup returns the compiled table
```

Note: never feed `compiled.pack` to a raw `vim.pack.add()` at startup —
it `:packadd`s everything and bypasses lazy triggers. Startup must go
through `laze.setup()`, which splits eager (`load = false`) from lazy
(no-op `load`). A raw add is only safe in manually-run maintenance
commands, where sourcing everything immediately is the point.

## Sandbox testing

A ready-to-use test profile is at `tests/profile/`:

```sh
# 1. Clone real plugins to /tmp/laze-plugins (one-time)
./tests/profile/setup.sh

# 2. Launch neovim with laze + plugins
./tests/profile/run.sh
```

The profile exercises all lazy-loading triggers (event, ft, cmd, keys) with real plugins via `dir` paths. Edit `tests/profile/init.lua` to experiment.