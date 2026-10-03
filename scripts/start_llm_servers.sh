#!/bin/bash
# =========================================================================
# Hybrid LLM Backend Launcher: llama.cpp (GPU, inference) + Ollama (CPU, embeddings)
# =========================================================================
# Adapted from ai-ragjus's examples/ollama-serve-ai-ragjus.sh dual-Ollama launcher
# (docs/plans/002-llama-cpp-inference-hybrid.md), with the llama-server side's
# interactive model/context picker adapted from ~/run-llama-claude.sh:
#   - llama-server (GPU, inference): model and --ctx-size are chosen
#     interactively at startup; every other llama-server flag is fixed, not
#     prompted (reasoning stays on; --jinja, flash-attn, cache quantization,
#     sampling, threading are all hardcoded below).
#   - ollama serve  (CPU-only, embeddings, port 11434): unattended, matches
#     core/document_loader.py's default host.
# Only llama-server ever requests a CUDA context, so there is no GPU
# contention between the two. CUDA_VISIBLE_DEVICES="" on the Ollama instance
# keeps it from opportunistically grabbing VRAM regardless.
#
# Usage:
#   bash scripts/start_llm_servers.sh
#
# Config (env vars, all optional):
#   LLAMA_SERVER_BIN   llama-server binary (default: llama-server on PATH,
#                      falling back to ~/llama.cpp/build/bin/llama-server)
#   MODEL_DIR          directory of GGUF models to pick from (default: ~/models-llm)
#   LLAMA_PORT         llama-server port (default: 8080)
#   OLLAMA_PORT        Ollama port for embeddings (default: 11434, matches
#                      core/document_loader.py's default host)

set -eo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODEL_DIR="${MODEL_DIR:-$HOME/models-llm}"
LLAMA_PORT="${LLAMA_PORT:-8080}"
OLLAMA_PORT="${OLLAMA_PORT:-11434}"

if [ -n "${LLAMA_SERVER_BIN:-}" ]; then
    : # explicit override, use as-is
elif command -v llama-server &> /dev/null; then
    LLAMA_SERVER_BIN="llama-server"
else
    LLAMA_SERVER_BIN="$HOME/llama.cpp/build/bin/llama-server"
fi

LOG_DIR="${PROJECT_ROOT}/.logs"
mkdir -p "$LOG_DIR"

LLAMA_LOG="$LOG_DIR/llama-server.log"
OLLAMA_LOG="$LOG_DIR/ollama-cpu.log"
: > "$LLAMA_LOG"
: > "$OLLAMA_LOG"

echo "=========================================================================="
echo "local-LLM-with-RAG - Hybrid Backend Launcher"
echo "=========================================================================="
echo ""
echo "  * llama-server (GPU, inference) on port $LLAMA_PORT"
echo "  * ollama serve  (CPU, embeddings) on port $OLLAMA_PORT"
echo ""

if [ ! -d "$MODEL_DIR" ]; then
    echo "Error: MODEL_DIR '$MODEL_DIR' does not exist." >&2
    exit 1
fi

if ! command -v "$LLAMA_SERVER_BIN" &> /dev/null && [ ! -x "$LLAMA_SERVER_BIN" ]; then
    echo "Error: '$LLAMA_SERVER_BIN' not found. Build/install llama.cpp first." >&2
    echo "See: https://github.com/ggml-org/llama.cpp" >&2
    exit 1
fi

if ! command -v ollama &> /dev/null; then
    echo "Error: Ollama not found. Install it first: https://ollama.ai" >&2
    exit 1
fi

# -------------------------------------------------------------------------
# Interactive: pick the inference model (only interactive choice besides ctx)
# -------------------------------------------------------------------------
mapfile -t models < <(find -L "$MODEL_DIR" -maxdepth 1 -name "*.gguf" -type f ! -name "*-mmproj.gguf")

if [ ${#models[@]} -eq 0 ]; then
    echo "Error: No .gguf files found in $MODEL_DIR (excluding mmproj)" >&2
    exit 1
fi

echo "Available models:"
for i in "${!models[@]}"; do
    echo "$((i + 1)). $(basename "${models[$i]}")"
done

echo ""
read -r -p "Select a model (1-${#models[@]}) [1]: " choice
choice="${choice:-1}"

if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#models[@]} ]; then
    echo "Error: Invalid selection" >&2
    exit 1
fi

selected_model="${models[$((choice - 1))]}"
selected_model_name=$(basename "$selected_model" .gguf)

echo ""
echo "Selected model: $(basename "$selected_model")"

# mmproj (vision) is auto-detected and auto-enabled when present, not prompted.
mmproj_file="$MODEL_DIR/${selected_model_name}-mmproj.gguf"
mmproj_param=()
if [ -f "$mmproj_file" ]; then
    echo "Vision support detected, enabling: $mmproj_file"
    mmproj_param=(--mmproj "$mmproj_file")
fi

# Detect model size from name (e.g. Qwen3.5-4B) to suggest a sane ctx/keep
# default; this heuristic is automatic, not a prompted option.
if [[ "$selected_model_name" =~ ([0-9]+)B ]]; then
    model_size=${BASH_REMATCH[1]}
else
    model_size=9 # fallback
fi

case "$model_size" in
    1 | 2 | 3 | 4)
        ctx_suggestion=16384
        keep_size=2048
        ;;
    7 | 8 | 9)
        ctx_suggestion=8192
        keep_size=2048
        ;;
    13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27)
        ctx_suggestion=4096
        keep_size=1024
        ;;
    *)
        ctx_suggestion=8192
        keep_size=2048
        ;;
esac

# -------------------------------------------------------------------------
# Interactive: pick the context size (second and last interactive choice)
# -------------------------------------------------------------------------
echo ""
echo "Select context size (--ctx-size):"
echo "1) 4k (4096)"
echo "2) 8k (8192)"
echo "3) 16k (16384)"
echo "4) 32k (32768)"
echo "5) 64k (65536)"
echo "6) 96k (98304)"
echo "7) 128k (131072)"
read -r -p "Choose (1-7) [default: ${ctx_suggestion}]: " ctx_choice

case "$ctx_choice" in
    1) ctx_size=4096 ;;
    2) ctx_size=8192 ;;
    3) ctx_size=16384 ;;
    4) ctx_size=32768 ;;
    5) ctx_size=65536 ;;
    6) ctx_size=98304 ;;
    7) ctx_size=131072 ;;
    *) ctx_size=$ctx_suggestion ;;
esac

echo "Context size set to: $ctx_size"
echo ""

cleanup() {
    echo ""
    echo "[*] Stopping llama-server and Ollama..."
    [ -n "${LLAMA_PID:-}" ] && kill "$LLAMA_PID" 2>/dev/null || true
    [ -n "${OLLAMA_PID:-}" ] && kill "$OLLAMA_PID" 2>/dev/null || true
    wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "[*] Starting llama-server (GPU, inference) on port $LLAMA_PORT..."
# Fixed, non-interactive flags: full GPU offload, reasoning left on (no
# --reasoning flag means the jinja chat template's default applies),
# "General" sampling profile, flash attention + q8_0 KV cache, 1 parallel
# slot, 4 threads.
"$LLAMA_SERVER_BIN" \
    --host 127.0.0.1 --port "$LLAMA_PORT" \
    --model "$selected_model" \
    "${mmproj_param[@]}" \
    --n-gpu-layers 99 \
    --ctx-size "$ctx_size" \
    --keep "$keep_size" \
    --jinja \
    --flash-attn on \
    --cache-type-k q8_0 \
    --cache-type-v q8_0 \
    --parallel 1 \
    --threads 4 \
    --temp 0.7 \
    --top-k 20 \
    --top-p 0.95 \
    --presence-penalty 1.5 \
    --repeat-penalty 1.05 \
    >> "$LLAMA_LOG" 2>&1 &
LLAMA_PID=$!

echo "[*] Starting Ollama (CPU-only, embeddings) on port $OLLAMA_PORT..."
CUDA_VISIBLE_DEVICES="" OLLAMA_KEEP_ALIVE=24h \
    ollama serve --addr "127.0.0.1:${OLLAMA_PORT}" \
    >> "$OLLAMA_LOG" 2>&1 &
OLLAMA_PID=$!

sleep 2

echo ""
echo "[*] Both servers started. Monitoring logs (Ctrl+C to stop both)..."
echo ""

tail -F "$LLAMA_LOG" 2>/dev/null | sed "s/^/[LLAMA-${LLAMA_PORT}] /" &
TAIL_LLAMA_PID=$!
tail -F "$OLLAMA_LOG" 2>/dev/null | sed "s/^/[OLLAMA-${OLLAMA_PORT}] /" &
TAIL_OLLAMA_PID=$!

wait "$LLAMA_PID" "$OLLAMA_PID" 2>/dev/null || true
kill "$TAIL_LLAMA_PID" "$TAIL_OLLAMA_PID" 2>/dev/null || true
