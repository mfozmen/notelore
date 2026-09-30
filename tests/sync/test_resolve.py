from __future__ import annotations

from notelore.providers import AgentResponse, Message, Tool
from notelore.sync.merge import Conflict
from notelore.sync.resolve import ModelResolver

CONFLICT = Conflict(
    base=["- 2026-09-01: meeting on Monday\n"],
    local=["- 2026-09-01: meeting on Tuesday\n"],
    remote=["- 2026-09-01: meeting on Monday at 10:00\n"],
)


class Scripted:
    def __init__(self, *answers: str | Exception) -> None:
        self.answers = list(answers)
        self.calls: list[tuple[str, list[Message], list[Tool]]] = []

    def turn(self, system: str, messages: list[Message], tools: list[Tool]) -> AgentResponse:
        self.calls.append((system, messages, tools))
        answer = self.answers.pop(0)
        if isinstance(answer, Exception):
            raise answer
        return AgentResponse([{"type": "text", "text": answer}], "end_turn")


def test_the_model_sees_all_three_versions_and_no_tools() -> None:
    provider = Scripted(
        "<merged>\n- 2026-09-01: meeting on Tuesday at 10:00\n</merged>\n"
        "<why>The laptop moved the day and the Mac added the time; both kept.</why>"
    )
    resolver = ModelResolver(provider)
    assert resolver(CONFLICT) == ["- 2026-09-01: meeting on Tuesday at 10:00\n"]
    system, messages, tools = provider.calls[0]
    assert tools == []
    prompt = messages[0]["content"]
    for line in ("meeting on Monday\n", "meeting on Tuesday\n", "Monday at 10:00\n"):
        assert line in prompt
    assert "never invent" in system.lower()
    assert resolver.explanations == [
        "The laptop moved the day and the Mac added the time; both kept."
    ]


def test_multiple_lines_and_a_missing_final_newline() -> None:
    provider = Scripted("<merged>\na\nb</merged><why>ok</why>")
    assert ModelResolver(provider)(CONFLICT) == ["a\n", "b\n"]


def test_an_empty_merge_is_allowed() -> None:
    provider = Scripted("<merged>\n</merged><why>Both sides deleted the line.</why>")
    assert ModelResolver(provider)(CONFLICT) == []


def test_an_answer_without_the_tags_leaves_the_conflict_open() -> None:
    resolver = ModelResolver(Scripted("I think Tuesday is right."))
    assert resolver(CONFLICT) is None
    assert resolver.explanations == []


def test_a_provider_failure_leaves_the_conflict_open() -> None:
    resolver = ModelResolver(Scripted(ConnectionError("offline")))
    assert resolver(CONFLICT) is None


def test_model_output_is_nfc_and_a_deletion_is_visible_in_the_report() -> None:
    import unicodedata

    nfd = unicodedata.normalize("NFD", "- 2026-09-01: toplantı Salı\n")
    assert ModelResolver(Scripted(f"<merged>\n{nfd}</merged><why>ok</why>"))(CONFLICT) == [
        unicodedata.normalize("NFC", nfd)
    ]
    resolver = ModelResolver(Scripted("<merged>\n</merged><why>Both sides dropped it.</why>"))
    resolver(CONFLICT)
    assert resolver.explanations == ["Removed the conflicting lines: Both sides dropped it."]
