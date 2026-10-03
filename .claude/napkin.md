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

## User Directives
1. **[2026-10-03] Done backlog items go to CHANGELOG.md before commit**
   Do instead: remove the item from the napkin Backlog and add a one-line description under `## Unreleased` in `CHANGELOG.md`.

2. **[2026-10-03] Significant architectural decisions get an ADR**
   Do instead: copy `docs/adr/template.md` to the next `NNNN-title.md` and add it to the index in `docs/adr/README.md`.

3. **[2026-10-03] Follow CLAUDE.md style: 88-col lines, type hints everywhere, Google-style docstrings, grouped imports**
   Do instead: match these conventions in all new code.
