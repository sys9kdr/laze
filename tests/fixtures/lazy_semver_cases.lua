--- Test vectors adapted from lazy.nvim's tests/manage/semver_spec.lua.
--- lazy.nvim is Copyright (c) Folke Lemaitre and contributors.
--- Licensed under the Apache License, Version 2.0.
--- Source: https://github.com/folke/lazy.nvim/blob/main/tests/manage/semver_spec.lua
--- License: https://github.com/folke/lazy.nvim/blob/main/LICENSE
---
--- Only input/expected membership data is adapted; no implementation code is
--- copied. `inside`/`outside` describe lazy.nvim's documented range semantics
--- as pinned by its own tests. laze lowers these inputs with
--- vim.version.range(), so tests/run.lua checks the resulting VersionRange.
return {
	{ input = "1.2.3", inside = { "1.2.3" }, outside = { "1.2.2", "1.2.4", "1.2.3-alpha" } },
	{ input = "1.2", inside = { "1.2.0", "1.2.9" }, outside = { "1.1.9", "1.3.0" } },
	{ input = "=1.2.3", inside = { "1.2.3" }, outside = { "1.2.2", "1.2.4" } },
	{ input = ">1.2.3", inside = { "1.2.4", "2.0.0" }, outside = { "1.2.3" } },
	{ input = ">=1.2.3", inside = { "1.2.3", "2.0.0" }, outside = { "1.2.2" } },
	{ input = "~1.2.3", inside = { "1.2.3", "1.2.9" }, outside = { "1.3.0" } },
	{ input = "^1.2.3", inside = { "1.2.3", "1.9.9" }, outside = { "2.0.0" } },
	{ input = "^0.2.3", inside = { "0.2.3", "0.2.9" }, outside = { "0.3.0" } },
	{ input = "^0.0.1", inside = { "0.0.1" }, outside = { "0.0.2" } },
	{ input = "^1.2", inside = { "1.2.0", "1.9.9" }, outside = { "2.0.0" } },
	{ input = "~1.2", inside = { "1.2.0", "1.2.9" }, outside = { "1.3.0" } },
	{ input = "~1", inside = { "1.0.0", "1.9.9" }, outside = { "2.0.0" } },
	{ input = "^1", inside = { "1.0.0", "1.9.9" }, outside = { "2.0.0" } },
	{ input = "1.*", inside = { "1.0.0", "1.9.9" }, outside = { "2.0.0" } },
	{ input = "1", inside = { "1.0.0", "1.9.9" }, outside = { "2.0.0" } },
	{ input = "1.x", inside = { "1.0.0", "1.9.9" }, outside = { "2.0.0" } },
	{ input = "1.2.x", inside = { "1.2.0", "1.2.9" }, outside = { "1.3.0" } },
	{ input = "1.2.*", inside = { "1.2.0", "1.2.9" }, outside = { "1.3.0" } },
	{ input = "*", inside = { "0.0.0", "99.0.0" }, outside = {} },
	{ input = "1.2 - 2.3.0", inside = { "1.2.0", "2.2.9" }, outside = { "1.1.9", "2.3.0" } },
	{ input = "1.2.3 - 2.3.4", inside = { "1.2.3", "2.3.3" }, outside = { "1.2.2", "2.3.4" } },
	{ input = "1.2.3 - 2", inside = { "1.2.3", "2.9.9" }, outside = { "1.2.2", "3.0.0" } },
	{ input = "1.2.3-alpha", inside = { "1.2.3-alpha" }, outside = { "1.2.3-beta", "1.2.3" } },
}
