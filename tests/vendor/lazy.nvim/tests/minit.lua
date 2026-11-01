#!/usr/bin/env -S nvim -l
--- Vendored from lazy.nvim tests/minit.lua.
--- Source: https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/tests/minit.lua
--- Copyright (c) Folke Lemaitre and contributors.
--- Licensed under the Apache License, Version 2.0. See ../LICENSE.
--- No test logic is modified; only this header was added.

vim.env.LAZY_STDPATH = ".tests"

vim.opt.rtp:prepend(".")

-- Setup lazy.nvim
require("lazy.minit").setup({
  spec = {
    { dir = vim.uv.cwd() },
  },
})
