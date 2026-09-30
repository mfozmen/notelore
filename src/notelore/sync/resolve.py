"""The model as the last resort for a true same-line sync conflict.

Only conflicts that ``merge.auto_resolve`` cannot settle get here. The model sees
the last synced lines and both edited versions and answers with the merged lines
plus one sentence on what it did; the sentence is kept for the sync report. Any
answer that cannot be read, and any provider failure, leaves the conflict open:
the engine then skips the file and tries again on the next sync.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

from notelore.providers import LLMProvider
from notelore.sync.merge import Conflict

SYSTEM = """You merge two edited versions of the same lines of a Markdown note that \
were changed on two devices. Keep every fact from both versions unless one clearly \
replaces the other; when entries carry dates, the later date wins. Never invent \
facts, dates or wording that is in neither version. Keep the note's line format.

Answer with exactly two parts and nothing else:
<merged>
the merged lines
</merged>
<why>One sentence in the note's language on what you kept and why.</why>"""

_MERGED = re.compile(r"<merged>\n?(.*?)</merged>", re.DOTALL)
_WHY = re.compile(r"<why>(.*?)</why>", re.DOTALL)


def _block(title: str, lines: list[str]) -> str:
    return f"{title}:\n```\n{''.join(lines)}```"


@dataclass
class ModelResolver:
    provider: LLMProvider
    explanations: list[str] = field(default_factory=list)

    def __call__(self, conflict: Conflict) -> list[str] | None:
        prompt = "\n\n".join(
            (
                _block("Last synced version", conflict.base),
                _block("Edited on this device", conflict.local),
                _block("Edited on the other device", conflict.remote),
            )
        )
        try:
            response = self.provider.turn(SYSTEM, [{"role": "user", "content": prompt}], [])
        except Exception:
            return None
        text = "".join(b.get("text", "") for b in response.content if b.get("type") == "text")
        merged, why = _MERGED.search(text), _WHY.search(text)
        if merged is None or why is None:
            return None
        body = merged.group(1)
        lines = [f"{line}\n" for line in body.splitlines()]
        self.explanations.append(why.group(1).strip())
        return lines
