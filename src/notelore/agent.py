"""The tool-use loop: the model decides *what* to do, the tools decide *how*."""

from __future__ import annotations

import datetime
from dataclasses import dataclass, field

from notelore.providers import Block, LLMProvider, Message
from notelore.tools import Toolbox

_PROMPT = """You are Notelore, a note-taking assistant. The user talks; you keep tidy notes \
in Markdown files through the tools, and later answer questions from those notes.

Rules:
- Answer in the language the user writes in, and write note content in that language. \
Pass lang="tr" to create_note when the user writes Turkish.
- Every fact comes from a tool result. Never invent a note, a decision, a date or a todo.
- Notes are projects or topics. Call list_notes before creating one; when it is unclear \
which project or topic the user means, ask instead of guessing.
- "What did we decide about X?" is answered with get_decision, never from free text. \
Use decision_history only when the user asks how a decision changed.
- Note entries are one clean, self-contained sentence each; no "as discussed above".
- Decisions have a short lowercase topic key (database, hosting, auth). Record the \
reason when the user gave one.
- archive only after the user confirmed in this conversation which entries to archive.
- Keep replies short. Say what you saved or found; do not narrate tool calls.

Today is {today}."""

MAX_TURNS = 20
_KEPT = {"text", "tool_use"}  # the only block types the API accepts back as history


def system_prompt(today: datetime.date | None = None) -> str:
    return _PROMPT.format(today=(today or datetime.date.today()).isoformat())


@dataclass
class Agent:
    provider: LLMProvider
    toolbox: Toolbox
    today: datetime.date | None = None
    max_turns: int = MAX_TURNS
    messages: list[Message] = field(default_factory=list)

    def ask(self, text: str) -> str:
        """One user message in, the final text answer out; tool calls run in between."""
        self.messages.append({"role": "user", "content": text})
        for _ in range(self.max_turns):
            response = self.provider.turn(
                system_prompt(self.today), self.messages, self.toolbox.tools
            )
            calling = response.stop_reason == "tool_use"
            # A tool_use outside a tool_use stop is half-built (e.g. cut by max_tokens):
            # never run it, and never keep it, since history needs a result for every call.
            kept = _KEPT if calling else {"text"}
            blocks = [b for b in response.content if b.get("type") in kept]
            if not blocks:
                return self._close("")
            self.messages.append({"role": "assistant", "content": blocks})
            uses = [b for b in blocks if b["type"] == "tool_use"]
            if not uses:
                return "\n".join(b["text"] for b in blocks if b["type"] == "text")
            self.messages.append({"role": "user", "content": [self._run(u) for u in uses]})
        return self._close(
            "I stopped after too many tool calls in a row. Please rephrase the request."
        )

    def _close(self, answer: str) -> str:
        """End the turn with an assistant message so user and assistant keep alternating."""
        self.messages.append(
            {"role": "assistant", "content": [{"type": "text", "text": answer or "(no answer)"}]}
        )
        return answer

    def _run(self, use: Block) -> Block:
        args = use.get("input") or {}
        if not isinstance(args, dict):
            result = "Error: the tool arguments must be a JSON object."
        elif "__raw" in args:
            result = f"Error: the tool arguments were not valid JSON: {args['__raw']}"
        else:
            result = self.toolbox.call(use["name"], args)
        return {"type": "tool_result", "tool_use_id": use["id"], "content": result}
