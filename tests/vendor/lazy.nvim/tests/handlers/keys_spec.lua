--- Vendored from lazy.nvim tests/handlers/keys_spec.lua.
--- Source: https://github.com/folke/lazy.nvim/blob/306a05526ada86a7b30af95c5cc81ffba93fef97/tests/handlers/keys_spec.lua
--- Copyright (c) Folke Lemaitre and contributors.
--- Licensed under the Apache License, Version 2.0. See ../../LICENSE.
--- No test logic is modified; only this header was added.
local Keys = require("lazy.core.handler.keys")

describe("keys", function()
  it("parses ids correctly", function()
    local tests = {
      { "<C-/>", "<c-/>", true },
      { "<C-h>", "<c-H>", true },
      { "<C-h>k", "<c-H>K", false },
    }
    for _, test in ipairs(tests) do
      if test[3] then
        assert.same(Keys.parse(test[1]).id, Keys.parse(test[2]).id)
      else
        assert.is_not.same(Keys.parse(test[1]).id, Keys.parse(test[2]).id)
      end
    end
  end)
end)
