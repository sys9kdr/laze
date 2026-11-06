-- Luacheck configuration (pinned: 1.2.0).
--
-- Luacheck was chosen over Selene: Selene's prebuilt 0.32.0 binary cannot
-- parse LuaJIT `goto`/labels used by the test loop, and a custom Rust build
-- would be required. Luacheck supports LuaJIT 2.x directly.
std = "luajit"

-- Neovim's global. Production code only reads it; tests that install a stub
-- opt in to writing it with a file-level `-- luacheck: globals vim`.
read_globals = { "vim" }

-- Test descriptions are single long string literals by design (the subset
-- notes are intentionally one line each), so line length is not linted.
max_line_length = false

-- Third-party oracle; it has its own upstream style and globals.
exclude_files = { "tests/vendor/**" }
