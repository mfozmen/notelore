"""Claude via the ``anthropic`` SDK. Native content-block format: no translation."""

from __future__ import annotations

from typing import Any

from notelore.providers.base import AgentResponse, Block, Message, Tool

MAX_TOKENS = 4096
TIMEOUT_SECONDS = 60.0  # the SDK default (~10 min) would freeze the REPL on a bad network


class AnthropicProvider:
    def __init__(self, api_key: str, model: str) -> None:
        self._api_key, self._model = api_key, model

    def turn(self, system: str, messages: list[Message], tools: list[Tool]) -> AgentResponse:
        import anthropic  # lazy: keeps startup fast for users of other providers

        client = anthropic.Anthropic(api_key=self._api_key, timeout=TIMEOUT_SECONDS)
        kwargs: dict[str, Any] = {
            "model": self._model,
            "max_tokens": MAX_TOKENS,
            "system": system,
            "messages": messages,
        }
        if tools:
            kwargs["tools"] = [
                {"name": t.name, "description": t.description, "input_schema": t.input_schema}
                for t in tools
            ]
        response = client.messages.create(**kwargs)
        blocks = [block_to_dict(b) for b in response.content]
        if response.stop_reason not in ("end_turn", "tool_use", "stop_sequence"):
            blocks.append(
                {"type": "text", "text": f"[The model stopped early: {response.stop_reason}.]"}
            )
        stop = "tool_use" if response.stop_reason == "tool_use" else "end_turn"
        return AgentResponse(blocks, stop)


def block_to_dict(block: Any) -> Block:
    """A response block as a plain dict, holding only the fields the API accepts back."""
    kind = getattr(block, "type", None)
    if kind == "text":
        return {"type": "text", "text": block.text}
    if kind == "tool_use":
        return {"type": "tool_use", "id": block.id, "name": block.name, "input": block.input}
    return {"type": kind}
