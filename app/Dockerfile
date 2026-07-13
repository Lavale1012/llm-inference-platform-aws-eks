# llama.cpp server image (CUDA build) — ships llama-server (OpenAI-compatible
# API) prebuilt WITH GPU support. The plain ":server" tag is CPU-only; this
# CUDA tag is required to use the g5 node's GPU.
# Tag verified to resolve on ghcr.io (2026-07-13). Bump the b#### to update.
FROM ghcr.io/ggml-org/llama.cpp:server-cuda-b4738

# Bake a small quantized model into the image (self-contained; no volumes /
# init containers needed on EKS). Verified ~773 MB, ungated (2026-07-13).
ADD https://huggingface.co/unsloth/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-IQ4_NL.gguf /models/model.gguf

EXPOSE 8080

# llama-server exposes /health once the model is loaded.
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD curl -fsS http://localhost:8080/health || exit 1

# The base image's entrypoint is llama-server; we supply arguments.
# -ngl 999 offloads ALL layers to the GPU — without it inference runs on CPU
# even on the CUDA image.
CMD ["-m", "/models/model.gguf", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--ctx-size", "4096", \
     "-ngl", "999"]
