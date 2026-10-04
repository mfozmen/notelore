"""LLM providers: Anthropic, OpenAI, Gemini, Ollama behind one ``turn()`` interface."""

from __future__ import annotations

from notelore.providers.base import (
    SPECS,
    AgentResponse,
    Block,
    LLMProvider,
    Message,
    ProviderSpec,
    Tool,
    find,
)


def create_provider(
    spec: ProviderSpec, api_key: str | None, model: str | None = None
) -> LLMProvider:
    """The runtime implementation for ``spec``."""
    chosen = model or spec.default_model
    if spec.name == "anthropic":
        from notelore.providers.anthropic import AnthropicProvider

        return AnthropicProvider(api_key or "", chosen)
    if spec.name == "openai":
        from notelore.providers.openai import OpenAIProvider

        return OpenAIProvider(api_key or "", chosen)
    if spec.name == "gemini":
        from notelore.providers.gemini import GeminiProvider

        return GeminiProvider(api_key or "", chosen)
    from notelore.providers.ollama import OllamaProvider

    return OllamaProvider(chosen)


__all__ = [
    "SPECS",
    "AgentResponse",
    "Block",
    "LLMProvider",
    "Message",
    "ProviderSpec",
    "Tool",
    "create_provider",
    "find",
]
