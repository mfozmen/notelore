"""Local models over Ollama's REST API (``/api/chat``). Key-less.

OpenAI-like wire shape with two twists: tool calls carry no id (one is
synthesized here) and tool results are correlated by ``tool_name``.
"""

from __future__ import annotations

import os
import uuid
from typing import Any

from notelore.providers import http
from notelore.providers.base import (
    AgentResponse,
    Block,
    Message,
    Tool,
    parse_arguments,
    split_blocks,
    tool_use_names,
)

DEFAULT_HOST = "http://localhost:11434"
TIMEOUT_SECONDS = 180.0  # a cold local model legitimately takes a while for its first token


def host() -> str:
    return os.environ.get("OLLAMA_HOST", DEFAULT_HOST).rstrip("/")


class OllamaProvider:
    def __init__(self, model: str) -> None:
        self._model = model

    def turn(self, system: str, messages: list[Message], tools: list[Tool]) -> AgentResponse:
        preamble = [{"role": "system", "content": system}] if system else []
        body: dict[str, Any] = {
            "model": self._model,
            "messages": preamble + to_ollama(messages),
            "stream": False,
        }
        if tools:
            body["tools"] = [
                {
                    "type": "function",
                    "function": {
                        "name": t.name,
                        "description": t.description,
                        "parameters": t.input_schema,
                    },
                }
                for t in tools
            ]
        return from_ollama(http.request("POST", f"{host()}/api/chat", None, body, TIMEOUT_SECONDS))


def to_ollama(messages: list[Message]) -> list[dict[str, Any]]:
    names = tool_use_names(messages)
    out: list[dict[str, Any]] = []
    for message in messages:
        texts, uses, results = split_blocks(message["content"])
        if message["role"] == "assistant":
            entry: dict[str, Any] = {"role": "assistant", "content": "".join(texts)}
            if uses:
                entry["tool_calls"] = [
                    {"function": {"name": u.get("name", ""), "arguments": u.get("input") or {}}}
                    for u in uses
                ]
            out.append(entry)
            continue
        out.extend(
            {
                "role": "tool",
                "content": r.get("content", ""),
                "tool_name": names.get(str(r.get("tool_use_id", "")), ""),
            }
            for r in results
        )
        out.extend({"role": "user", "content": text} for text in texts)
    return out


def from_ollama(answer: dict[str, Any]) -> AgentResponse:
    blocks: list[Block] = []
    message = answer.get("message")
    if not message:
        return AgentResponse(blocks, "end_turn")
    if message.get("content"):
        blocks.append({"type": "text", "text": message["content"]})
    for call in message.get("tool_calls") or []:
        blocks.append(
            {
                "type": "tool_use",
                "id": f"toolu_{uuid.uuid4().hex[:12]}",
                "name": call["function"]["name"],
                "input": parse_arguments(call["function"].get("arguments")),
            }
        )
    tool_use = any(b["type"] == "tool_use" for b in blocks)
    return AgentResponse(blocks, "tool_use" if tool_use else "end_turn")
