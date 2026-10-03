# CLAUDE.md

Guidance for Claude Code in this repo. Agentic RAG sandbox: local LLMs via Ollama
(`http://localhost:11434`) + Pydantic AI. See [ARCHITECTURE.md](ARCHITECTURE.md)
for design, structure, models, Pydantic AI/Streamlit patterns and benchmarking.

## Commands

```bash
uv sync                                        # install
uv run streamlit run interfaces/streamlit_app.py   # run app
uv run ruff check . --fix                      # lint
uv run ruff format .                           # format
uv run pyrefly check                           # type check
uv run python -m bench --limit 2 -v            # benchmark smoke test
```

## Code Style

- `snake_case` functions/variables, `PascalCase` classes, `UPPER_CASE` constants,
  `_leading_underscore` private
- Type hints on all parameters and returns (`-> None` when nothing returned)
- Google-style docstrings; 4-space indent; max line length 88
- Imports grouped: stdlib, third-party, local (blank line between)

## Workflow

- **Napkin:** `.claude/napkin.md` holds the runbook and open Backlog items.
- **ADRs:** record significant decisions in `docs/adr/` (new ADR, don't edit
  accepted ones).
- **Changelog:** when a Backlog item is done, remove it from the napkin and add a
  brief line under `## Unreleased` in `CHANGELOG.md` before committing.

## Before Committing

1. `uv run ruff check . --fix`
2. `uv run ruff format .`
3. `uv run pyrefly check`
4. Test Streamlit UI / agent tool calling if behavior changed
5. Move done Backlog items to `CHANGELOG.md`
