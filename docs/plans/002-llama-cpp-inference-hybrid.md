# Plan: Hybrid Inference Backend — llama.cpp (GPU) + Ollama (CPU, embeddings)

Status: Proposed · Date: 2026-10-03 · Napkin: `.claude/napkin.md` (Backlog item 1)

## Context

Backlog item 1 originally called for a full swap of Ollama to llama.cpp for both
inference and embeddings. Assessment (two passes, informed by `/home/lw_na/git/ai-ragjus`
as a reference architecture) found that a full swap is not worth it: `llama-server`
loads exactly one GGUF per process (no multi-model daemon like Ollama's), so it would
*introduce* a two-process problem Ollama doesn't currently have, and would touch four
integration points, two with hidden regressions (tool-calling profile loss, model
capability-detection loss).

A narrower hybrid removes most of that risk: keep Ollama, CPU-pinned, for the
embedding model only; move just the inference/chat model to `llama-server` on the
GPU. This mirrors ai-ragjus's actual working architecture — two long-lived processes,
one per model, split by resource (GPU vs CPU) — except the GPU slot becomes
`llama-server` instead of a second Ollama instance.

Constraints: local models only, Pydantic AI, LanceDB, keep the benchmark harness and
Streamlit UI working, single consumer GPU (no VRAM contention tolerated).

## Findings that shape the plan

- `core/agent.py:72-75` — `OpenAIChatModel` wrapped in Pydantic AI's `OllamaProvider`.
  `OllamaProvider` is a thin `OpenAIProvider` subclass that also applies Ollama-specific
  `model_profile()` tuning (notably `openai_supports_strict_tool_definition=False`).
  Swapping to a plain `OpenAIProvider` pointed at llama-server needs an explicit
  `OpenAIModelProfile` override or tool-calling may silently regress — this is the one
  real risk in scope, and it is isolated to this file.
- `core/document_loader.py:27-33,53-55` — LanceDB's `"ollama"` embedding registry
  (`OllamaEmbeddings`, installed package) defaults `host="http://localhost:11434"`.
  As long as Ollama keeps serving on `11434`, this file needs **zero changes** —
  embeddings never move.
- `core/models.py:39-59` — `get_list_of_models()` drives the Streamlit model dropdown
  by calling `ollama.list()` + `ollama.show(...).capabilities`, filtering for `"tools"`
  (this is the automatic version of the napkin's "test tool calling before adopting a
  model" guardrail). `llama-server` has no equivalent listing/capability-introspection
  API — it loads one model, fixed at process start. The dropdown's "pick any installed
  tool-capable model" premise cannot be preserved for the inference slot; it collapses
  to one configured model name for llama-server, while any Ollama-specific logic here
  becomes unused for the inference picker (document as a known UX trade-off, not a bug).
- `bench/judge.py` — uses `ollama.chat()` directly for the LLM-as-judge. This is an
  independent evaluation path; it stays on Ollama regardless of what serves the agent's
  chat traffic and needs **no change**.
- `/home/lw_na/git/ai-ragjus/examples/ollama-serve-ai-ragjus.sh` is the reference
  pattern to adapt: two long-lived processes, `CUDA_VISIBLE_DEVICES` pins one to CPU,
  `trap cleanup EXIT INT TERM`, per-instance log files tailed with a prefix. (Its sibling
  `web/run_dual_ollama.sh` assigns the same two ports the opposite way — inconsistent
  with it and with this project's own `config.conf`-style convention; the `examples/`
  version's port layout, GPU first, is the one to follow.)
- GPU allocation is clean by construction here: only `llama-server` ever requests a
  CUDA context, so there is exactly one GPU consumer. Still explicitly pin the Ollama
  embedding instance off the GPU (`CUDA_VISIBLE_DEVICES=""`) so it can't opportunistically
  grab VRAM `llama-server` wants, carrying over ai-ragjus's convention rather than relying
  on embeddings being "too small to matter."

## Phases

Each phase is independently shippable. Move each to `CHANGELOG.md` when done.

### Phase 0: Spike — validate tool calling against llama-server (throwaway)
Do this before touching any of the files above.
1. Build/install `llama-server` in WSL2 (prefer a CUDA build; fall back to CPU-only
   just to validate correctness if the CUDA build is a blocker).
2. Acquire a GGUF for the current default chat model (e.g. a `qwen3:8b`-class quant)
   and start `llama-server --port 8080 -ngl 999` with it. Leave the existing Ollama
   instance exactly as-is on `11434` — nothing about embeddings changes in this phase.
3. Write a standalone throwaway script (outside `core/`) that builds an
   `OpenAIChatModel` with `OpenAIProvider(base_url="http://localhost:8080/v1")` and an
   explicit `OpenAIModelProfile(openai_supports_strict_tool_definition=False, ...)`,
   runs it against the project's actual `search_documents` tool schema (same shape
   `core/agent.py` registers), and confirms multi-turn tool calls are emitted and
   parsed correctly against the existing (unmodified) vector store.
4. Decision gate: if tool calling is reliable, proceed to Phase 1. If not, try
   adjusting the `ModelProfile` flags once before giving up. If still unreliable,
   write the ADR as Rejected, close backlog item 1 as "stay on Ollama", and stop here.

### Phase 1: Wire the hybrid backend
- New `scripts/start_llm_servers.sh` (adapted from ai-ragjus — see below) starts both
  long-lived processes: Ollama CPU-only on `11434` (embeddings) and `llama-server`
  GPU-enabled on `8080` (inference).
- `core/agent.py`: replace `OllamaProvider(base_url="http://localhost:11434/v1")` with
  `OpenAIProvider(base_url="http://localhost:8080/v1")` plus the explicit
  `OpenAIModelProfile` override validated in Phase 0.
- `core/document_loader.py`: no change (confirmed in Findings).
- `bench/judge.py`: no change (confirmed in Findings).

### Phase 2: Model-picker UX trade-off
- `core/models.py` / `interfaces/streamlit_app.py`: collapse the inference model
  dropdown to a single configured llama-server model name (changing it means
  restarting `llama-server` with a different `--model`, not a dropdown pick).
  Decide whether `get_list_of_models()`'s Ollama-based capability filter has any
  remaining use (likely none for inference once collapsed) and remove or repurpose it
  rather than leaving dead code.
- Document the trade-off explicitly in the ADR and `CHANGELOG.md`: dynamic inference
  model switching in the UI is intentionally dropped in exchange for the GPU/CPU split.

### Phase 3: Process supervision hardening (optional, lower priority)
- `scripts/start_llm_servers.sh` run manually/in a terminal is sufficient for this
  sandbox project (matches ai-ragjus's own level of supervision). Only revisit
  `systemd --user` units if the manual script proves unreliable in practice.

## Decisions (ADRs)
- 0002: hybrid inference backend (llama.cpp GPU inference + Ollama CPU embeddings),
  written at the Phase 0 decision gate as Accepted or Rejected.

## Critical files
`core/agent.py`, `core/models.py`, `interfaces/streamlit_app.py`,
new `scripts/start_llm_servers.sh`, `docs/adr/`, `CHANGELOG.md`, `.claude/napkin.md`.
Confirmed out of scope: `core/document_loader.py`, `bench/judge.py`.

## Verification
- Static: `uv run ruff check . --fix`, `uv run ruff format .`, `uv run pyrefly check`.
- Phase 0: throwaway script confirms tool calls against the real `search_documents`
  schema, multi-turn, no silent fallback to plain text.
- End to end: `uv run streamlit run interfaces/streamlit_app.py` after Phase 1/2 —
  ask a question that needs a tool call, confirm sources are retrieved and answered;
  confirm embeddings still work unchanged (no re-index needed).
- Benchmark: `uv run python -m bench --limit 2 -v` smoke test; judge path untouched so
  no score-calculation regression expected, only the generation side should change.
