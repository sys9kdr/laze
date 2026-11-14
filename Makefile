# laze.nvim dev workflow. Run `make [target]` from the repo root; `make` alone
# lists everything. CI calls these same targets, so this file is the single
# source of truth for what gets run (see .github/workflows/ci.yml).

NVIM   ?= nvim
SELENE ?= selene
STYLUA ?= stylua
LUA_LS ?= lua-language-server
VIMRUNTIME ?= $(shell $(NVIM) --clean --headless +'lua io.write(vim.env.VIMRUNTIME)' +qa 2>/dev/null)
BENCH_BREAKDOWN_N ?= 50
BENCH_JIT_N ?= 100

.DEFAULT_GOAL := help

.PHONY: help test test-fast test-perf test-unit test-subset typecheck lint lint-tests \
	fmt fmt-check fast check e2e \
	bench bench-lua bench-compile bench-compare bench-breakdown bench-parse \
	bench-jit bench-jit-pro

# --- help ---

help: ## List available targets
	@printf '%s\n' 'Usage: make [target]' '' 'Targets:'
	@awk 'BEGIN {FS = ":.*## "} /^[[:alnum:]_.-]+:.*## / {printf "  %-18s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# --- tests ---

test: ## Integration suite (incl. spawned-session startup phases + perf)
	$(NVIM) --cmd "set rtp+=." -l tests/run.lua

test-fast: ## Integration suite, single session
	$(NVIM) --cmd "set rtp+=." -l tests/run.lua fast

test-perf: ## Perf thresholds only
	$(NVIM) --cmd "set rtp+=." -l tests/run.lua perf

test-unit: ## Compile/IR unit tests
	$(NVIM) --clean -l tests/test_compile.lua

test-subset: ## Spec-surface conformance
	$(NVIM) --clean -l tests/test_subset.lua

typecheck: ## LuaLS type check (Warning+), not part of check yet
	VIMRUNTIME=$(VIMRUNTIME) $(LUA_LS) --check=lua/laze --checklevel=Warning --check_format=pretty --configpath=$(abspath .luarc.json)

# --- lint + format ---

lint: ## Static lint, production (Selene 0.32.0)
	$(SELENE) lua

lint-tests: ## Static lint, tests
	$(SELENE) --config tests/selene.toml tests

fmt: ## Format in place (StyLua 2.6.0)
	$(STYLUA) .

fmt-check: ## Formatting check (CI)
	$(STYLUA) --check .

# --- aggregates ---

fast: test-fast test-unit test-subset fmt-check ## Curated quick gates (comment/edits)

check: test-unit test-subset test lint lint-tests fmt-check ## All gates (CI parity)

# --- README e2e (manual, network only) ---

e2e: ## README e2e; optional ARGS="oil flash" or "--failed" / "--clean"
	$(NVIM) --cmd "set rtp+=." -l tests/run.lua e2e_readme $(ARGS)

# --- benchmarks (manual, not CI) ---

bench: ## Cold/warm start + profile breakdown (bash)
	bash tests/benchmarks/bench.sh

bench-lua: ## Lua micro-benchmarks (us scale, multiple sizes)
	$(NVIM) --cmd "set rtp+=." -l tests/benchmarks/bench.lua

bench-compile: ## laze only: setup cost
	$(NVIM) -u NONE --headless -l tests/benchmarks/compile_only.lua

bench-compare: ## laze vs lazy.nvim setup comparison
	$(NVIM) -u NONE --headless -l tests/benchmarks/compile_compare.lua

bench-breakdown: ## Cold-setup breakdown (fixed vs per-spec; BENCH_BREAKDOWN_N=50)
	N=$(BENCH_BREAKDOWN_N) $(NVIM) --clean -l tests/benchmarks/breakdown.lua

bench-parse: ## Parse-cost oracle (median-of-60 in-process load)
	$(NVIM) --clean -l tests/benchmarks/parse_cost.lua

bench-jit: ## JIT A/B oracle (fresh process/row; BENCH_JIT_N=100)
	@for m in on off; do JIT=$$m N=$(BENCH_JIT_N) $(NVIM) --clean -l tests/benchmarks/jit_ab.lua; done

bench-jit-pro: ## JIT A/B oracle, probe workload (JIT=on|off, BENCH_JIT_N=100)
	WORKLOAD=probe JIT=on N=$(BENCH_JIT_N) $(NVIM) --clean -l tests/benchmarks/jit_ab.lua
	WORKLOAD=probe JIT=off N=$(BENCH_JIT_N) $(NVIM) --clean -l tests/benchmarks/jit_ab.lua
