"""FlameBot desktop app entrypoint.

Kept as a tiny wrapper so PyInstaller has a stable target while the main UI code
lives in app/text5.py.
"""

from __future__ import annotations

import sys
from pathlib import Path


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))

    from app.text5 import main as _app_main  # noqa: WPS433

    _app_main()


if __name__ == "__main__":
    main()
