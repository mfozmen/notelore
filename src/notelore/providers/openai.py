"""GPT via the OpenAI Chat Completions API.

Translation at the boundary: assistant ``tool_use`` blocks become ``tool_calls``
with JSON-string arguments, user ``tool_result`` blocks become ``role: tool``
messages, and the completion comes back as Anthropic-style blocks.
"""

from __future__ import annotations

import json
from typing import Any

from notelore.providers.base import (
    AgentResponse,
    Block,
    Message,
    Tool,
    parse_arguments,
    split_blocks,
)

TIMEOUT_SECONDS = 60.0


class OpenAIProvider:
    def __init__(self, api_key: str, model: str) -> None:
        self._api_key, self._model = api_key, model

    def turn(self, system: str, messages: list[Message], tools: list[Tool]) -> AgentResponse:
        import openai

        client = openai.OpenAI(api_key=self._api_key, timeout=TIMEOUT_SECONDS)
        kwargs: dict[str, Any] = {
            "model": self._model,
            "messages": [{"role": "system", "content": system}, *to_openai(messages)],
        }
        if tools:
            kwargs["tools"] = [
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
        return from_openai(client.chat.completions.create(**kwargs))


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


def from_openai(completion: Any) -> AgentResponse:
    blocks: list[Block] = []
    choices = getattr(completion, "choices", None) or []
    if not choices:
        return AgentResponse(blocks, "end_turn")
    message = choices[0].message
    if getattr(message, "content", None):
        blocks.append({"type": "text", "text": message.content})
    for call in getattr(message, "tool_calls", None) or []:
        blocks.append(
            {
                "type": "tool_use",
                "id": call.id,
                "name": call.function.name,
                "input": parse_arguments(call.function.arguments),
            }
        )
    tool_use = any(b["type"] == "tool_use" for b in blocks)
    finish = str(getattr(choices[0], "finish_reason", "stop"))
    if not tool_use and finish not in {"stop", "None"}:
        blocks.append({"type": "text", "text": f"[The model stopped early: {finish}.]"})
    return AgentResponse(blocks, "tool_use" if tool_use else "end_turn")
