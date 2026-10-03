# Napkin Runbook

## Curation Rules
- Re-prioritize on every read.
- Keep recurring, high-value notes only.
- Max 10 items per category.
- Each item includes date + "Do instead".

## Execution & Validation (Highest Priority)
1. **[2026-10-03] Pre-commit checks are mandatory**
   Do instead: run `uv run ruff check . --fix`, `uv run ruff format .`, `uv run pyrefly check` before any commit.

2. **[2026-10-03] App and benchmarks need local Ollama at localhost:11434**
   Do instead: confirm Ollama is running before `streamlit run` or `python -m bench`; use `--limit 2 -v` for smoke tests.

## Shell & Command Reliability
1. **[2026-10-03] Platform is Windows; Bash tool is Git Bash, PowerShell is primary**
   Do instead: use `uv run ...` commands; use POSIX syntax in Bash tool, PowerShell syntax (no `&&`) in PowerShell tool.

## Domain Behavior Guardrails
1. **[2026-10-03] Not every Ollama model supports tool calling; MoE models with few active params are unreliable**
   Do instead: default to `qwen3.5:9b` or `qwen3:8b`; test tool calling before adopting a new model.

2. **[2026-10-03] Vector store reloads only when folder path changes**
   Do instead: don't expect a model switch to re-index; change folder or clear `storage/` to force reload.

## Backlog
(Open items only. When done, move to CHANGELOG.md before commit.)
1. **[2026-10-03] Hybrid backend: llama.cpp (GPU, inference) + Ollama (CPU, embeddings)**
   Do instead: follow `docs/plans/002-llama-cpp-inference-hybrid.md` phase by phase (Phase 0 is a throwaway tool-calling spike, gate before touching any code); scope narrowed from a full Ollama→llama.cpp swap after assessment showed embeddings should stay on Ollama. Record the decision in ADR 0002 at the Phase 0 gate.

2. **[2026-10-03] High-precision agentic document search (filesystem tools, iterative loop, hybrid retrieval)**
   Do instead: follow `docs/plans/001-precision-search.md` phase by phase (Phase 0 is item 1); move each finished phase to CHANGELOG.md.

## User Directives
0. **[2026-10-03] Plans live in `docs/plans/` as ordered, numbered `NNN-plan-name.md`**
   Do instead: use the next free zero-padded number (never renumber) and reference the plan from the Backlog.

1. **[2026-10-03] Done backlog items go to CHANGELOG.md before commit**
   Do instead: remove the item from the napkin Backlog and add a one-line description under `## Unreleased` in `CHANGELOG.md`.

2. **[2026-10-03] Significant architectural decisions get an ADR**
   Do instead: copy `docs/adr/template.md` to the next `NNNN-title.md` and add it to the index in `docs/adr/README.md`.

3. **[2026-10-03] Follow CLAUDE.md style: 88-col lines, type hints everywhere, Google-style docstrings, grouped imports**
   Do instead: match these conventions in all new code.
