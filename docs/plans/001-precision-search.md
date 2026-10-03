# Plan: High-Precision Agentic Document Search

Status: Proposed · Date: 2026-10-03 · Napkin: `.claude/napkin.md` (Backlog)

## Context

The agent can only call `search_documents` (embedding search over LanceDB) and is
capped at 4 tool calls (`UsageLimits(tool_calls_limit=4)`). It cannot grep raw files,
read arbitrary files, or iterate freely, so precision is limited to what pre-chunked
embeddings return. Goal: approach Claude Code-style accuracy, where the agent
reasons about what to read, searches iteratively, and cites exact file and lines.

Constraints: local models only (Ollama now; hybrid llama.cpp inference + Ollama
embeddings per Backlog item 1 / `docs/plans/002-llama-cpp-inference-hybrid.md`),
Pydantic AI, LanceDB, MarkItDown formats, no heavy infrastructure. Keep embedding
search, the benchmark harness and the Streamlit UI.

## Findings that shape the plan

- Tools are registered with `@self.agent.tool` inside `ResearchAgent.__post_init__`
  (`core/agent.py:105-139`). `AgentDeps` (`core/agent.py:21-26`) is the place for a
  root path and file-type config.
- The tool cap lives in two places: `interfaces/streamlit_app.py:27` and
  `bench/runner.py:30-31` (`--max-tool-calls` flag in `bench/cli.py`).
- `chat_stream_with_tools` (`core/agent.py:219-260`) yields only `tool_call` and
  `text` events. Tool results are never surfaced, so the UI cannot show reasoning
  and the bench cannot measure retrieved sources.
- The UI and bench read `args["query"]` (`streamlit_app.py:198`, `runner.py:65`).
  New tools use other arg names, so this must be generalised.
- `load_file` sets `page=1` for every chunk (`core/document_loader.py:90-109`), so
  current citations are not real pages. Schema has no file-type or mtime field.
- No tests, no `rg` usage, no config module. `rg` may be absent on Windows, so
  every search tool needs a pure-Python fallback.

## Phases

Each phase is independently shippable. Move each to `CHANGELOG.md` when done.

### Phase 0: Prerequisite, hybrid backend
Napkin Backlog item 1: `docs/plans/002-llama-cpp-inference-hybrid.md` (llama.cpp
inference on GPU, Ollama kept for embeddings on CPU — not a full Ollama swap). Do
first or in parallel; keep the new tools backend-agnostic (they depend only on
Pydantic AI). Needs an ADR (0002, at that plan's Phase 0 gate).

### Phase 1: Filesystem tools (highest impact)
New module `core/fs_tools.py` with plain functions returning structured, size-capped
results (dataclass or typed dict rendered to compact text):
- `grep_search(pattern, path, max_results=20)`: pure-Python regex fallback.
- `ripgrep_search(...)`: use `shutil.which("rg")`, otherwise delegate to grep.
  Return `file:line: text` plus surrounding context lines.
- `find_files(pattern, path)`: glob/fnmatch, respects ignore list.
- `read_file(filepath, start_line=1, max_lines=200)`: line-numbered output; use
  MarkItDown for binary formats (pdf, docx...) so they are readable too.
- `list_directory(path)`: one level, with sizes.
- `file_stats(path)`: lines, size, mtime, file type (Phase 4).

Safety: resolve every path and reject anything outside `AgentDeps.root_path`
(no traversal, no symlink escape); cap output bytes; ignore `.git`, `node_modules`,
`.venv`, `storage/`; subprocess with list args, no shell, timeout.
Register in `ResearchAgent.__post_init__`; add `root_path` to `AgentDeps`.
Generalise tool-arg display in UI and bench (replace `args["query"]` lookups).

### Phase 2: Iterative reasoning loop
- Replace the fixed cap with a configurable budget (default 10) in one place,
  new `core/config.py` (`MAX_TOOL_CALLS`, chunk size, ignore list), imported by the
  app and `bench/runner.py`.
- Search history: store the executed (tool, args) set on `AgentDeps`; a repeated
  identical call returns "already searched, refine the query" instead of re-running.
- Convergence: prompt-driven ("state what is still missing; stop when answerable")
  plus a hard stop at the budget. On `UsageLimitExceeded`, force a final answer
  from gathered context rather than erroring.

### Phase 3: Hybrid retrieval
Prompt-guided three-phase strategy, plus a supporting tool:
1. `search_documents` returns candidate files (add file path to results).
2. `grep_search`/`ripgrep_search` scoped to those candidates.
3. `read_file` around matched lines for exact context.
Optional: add a LanceDB FTS index (`create_fts_index("text")`) and hybrid query
for the embedding tool. Fix real page numbers in `load_file` where the converter
exposes them.

### Phase 4: File-type awareness
- Add `file_type`, `mtime` to the `Document` schema (forces re-index; note in
  CHANGELOG). Extend `SUPPORTED_EXTENSIONS` with text/code types.
- `file_stats` tool plus a priority table (source/docs high; lock files, images,
  `.gitignore` low) used to rank `find_files`/grep output and described in the prompt.

### Phase 5: Prompting and visibility
- System prompt: precision over speed, cite `path:line` (or path + page for
  converted docs), say when unsure and search more, show what is still missing.
- Add `tool_result` and `thinking` event types in `chat_stream_with_tools`.
- Streamlit: "Show reasoning steps" toggle after the folder input
  (`streamlit_app.py:75`); render each tool call and a result summary in the
  `st.status` block; persist steps per message.

### Phase 6: Benchmark
- Extend `bench/questions.jsonl` with `expected_sources` (and a few repo-wide
  questions). docs/ARCHITECTURE.md says 10 questions but the file has 13; fix it.
- Capture tool results in `QuestionResult`; add citation validity (cited
  file/line exists and contains the claim) and source recall/precision columns to
  `_judge_phase` and `_write_summary`.
- Baseline on current main before Phase 1, then compare after each phase.

## Decisions (ADRs)
- 0002: hybrid inference backend, llama.cpp (GPU) + Ollama (CPU, embeddings) (Phase 0).
- 0003: agent filesystem access and sandboxing model (Phase 1).

## Critical files
`core/agent.py`, `core/document_loader.py`, `core/__init__.py` (exports),
`interfaces/streamlit_app.py`, `bench/runner.py`, `bench/cli.py`,
`bench/questions.jsonl`, new `core/fs_tools.py`, `core/config.py`, docs/ARCHITECTURE.md
(tool code excerpt and project tree), `docs/adr/`.

## Verification
- Static: `uv run ruff check . --fix`, `uv run ruff format .`, `uv run pyrefly check`.
- Tools: small `pytest` module for `fs_tools` (path traversal rejected, caps,
  rg-missing fallback). Adds pytest as a dev dependency.
- End to end: `uv run streamlit run interfaces/streamlit_app.py`, ask a question
  that needs grep over a repo folder; confirm multiple tool calls, `path:line`
  citations, reasoning toggle, and that plain embedding Q&A still works.
- Benchmark: `uv run python -m bench --limit 2 -v` smoke test, then full run; no
  score regression on existing questions, and precision columns improve.
