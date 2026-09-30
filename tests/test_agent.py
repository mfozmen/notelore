from __future__ import annotations

from collections.abc import Iterator
from datetime import date
from pathlib import Path

import pytest

from notelore.agent import Agent, system_prompt
from notelore.providers import AgentResponse, Block, Message, Tool
from notelore.store.index import Index
from notelore.tools import Toolbox

TODAY = date(2026, 9, 30)


class ScriptedProvider:
    """Returns the scripted responses in order and records every turn."""

    def __init__(self, *responses: AgentResponse) -> None:
        self.responses = list(responses)
        self.turns: list[tuple[str, list[Message], list[Tool]]] = []

    def turn(self, system: str, messages: list[Message], tools: list[Tool]) -> AgentResponse:
        self.turns.append((system, [dict(m) for m in messages], tools))
        return self.responses.pop(0)


def text(content: str) -> AgentResponse:
    return AgentResponse([{"type": "text", "text": content}], "end_turn")


def tool_use(name: str, tool_id: str = "t1", **args: object) -> AgentResponse:
    block: Block = {"type": "tool_use", "id": tool_id, "name": name, "input": args}
    return AgentResponse([{"type": "text", "text": "checking"}, block], "tool_use")


@pytest.fixture
def box(tmp_path: Path) -> Iterator[Toolbox]:
    root = tmp_path / "notes"
    box = Toolbox(root, Index(tmp_path / "state" / "index.sqlite", root), today=TODAY)
    yield box
    box.index.close()


def test_plain_answer_keeps_history(box: Toolbox) -> None:
    provider = ScriptedProvider(text("Merhaba!"))
    agent = Agent(provider, box, today=TODAY)
    assert agent.ask("selam") == "Merhaba!"
    system, messages, tools = provider.turns[0]
    assert "2026-09-30" in system
    assert messages == [{"role": "user", "content": "selam"}]
    assert tools == box.tools
    assert agent.messages[-1] == {
        "role": "assistant",
        "content": [{"type": "text", "text": "Merhaba!"}],
    }


def test_tool_calls_run_and_results_go_back(box: Toolbox) -> None:
    provider = ScriptedProvider(
        tool_use("create_note", kind="project", title="Mopsos"),
        tool_use("add_note_entry", "t2", slug="mopsos", text="Weekly hit rate."),
        text("Noted."),
    )
    agent = Agent(provider, box, today=TODAY)
    assert agent.ask("Mopsos için not al: haftalık isabet oranı") == "Noted."
    assert len(provider.turns) == 3
    second = provider.turns[1][1]
    assert second[-1] == {
        "role": "user",
        "content": [
            {
                "type": "tool_result",
                "tool_use_id": "t1",
                "content": '{"slug": "mopsos", "kind": "project", "path": "projects/mopsos.md"}',
            }
        ],
    }
    assert provider.turns[2][1][-1]["content"][0]["content"] == "ok"
    assert "Weekly hit rate." in (box.root / "projects" / "mopsos.md").read_text(encoding="utf-8")


def test_tool_errors_and_bad_arguments_are_reported_not_raised(box: Toolbox) -> None:
    bad = AgentResponse(
        [{"type": "tool_use", "id": "t1", "name": "read_note", "input": {"__raw": "{oops"}}],
        "tool_use",
    )
    provider = ScriptedProvider(bad, tool_use("read_note", "t2", slug="nope"), text("Sorry."))
    assert Agent(provider, box, today=TODAY).ask("read it") == "Sorry."
    first_result = provider.turns[1][1][-1]["content"][0]["content"]
    assert first_result == "Error: the tool arguments were not valid JSON: {oops"
    second_result = provider.turns[2][1][-1]["content"][0]["content"]
    assert second_result == "Error: no note with slug 'nope'."


def test_only_text_and_tool_use_blocks_enter_history(box: Toolbox) -> None:
    provider = ScriptedProvider(
        AgentResponse([{"type": "thinking"}, {"type": "text", "text": "hi"}], "end_turn")
    )
    agent = Agent(provider, box, today=TODAY)
    assert agent.ask("x") == "hi"
    assert agent.messages[-1]["content"] == [{"type": "text", "text": "hi"}]


def test_empty_answer_leaves_history_consistent(box: Toolbox) -> None:
    provider = ScriptedProvider(AgentResponse([], "end_turn"), text("now"))
    agent = Agent(provider, box, today=TODAY)
    assert agent.ask("x") == ""
    assert agent.messages == [{"role": "user", "content": "x"}]
    assert agent.ask("again") == "now"
    assert [m["role"] for m in agent.messages] == ["user", "user", "assistant"]


def test_runaway_tool_loop_is_cut_off(box: Toolbox) -> None:
    provider = ScriptedProvider(*[tool_use("list_notes", f"t{i}") for i in range(5)])
    agent = Agent(provider, box, today=TODAY, max_turns=3)
    answer = agent.ask("loop")
    assert "stopped" in answer
    assert len(provider.turns) == 3


def test_system_prompt_rules() -> None:
    prompt = system_prompt(TODAY)
    for rule in ("get_decision", "language", "ask", "archive", "2026-09-30"):
        assert rule in prompt
