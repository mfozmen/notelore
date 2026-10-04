"""Claude over the Messages API. Native content-block format: no translation."""

from __future__ import annotations

from typing import Any

from notelore.providers import http
from notelore.providers.base import AgentResponse, Block, Message, Tool

API = "https://api.anthropic.com/v1/messages"
MODELS = "https://api.anthropic.com/v1/models"
VERSION = "2023-06-01"
MAX_TOKENS = 4096
TIMEOUT_SECONDS = 60.0  # long enough for a reply, short enough not to freeze the chat


def headers(api_key: str) -> dict[str, str]:
    return {"x-api-key": api_key, "anthropic-version": VERSION}


class AnthropicProvider:
    def __init__(self, api_key: str, model: str) -> None:
        self._api_key, self._model = api_key, model

    def turn(self, system: str, messages: list[Message], tools: list[Tool]) -> AgentResponse:
        body: dict[str, Any] = {"model": self._model, "max_tokens": MAX_TOKENS}
        if system:
            body["system"] = system
        body["messages"] = messages
        if tools:
            body["tools"] = [
                {"name": t.name, "description": t.description, "input_schema": t.input_schema}
                for t in tools
            ]
        answer = http.request("POST", API, headers(self._api_key), body, TIMEOUT_SECONDS)
        blocks = [block_to_dict(b) for b in answer.get("content", [])]
        stop = answer.get("stop_reason")
        if stop not in ("end_turn", "tool_use", "stop_sequence"):
            blocks.append({"type": "text", "text": f"[The model stopped early: {stop}.]"})
        return AgentResponse(blocks, "tool_use" if stop == "tool_use" else "end_turn")


def block_to_dict(block: Block) -> Block:
    """Only the fields the API accepts back in history (it rejects response-only ones)."""
    kind = block.get("type")
    if kind == "text":
        return {"type": "text", "text": block["text"]}
    if kind == "tool_use":
        return {
            "type": "tool_use",
            "id": block["id"],
            "name": block["name"],
            "input": block["input"],
        }
    return {"type": kind}
