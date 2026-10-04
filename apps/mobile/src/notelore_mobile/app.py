"""The Notelore app shell. For the spike (#50) it shows the core diagnostics."""

from __future__ import annotations

import os

import toga
from toga.style import Pack

from notelore_mobile import diagnostics


class Notelore(toga.App):
    def startup(self) -> None:
        # Every path comes from notelore.paths; on a phone the root is the app's own storage.
        os.environ["NOTELORE_HOME"] = str(self.paths.data)
        box = toga.Box(style=Pack(direction="column", margin=12))
        box.add(toga.Label("Notelore core on this device", style=Pack(font_weight="bold")))
        for check in diagnostics.run():
            box.add(toga.Label(f"{'OK' if check.ok else '--'}  {check.name}: {check.detail}"))
        window = toga.MainWindow(title=self.formal_name)
        window.content = box
        self.main_window = window
        window.show()


def main() -> Notelore:
    return Notelore("Notelore", "io.github.mfozmen.notelore")
