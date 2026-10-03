# Architecture

Experimental sandbox for **agentic RAG** using local LLMs via Ollama and Pydantic AI.
Unlike fixed RAG pipelines, the agent decides when and how to search documents.
Decisions are recorded in [docs/adr/](docs/adr/README.md).

**Key constraint:** Ollama must be running locally at `http://localhost:11434`.

## Overview

```
interfaces/streamlit_app.py ──▶ core/agent.py (ResearchAgent) ──▶ Ollama LLM
                                        │
                                        │ @agent.tool
                                        ▼
                                 core/document_loader.py ──▶ LanceDB (storage/)
                                        │
                                        ▼
                                 Ollama Embeddings (nomic-embed-text)
```

**Core flow:**
1. Documents loaded from a folder into LanceDB (PDF, Word, PowerPoint, Excel,
   Markdown, HTML, CSV, JSON via MarkItDown).
2. `ResearchAgent` uses Pydantic AI with a `search_documents` tool.
3. The agent decides whether to search or answer directly.
4. Responses stream via `agent.run_stream_sync()`.

## Project Structure

```
├── core/
│   ├── agent.py                  # Pydantic AI agent with RAG tool
│   ├── document_loader.py        # Document loading, LanceDB integration
│   └── models.py                 # Ollama model management
├── interfaces/
│   └── streamlit_app.py          # Streamlit web interface (main entry point)
├── bench/                        # Model benchmarking harness
│   ├── questions.jsonl           # Eval questions w/ golden answers + key facts
│   ├── runner.py                 # Runs a model via ResearchAgent, captures metrics
│   ├── judge.py                  # LLM-as-judge (Ollama) scoring vs golden answers
│   └── cli.py                    # CLI orchestrator -> results/scores.csv + summary.md
├── docs/adr/                     # Architecture decision records
├── Research/                     # Sample documents
└── storage/                      # LanceDB vector store (gitignored)
```

## Tech Stack

- **Pydantic AI**: agent orchestration, tool calling, streaming
- **LanceDB**: vector store with native Ollama embeddings
- **MarkItDown**: document loading
- **Ollama**: local LLM and embeddings
- **Streamlit**: web interface

## Models

- Default LLM: `qwen3.5:9b`; alternative: `qwen3:8b`
- Default embeddings: `nomic-embed-text` (768 dimensions)
- Judge for benchmarks: `qwen3-coder:480b-cloud` (free-tier Ollama cloud)
- Some models don't support tool calling in Ollama - test before using
- Hybrid/MoE models with few active parameters (e.g. `lfm2.5:8b-a1b`) are
  unreliable for agentic RAG
- Vector store reloads only when the folder path changes (not on model switch)

## Pydantic AI Patterns

### Agent setup
```python
model = OpenAIChatModel(
    model_name=self.llm_model,
    provider=OllamaProvider(base_url="http://localhost:11434/v1"),
)
agent = Agent(model, deps_type=AgentDeps, system_prompt="...")
```

### Tools
- Async functions decorated with `@agent.tool`
- First parameter is `RunContext[DepsType]`
- Return JSON-serializable types

```python
@self.agent.tool
async def search_documents(ctx: RunContext[AgentDeps], query: str) -> str:
    query_embedding = embedding_func.compute_query_embeddings(query)[0]
    results = ctx.deps.vector_store.search(query_embedding).limit(10).to_list()
    parts = []
    for i, doc in enumerate(results, 1):
        parts.append(f"--- Result {i} ---")
        parts.append(f"Source: {doc['source']}, Page: {doc['page']}")
        parts.append(doc["text"].strip())
    parts.append("--- End of results ---")
    return "\n\n".join(parts)
```

### Streaming
```python
response = self.agent.run_stream_sync(
    question,
    deps=deps,
    message_history=history,
    model_settings=model_settings,
    usage_limits=usage_limits,
)
last_text = ""
for text in response.stream_text():
    yield text[len(last_text):]  # yield only the delta
    last_text = text
```

## Streamlit

- Persist state in `st.session_state` (check `if "key" not in st.session_state:`)
- `st.spinner` for long operations, `st.chat_message` for chat,
  `st.status` for tool call activity

## Benchmarking

`bench/` compares models on the agentic RAG pipeline. Each candidate runs against
`bench/questions.jsonl` (10 questions: factual, methodology, numeric, comparison);
a larger judge model scores answers 1-5 against golden answers + key facts.

**Captured per (model, question):** answer text, `search_documents` call count,
total time, time-to-first-text, judge score, covered facts.

**Outputs** (`bench/results/`, gitignored):
- `raw/<model>.jsonl` - full raw outputs per model
- `scores.csv` - one row per (model, question)
- `summary.md` - per-model averages + per-question score table

To add questions, append lines to `bench/questions.jsonl` with `id`, `category`,
`question`, `reference_answer`, and `key_facts` (list the judge checks).

```bash
uv run python -m bench --models qwen3:8b qwen3:14b qwen3.5:9b --judge qwen3-coder:480b-cloud
uv run python -m bench --limit 2 -v          # quick smoke test
uv run python -m bench --skip-run             # re-judge existing raw outputs
uv run python -m bench --max-tool-calls 3     # tighten search loop protection
```
