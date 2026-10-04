"""Provider catalogue and the one interface the agent loop talks to.

Ported from littlepress-ai (same author, MIT) and trimmed: no plain ``chat()``
and no image blocks, the agent only needs ``turn()``. Messages and content
blocks use Anthropic's wire shape everywhere; the other providers translate at
their boundary so the agent never learns a second format.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Protocol

# A content block: {"type": "text", ...}, {"type": "tool_use", ...} or {"type": "tool_result", ...}.
Block = dict[str, Any]
# A message: {"role": "user" | "assistant", "content": str | list[Block]}.
Message = dict[str, Any]


@dataclass(frozen=True)
class ProviderSpec:
    name: str
    display_name: str
    requires_api_key: bool
    default_model: str
    key_url: str | None = None
    key_steps: tuple[str, ...] = ()


SPECS: tuple[ProviderSpec, ...] = (
    ProviderSpec(
        "anthropic",
        "Claude (Anthropic)",
        requires_api_key=True,
        default_model="claude-sonnet-5-5",
        key_url="https://console.anthropic.com/settings/keys",
        key_steps=(
            "Sign in to the Anthropic Console (a free account is enough).",
            "Click Create Key, give it a name such as notelore, and copy it.",
            "Paste the key below (it starts with sk-ant-).",
        ),
    ),
    ProviderSpec(
        "openai",
        "GPT (OpenAI)",
        requires_api_key=True,
        default_model="gpt-4o-mini",
        key_url="https://platform.openai.com/api-keys",
        key_steps=(
            "Sign in to the OpenAI Platform.",
            "Click Create new secret key, give it a name, and copy it.",
            "Paste the key below (it starts with sk-).",
        ),
    ),
    ProviderSpec(
        "gemini",
        "Gemini (Google)",
        requires_api_key=True,
        default_model="gemini-2.5-flash",
        key_url="https://aistudio.google.com/apikey",
        key_steps=(
            "Sign in to Google AI Studio.",
            "Click Create API key and copy it.",
            "Paste the key below.",
        ),
    ),
    ProviderSpec(
        "ollama",
        "Ollama (local)",
        requires_api_key=False,
        default_model="llama3.2",
    ),
)


def find(name: str) -> ProviderSpec:
    for spec in SPECS:
        if spec.name == name:
            return spec
    raise KeyError(f"unknown provider {name!r}; known: {[s.name for s in SPECS]}")


@dataclass(frozen=True)
class Tool:
    name: str
    description: str
    input_schema: dict[str, Any]  # JSON Schema: type, properties, required, enum, items


@dataclass(frozen=True)
class AgentResponse:
    content: list[Block]
    stop_reason: str  # "end_turn" | "tool_use"


class LLMProvider(Protocol):
    def turn(self, system: str, messages: list[Message], tools: list[Tool]) -> AgentResponse:
        """One agent step: the model's content blocks for the conversation so far."""
        ...


def tool_use_names(messages: list[Message]) -> dict[str, str]:
    """``tool_use`` id -> tool name over the conversation.

    A ``tool_result`` carries only the id; Gemini and Ollama correlate by
    name, so their translators look it up here.
    """
    names: dict[str, str] = {}
    for message in messages:
        content = message.get("content")
        if message.get("role") == "assistant" and isinstance(content, list):
            for block in content:
                if block.get("type") == "tool_use" and block.get("id"):
                    names[str(block["id"])] = str(block.get("name", ""))
    return names


def split_blocks(content: str | list[Block]) -> tuple[list[str], list[Block], list[Block]]:
    """(texts, tool_use blocks, tool_result blocks) of a message's content."""
    if isinstance(content, str):
        return [content], [], []
    texts = [str(b.get("text", "")) for b in content if b.get("type") == "text"]
    uses = [b for b in content if b.get("type") == "tool_use"]
    results = [b for b in content if b.get("type") == "tool_result"]
    return texts, uses, results


def parse_arguments(raw: object) -> dict[str, Any]:
    """Tool arguments as a dict: JSON text is parsed, a dict copied, anything odd kept raw."""
    import json

    if isinstance(raw, dict):
        return dict(raw)
    if not raw:
        return {}
    try:
        parsed = json.loads(str(raw))
    except ValueError:
        return {"__raw": str(raw)}
    return parsed if isinstance(parsed, dict) else {"__raw": str(raw)}
