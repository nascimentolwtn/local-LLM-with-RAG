# 0001. Agentic RAG with Pydantic AI and local Ollama

- Status: Accepted
- Date: 2026-10-03

## Context
Fixed RAG pipelines always retrieve, even when unnecessary. The project is a
sandbox for letting a local LLM decide when and how to search documents.

## Decision
Use a Pydantic AI agent with a `search_documents` tool over a LanceDB vector
store, with Ollama serving both the LLM and embeddings (`nomic-embed-text`).

## Consequences
- Fully local; requires Ollama running at `localhost:11434`.
- Quality depends on the model's tool-calling ability (see `bench/`).
- Search-loop protection (usage/tool-call limits) is needed.
