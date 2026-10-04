"""GPT over the Chat Completions API.

Translation at the boundary: assistant ``tool_use`` blocks become ``tool_calls``
with JSON-string arguments, user ``tool_result`` blocks become ``role: tool``
messages, and the completion comes back as Anthropic-style blocks.
"""

from __future__ import annotations

import json
from typing import Any

from notelore.providers import http
from notelore.providers.base import (
    AgentResponse,
    Block,
    Message,
    Tool,
    parse_arguments,
    split_blocks,
)

API = "https://api.openai.com/v1/chat/completions"
MODELS = "https://api.openai.com/v1/models"
TIMEOUT_SECONDS = 60.0


def headers(api_key: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {api_key}"}


class OpenAIProvider:
    def __init__(self, api_key: str, model: str) -> None:
        self._api_key, self._model = api_key, model

    def turn(self, system: str, messages: list[Message], tools: list[Tool]) -> AgentResponse:
        preamble = [{"role": "system", "content": system}] if system else []
        body: dict[str, Any] = {"model": self._model, "messages": preamble + to_openai(messages)}
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
        return from_openai(http.request("POST", API, headers(self._api_key), body, TIMEOUT_SECONDS))


def to_openai(messages: list[Message]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for message in messages:
        texts, uses, results = split_blocks(message["content"])
        if message["role"] == "assistant":
            entry: dict[str, Any] = {"role": "assistant", "content": "".join(texts) or None}
            if uses:
                entry["tool_calls"] = [
                    {
                        "id": u.get("id", ""),
                        "type": "function",
                        "function": {
                            "name": u.get("name", ""),
                            "arguments": json.dumps(u.get("input") or {}),
                        },
                    }
                    for u in uses
                ]
            out.append(entry)
            continue
        out.extend(
            {
                "role": "tool",
                "tool_call_id": r.get("tool_use_id", ""),
                "content": r.get("content", ""),
            }
            for r in results
        )
        out.extend({"role": "user", "content": text} for text in texts)
    return out


def from_openai(completion: dict[str, Any]) -> AgentResponse:
    blocks: list[Block] = []
    choices = completion.get("choices") or []
    if not choices:
        return AgentResponse(blocks, "end_turn")
    message = choices[0].get("message") or {}
    if message.get("content"):
        blocks.append({"type": "text", "text": message["content"]})
    for call in message.get("tool_calls") or []:
        blocks.append(
            {
                "type": "tool_use",
                "id": call.get("id", ""),
                "name": call["function"]["name"],
                "input": parse_arguments(call["function"].get("arguments")),
            }
        )
    tool_use = any(b["type"] == "tool_use" for b in blocks)
    finish = choices[0].get("finish_reason")
    if not tool_use and finish not in (None, "stop"):
        blocks.append({"type": "text", "text": f"[The model stopped early: {finish}.]"})
    return AgentResponse(blocks, "tool_use" if tool_use else "end_turn")
