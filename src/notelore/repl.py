"""The read loop: pick a provider once, then chat; slash commands for the rest."""

from __future__ import annotations

import contextlib
import json
import sys
import webbrowser
from collections.abc import Callable
from pathlib import Path
from typing import Any

from notelore import paths, secrets
from notelore.agent import Agent
from notelore.providers import SPECS, LLMProvider, ProviderSpec, create_provider, find
from notelore.providers.validator import KeyValidationError, TransientValidationError, validate_key
from notelore.store.index import Index
from notelore.tools import Toolbox

COMMANDS = {
    "/model": "pick a provider and model (enter a new key if needed)",
    "/logout": "forget the saved key of the active provider and pick again",
    "/help": "show this list",
    "/exit": "quit",
}

Ask = Callable[..., str]  # ask(prompt, secret=False) -> str; raises EOFError on Ctrl-D
Say = Callable[[str], None]


def load_config(path: Path) -> dict[str, Any] | None:
    try:
        loaded = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return loaded if isinstance(loaded, dict) else None


def save_config(path: Path, config: dict[str, Any] | None) -> None:
    if config is None:
        path.unlink(missing_ok=True)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(config), encoding="utf-8")


class Repl:
    def __init__(self, ask: Ask, say: Say, toolbox: Toolbox, config_path: Path) -> None:
        self.ask, self.say, self.toolbox, self.config_path = ask, say, toolbox, config_path
        self.provider: LLMProvider | None = None
        self.spec: ProviderSpec | None = None
        self.agent: Agent | None = None

    # ------------------------------------------------------------ provider setup

    def resume(self) -> bool:
        """Use the saved provider and key without asking; False when there is none."""
        config = load_config(self.config_path)
        if config is None:
            return False
        try:
            spec = find(str(config.get("provider")))
        except KeyError:
            return False  # a hand-edited or outdated config: just ask again
        key = (secrets.load_key(spec.name) or "") if spec.requires_api_key else ""
        if spec.requires_api_key and not key:
            return False
        self._use(spec, key, config.get("model"))
        return True

    def pick(self) -> bool:
        """The provider picker; False when the user abandons it (Ctrl-D)."""
        try:
            while True:
                spec = self._pick_spec()
                key = self._get_key(spec)
                if key is None:
                    continue  # the daemon is down or the user wants another provider
                model = self.ask(f"Model [{spec.default_model}]: ").strip() or spec.default_model
                self._use(spec, key, model)
                return True
        except EOFError:
            self.say("No provider selected.")
            return False

    def _pick_spec(self) -> ProviderSpec:
        self.say("Pick a model provider:")
        for number, spec in enumerate(SPECS, 1):
            self.say(f"  {number}. {spec.display_name}")
        while True:
            answer = self.ask("> ").strip()
            if answer.isdigit() and 1 <= int(answer) <= len(SPECS):
                return SPECS[int(answer) - 1]
            self.say(f"Pick a number between 1 and {len(SPECS)}.")

    def _get_key(self, spec: ProviderSpec) -> str | None:
        """A validated key for ``spec`` ("" for key-less providers), or None to re-pick."""
        if not spec.requires_api_key:
            try:
                validate_key(spec, "")
            except TransientValidationError as exc:
                self.say(str(exc))
                return None
            return ""
        self.say(f"{spec.display_name} needs an API key:")
        for step in spec.key_steps:
            self.say(f"  - {step}")
        self.say(f"  {spec.key_url}")
        if spec.key_url:
            with contextlib.suppress(Exception):
                webbrowser.open(spec.key_url)
        while True:
            key = self.ask("API key: ", True).strip()
            if not key:
                continue
            try:
                validate_key(spec, key)
            except (KeyValidationError, TransientValidationError) as exc:
                self.say(str(exc))
                continue
            secrets.save_key(spec.name, key)
            return key

    def _use(self, spec: ProviderSpec, key: str, model: str | None) -> None:
        self.provider = create_provider(spec, key, model)
        self.agent = Agent(self.provider, self.toolbox)
        self.spec = spec
        save_config(self.config_path, {"provider": spec.name, "model": model or spec.default_model})

    # ------------------------------------------------------------ loop

    def loop(self) -> int:
        if not self.resume() and not self.pick():
            return 1
        self.say("Notelore is ready. Type /help for commands.")
        while True:
            try:
                line = self.ask("notelore> ").strip()
            except EOFError:
                self.say("Bye.")
                return 0
            if not line:
                continue
            if line.startswith("/"):
                keep_going = self.command(line)
                if keep_going is None:
                    return 1
                if not keep_going:
                    return 0
                continue
            self.answer(line)

    def command(self, line: str) -> bool | None:
        """True to keep going, False to exit, None when no provider is left."""
        if line == "/exit":
            self.say("Bye.")
            return False
        if line == "/help":
            for name, purpose in COMMANDS.items():
                self.say(f"  {name:8} {purpose}")
            return True
        if line == "/logout":
            assert self.spec is not None  # loop() only runs after a provider was picked
            secrets.delete_key(self.spec.name)
            save_config(self.config_path, None)
            return self.pick() or None
        if line == "/model":
            return self.pick() or None
        self.say(f"Unknown command {line!r}. Type /help.")
        return True

    def answer(self, line: str) -> None:
        assert self.agent is not None  # loop() only runs with a provider picked
        try:
            self.say(self.agent.ask(line))
        except Exception as exc:
            self.say(f"Error: {exc}")


# ---------------------------------------------------------------- wiring


def _has_console() -> bool:
    return sys.stdin.isatty() and sys.stdout.isatty()


def _make_ask() -> Ask:
    """prompt_toolkit on a real console; plain ``input()`` otherwise.

    prompt_toolkit needs a Windows console and raises in Git Bash's mintty or on
    piped input. The fallback loses completion and hidden key entry, not the app.
    """
    import prompt_toolkit
    from prompt_toolkit.completion import WordCompleter

    session: prompt_toolkit.PromptSession[str] | None = None
    if _has_console():
        with contextlib.suppress(Exception):
            session = prompt_toolkit.PromptSession(
                completer=WordCompleter(list(COMMANDS), sentence=True)
            )

    def ask(prompt: str, secret: bool = False) -> str:
        try:
            if session is not None:
                return session.prompt(prompt, is_password=secret)
            if secret:
                prompt = prompt.replace(": ", " (visible in this terminal): ")
            return input(prompt)
        except KeyboardInterrupt:
            return ""

    return ask


def run() -> int:
    from rich.console import Console

    notes_dir, state_dir = paths.notes_dir(), paths.state_dir()
    notes_dir.mkdir(parents=True, exist_ok=True)
    toolbox = Toolbox(notes_dir, Index(state_dir / "index.sqlite", notes_dir))
    ask = _make_ask()
    console = Console()

    def say(text: str) -> None:
        console.print(text, markup=False, highlight=False)

    try:
        return Repl(ask, say, toolbox, state_dir / "config.json").loop()
    finally:
        toolbox.index.close()
