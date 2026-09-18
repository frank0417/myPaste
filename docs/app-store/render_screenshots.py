#!/usr/bin/env python3
"""Render PasteNest Mac App Store artboards at 16:10."""

from __future__ import annotations

import http.server
import os
import subprocess
import threading
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent
SHOTS = ROOT / "screenshots"
PORT = 8767
NAMES = {
    1: "01-hero",
    2: "02-hotkey",
    3: "03-screenshot",
    4: "04-ocr",
    5: "05-search",
    6: "06-keep",
}
LANGS = {"zh-Hans": "zh", "zh-Hant": "zh-Hant", "en": "en"}


def serve() -> http.server.HTTPServer:
    handler = http.server.SimpleHTTPRequestHandler
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), handler)

    class Silent(handler):
        def log_message(self, *_args):  # noqa: N802
            return

    httpd.RequestHandlerClass = Silent
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    return httpd


def chrome_shot(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists():
        dest.unlink()
    user_dir = f"/tmp/chrome-mas-{os.getpid()}-{dest.stem}"
    cmd = [
        "google-chrome",
        "--headless",
        "--disable-gpu",
        "--hide-scrollbars",
        "--no-sandbox",
        "--disable-dev-shm-usage",
        f"--user-data-dir={user_dir}",
        "--remote-debugging-port=0",
        "--window-size=2560,1600",
        "--force-device-scale-factor=1",
        "--virtual-time-budget=8000",
        "--run-all-compositor-stages-before-draw",
        f"--screenshot={dest}",
        url,
    ]
    # Headless Chrome writes the PNG then may linger on DBus; stop once the file exists.
    proc = subprocess.Popen(cmd, cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(40):
        if dest.exists() and dest.stat().st_size > 10_000:
            proc.kill()
            proc.wait(timeout=5)
            return
        try:
            proc.wait(timeout=0.5)
            break
        except subprocess.TimeoutExpired:
            continue
    proc.kill()
    if not dest.exists() or dest.stat().st_size < 10_000:
        raise SystemExit(f"screenshot failed: {url} -> {dest}")


def resize(src: Path, dest: Path, size: tuple[int, int]) -> None:
    im = Image.open(src).convert("RGB")
    im = im.resize(size, Image.Resampling.LANCZOS)
    im.save(dest, "PNG", optimize=True)


def main() -> None:
    os.chdir(ROOT)
    SHOTS.mkdir(exist_ok=True)
    httpd = serve()
    try:
        for n, name in NAMES.items():
            for lang, suffix in LANGS.items():
                dest = SHOTS / f"{name}-{suffix}-2560x1600.png"
                url = f"http://127.0.0.1:{PORT}/artboard.html?n={n}&lang={lang}"
                print(f"render {name} [{lang}]")
                chrome_shot(url, dest)
                im = Image.open(dest)
                if im.size != (2560, 1600):
                    im = im.resize((2560, 1600), Image.Resampling.LANCZOS)
                    im.save(dest, "PNG", optimize=True)
                resize(dest, SHOTS / f"{name}-{suffix}-1440x900.png", (1440, 900))
                print(f"  {dest.name} {Image.open(dest).size}")
    finally:
        httpd.shutdown()


if __name__ == "__main__":
    main()
