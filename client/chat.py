#!/usr/bin/env python3
"""Minimal CLI chat client for the llama.cpp server deployed on EKS.

llama-server exposes an OpenAI-compatible API, so we use the openai SDK and
just point it at the ALB. No API key is required (llama-server ignores it), but
the SDK insists one is set, so we pass a dummy.

Usage:
    export LLM_ENDPOINT="http://<alb-dns-name>"   # from: kubectl get ingress -n llm
    python chat.py

Requires: pip install openai  (see requirements.txt)
"""
import os
import sys

from openai import OpenAI

# The ALB URL. Get it after deploy with:
#   kubectl get ingress llm-inference -n llm -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
endpoint = os.environ.get("LLM_ENDPOINT")
if not endpoint:
    sys.exit("Set LLM_ENDPOINT to your ALB URL, e.g. http://my-alb-123.us-east-1.elb.amazonaws.com")

client = OpenAI(
    base_url=f"{endpoint.rstrip('/')}/v1",
    api_key="not-needed",  # llama-server does not check this
)

# Keep a running conversation so context carries across turns.
messages = [{"role": "system", "content": "You are a helpful assistant."}]

print(f"Connected to {endpoint}. Type your message (Ctrl-C or 'exit' to quit).\n")
while True:
    try:
        user_input = input("you> ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        break
    if user_input.lower() in {"exit", "quit"}:
        break
    if not user_input:
        continue

    messages.append({"role": "user", "content": user_input})

    # Stream the response token-by-token for a snappier feel.
    print("llm> ", end="", flush=True)
    reply = ""
    try:
        stream = client.chat.completions.create(
            model="local-model",  # llama-server serves whatever GGUF is loaded
            messages=messages,
            stream=True,
        )
        for chunk in stream:
            delta = chunk.choices[0].delta.content or ""
            reply += delta
            print(delta, end="", flush=True)
        print("\n")
    except Exception as exc:  # network / server errors surface here
        print(f"\n[error talking to the model: {exc}]\n")
        messages.pop()  # drop the unanswered user turn
        continue

    messages.append({"role": "assistant", "content": reply})
