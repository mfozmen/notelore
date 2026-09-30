from __future__ import annotations

import json
from collections.abc import Iterator
from pathlib import Path
from typing import Any, ClassVar

import pytest

from notelore import repl, secrets
from notelore.providers import AgentResponse, Message, Tool
from notelore.providers.validator import KeyValidationError, TransientValidationError
from notelore.store.index import Index
from notelore.tools import Toolbox


class Console:
    """Scripted answers for ``ask`` and a transcript of everything ``say`` printed."""

    def __init__(self, *answers: str) -> None:
        self.answers = list(answers)
        self.out: list[str] = []
        self.prompts: list[tuple[str, bool]] = []

    def ask(self, prompt: str, secret: bool = False) -> str:
        self.prompts.append((prompt, secret))
        if not self.answers:
            raise EOFError
        return self.answers.pop(0)

    def say(self, text: str) -> None:
        self.out.append(text)

    @property
    def text(self) -> str:
        return "\n".join(self.out)


class EchoProvider:
    def turn(self, system: str, messages: list[Message], tools: list[Tool]) -> AgentResponse:
        last = messages[-1]["content"]
        return AgentResponse([{"type": "text", "text": f"echo: {last}"}], "end_turn")


@pytest.fixture
def box(tmp_path: Path) -> Iterator[Toolbox]:
    root = tmp_path / "notes"
    box = Toolbox(root, Index(tmp_path / "state" / "index.sqlite", root))
    yield box
    box.index.close()


@pytest.fixture
def fakes(monkeypatch: pytest.MonkeyPatch) -> dict[str, Any]:
    """No keyring, no network, no browser: everything the picker touches is recorded."""
    store: dict[str, str] = {}
    calls: dict[str, Any] = {"validate": [], "opened": [], "store": store, "outcome": []}
    monkeypatch.setattr(secrets, "load_key", store.get)
    monkeypatch.setattr(secrets, "save_key", store.__setitem__)
    monkeypatch.setattr(secrets, "delete_key", lambda name: store.pop(name, None))

    def validate(spec: Any, key: str) -> None:
        calls["validate"].append((spec.name, key))
        outcome = calls["outcome"].pop(0) if calls["outcome"] else None
        if outcome is not None:
            raise outcome

    monkeypatch.setattr(repl, "validate_key", validate)
    monkeypatch.setattr("webbrowser.open", lambda url: calls["opened"].append(url))
    monkeypatch.setattr(repl, "create_provider", lambda spec, key, model: EchoProvider())
    return calls


def make(box: Toolbox, console: Console, tmp_path: Path) -> repl.Repl:
    return repl.Repl(console.ask, console.say, box, tmp_path / "state" / "config.json")


def test_first_run_picks_a_provider_enters_a_key_and_chats(
    box: Toolbox, fakes: dict[str, Any], tmp_path: Path
) -> None:
    console = Console("1", "sk-ant-1", "", "merhaba", "/exit")
    session = make(box, console, tmp_path)
    assert session.loop() == 0
    assert "1. Claude (Anthropic)" in console.text
    assert "https://console.anthropic.com/settings/keys" in console.text
    assert fakes["opened"] == ["https://console.anthropic.com/settings/keys"]
    assert console.prompts[1] == ("API key: ", True)
    assert fakes["validate"] == [("anthropic", "sk-ant-1")]
    assert fakes["store"] == {"anthropic": "sk-ant-1"}
    assert json.loads((tmp_path / "state" / "config.json").read_text(encoding="utf-8")) == {
        "provider": "anthropic",
        "model": "claude-sonnet-5-5",
    }
    assert "echo: merhaba" in console.text
    assert "Bye." in console.text


def test_saved_config_and_key_skip_the_picker(
    box: Toolbox, fakes: dict[str, Any], tmp_path: Path
) -> None:
    fakes["store"]["openai"] = "sk-saved"
    repl.save_config(tmp_path / "state" / "config.json", {"provider": "openai", "model": "gpt-x"})
    console = Console("hi")
    assert make(box, console, tmp_path).loop() == 0  # EOF ends the loop too
    assert "Pick a model provider" not in console.text
    assert "echo: hi" in console.text
    assert fakes["validate"] == []


def test_picker_input_edge_cases(box: Toolbox, fakes: dict[str, Any], tmp_path: Path) -> None:
    fakes["outcome"] = [KeyValidationError("bad"), TransientValidationError("rate limited"), None]
    console = Console("9", "x", "1", "", "sk-bad", "sk-slow", "sk-ok", "my-model", "/exit")
    make(box, console, tmp_path).loop()
    assert console.text.count("Pick a number") == 2
    assert "bad" in console.text and "rate limited" in console.text
    assert fakes["validate"][-1] == ("anthropic", "sk-ok")
    assert repl.load_config(tmp_path / "state" / "config.json") == {
        "provider": "anthropic",
        "model": "my-model",
    }


def test_ollama_needs_no_key_but_must_be_reachable(
    box: Toolbox, fakes: dict[str, Any], tmp_path: Path
) -> None:
    fakes["outcome"] = [TransientValidationError("Ollama is not reachable"), None]
    console = Console("4", "4", "", "/exit")
    make(box, console, tmp_path).loop()
    assert "not reachable" in console.text
    assert fakes["validate"] == [("ollama", ""), ("ollama", "")]
    assert fakes["store"] == {}
    assert console.prompts[-2] == ("Model [llama3.2]: ", False)


@pytest.mark.parametrize(
    "config",
    [
        {"provider": "anthropic", "model": None},  # saved provider, but its key is gone
        {"provider": "bard", "model": None},  # a provider this version does not know
    ],
)
def test_unusable_saved_config_falls_back_to_the_picker(
    box: Toolbox, fakes: dict[str, Any], tmp_path: Path, config: dict[str, Any]
) -> None:
    repl.save_config(tmp_path / "state" / "config.json", config)
    console = Console("4", "", "/exit")
    assert make(box, console, tmp_path).loop() == 0
    assert "Pick a model provider" in console.text


def test_abandoning_the_picker_exits(box: Toolbox, fakes: dict[str, Any], tmp_path: Path) -> None:
    console = Console()
    assert make(box, console, tmp_path).loop() == 1
    assert "No provider" in console.text


def test_slash_commands(box: Toolbox, fakes: dict[str, Any], tmp_path: Path) -> None:
    fakes["store"]["gemini"] = "g-key"
    repl.save_config(tmp_path / "state" / "config.json", {"provider": "gemini", "model": None})
    console = Console("/help", "/nope", "", "/logout", "1", "sk", "", "/model", "4", "", "/exit")
    make(box, console, tmp_path).loop()
    assert "/model" in console.text and "/logout" in console.text
    assert "Unknown command" in console.text
    assert fakes["store"] == {"anthropic": "sk"}  # gemini key deleted by /logout, new one saved
    config = repl.load_config(tmp_path / "state" / "config.json")
    assert config is not None
    assert config["provider"] == "ollama"


def test_provider_errors_are_shown_not_raised(
    box: Toolbox, fakes: dict[str, Any], tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    class Broken:
        def turn(self, *args: Any) -> AgentResponse:
            raise ConnectionError("no network")

    monkeypatch.setattr(repl, "create_provider", lambda spec, key, model: Broken())
    fakes["store"]["anthropic"] = "sk"
    repl.save_config(tmp_path / "state" / "config.json", {"provider": "anthropic", "model": None})
    console = Console("hello", "/exit")
    make(box, console, tmp_path).loop()
    assert "Error: no network" in console.text


def test_logout_then_abandon(box: Toolbox, fakes: dict[str, Any], tmp_path: Path) -> None:
    fakes["store"]["anthropic"] = "sk"
    repl.save_config(tmp_path / "state" / "config.json", {"provider": "anthropic", "model": None})
    console = Console("/logout")
    assert make(box, console, tmp_path).loop() == 1
    assert fakes["store"] == {}
    assert repl.load_config(tmp_path / "state" / "config.json") is None


class FakeSession:
    """Stands in for prompt_toolkit's PromptSession, whose pipe input opens sockets on Windows."""

    lines: ClassVar[list[str]] = ["", "/exit"]
    seen: ClassVar[list[tuple[str, bool]]] = []

    def __init__(self, **kwargs: Any) -> None:
        self.completer = kwargs["completer"]

    def prompt(self, message: str, is_password: bool = False) -> str:
        FakeSession.seen.append((message, is_password))
        line = FakeSession.lines.pop(0)
        if not line:
            raise KeyboardInterrupt  # Ctrl-C at the prompt clears the line, it does not quit
        return line


def test_run_wires_the_prompt_and_the_console(
    monkeypatch: pytest.MonkeyPatch, notelore_home: Path, capsys: pytest.CaptureFixture[str]
) -> None:
    monkeypatch.setattr(repl, "_has_console", lambda: True)
    monkeypatch.setattr(FakeSession, "lines", ["", "/exit"])
    monkeypatch.setattr(FakeSession, "seen", [])
    monkeypatch.setattr("prompt_toolkit.PromptSession", FakeSession)
    monkeypatch.setattr(repl, "create_provider", lambda spec, key, model: EchoProvider())
    repl.save_config(notelore_home / "state" / "config.json", {"provider": "ollama", "model": "m"})
    assert repl.run() == 0
    out = capsys.readouterr().out
    assert "Notelore is ready" in out
    assert "Bye." in out
    assert FakeSession.seen == [("notelore> ", False), ("notelore> ", False)]
    assert (notelore_home / "notes").is_dir()


class NoConsole(Exception):
    """What prompt_toolkit raises in Git Bash (mintty) on Windows."""


def failing_session(**kwargs: Any) -> None:
    raise NoConsole("Found xterm-256color, while expecting a Windows console.")


@pytest.mark.parametrize("has_console", [False, True], ids=["piped", "mintty"])
def test_run_falls_back_to_plain_input_without_a_windows_console(
    monkeypatch: pytest.MonkeyPatch,
    notelore_home: Path,
    capsys: pytest.CaptureFixture[str],
    has_console: bool,
) -> None:
    monkeypatch.setattr(repl, "_has_console", lambda: has_console)
    monkeypatch.setattr("prompt_toolkit.PromptSession", failing_session)
    monkeypatch.setattr(repl, "create_provider", lambda spec, key, model: EchoProvider())
    monkeypatch.setattr(repl, "validate_key", lambda spec, key: None)
    monkeypatch.setattr(secrets, "save_key", lambda name, key: None)
    monkeypatch.setattr(secrets, "load_key", lambda name: None)
    monkeypatch.setattr("webbrowser.open", lambda url: None)
    answers = iter(["1", "sk-visible", "", "hello"])

    def fake_input(prompt: str) -> str:
        print(prompt, end="")
        try:
            return next(answers)
        except StopIteration:
            raise EOFError from None

    monkeypatch.setattr("builtins.input", fake_input)
    assert repl.run() == 0
    out = capsys.readouterr().out
    assert "API key (visible in this terminal): " in out
    assert "echo: hello" in out
    assert "Bye." in out


def test_has_console_reads_both_streams(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr("sys.stdin.isatty", lambda: True, raising=False)
    monkeypatch.setattr("sys.stdout.isatty", lambda: True, raising=False)
    assert repl._has_console() is True
    monkeypatch.setattr("sys.stdout.isatty", lambda: False, raising=False)
    assert repl._has_console() is False


def test_a_spec_without_a_key_page_opens_no_browser(
    box: Toolbox, fakes: dict[str, Any], tmp_path: Path
) -> None:
    from notelore.providers import ProviderSpec

    spec = ProviderSpec("anthropic", "Self-hosted", True, "m", "m")
    session = make(box, Console("sk"), tmp_path)
    assert session.spec is None
    assert session._get_key(spec) == "sk"
    assert fakes["opened"] == []
