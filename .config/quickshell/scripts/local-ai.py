#!/usr/bin/env python3

"""Small Ollama bridge for the Quickshell notification center.

The bridge keeps networking and first-run setup out of QML. Every command
prints exactly one JSON object so the shell can expose useful offline states.
"""

from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


HOST = "http://127.0.0.1:11434"
USER_PREFIX = Path.home() / ".local"
USER_OLLAMA = USER_PREFIX / "bin" / "ollama"
LOG_PATH = Path.home() / ".cache" / "quickshell" / "ollama.log"
DEFAULT_MODEL = "qwen3.5:4b"


def emit(**payload: object) -> None:
    print(json.dumps(payload, ensure_ascii=False))


def request_json(path: str, payload: object | None = None, timeout: int = 8) -> object:
    data = None
    headers: dict[str, str] = {}
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(HOST + path, data=data, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.load(response)


def ollama_binary() -> str | None:
    found = shutil.which("ollama")
    if found:
        return found
    if USER_OLLAMA.is_file() and os.access(USER_OLLAMA, os.X_OK):
        return str(USER_OLLAMA)
    return None


def server_models() -> list[str] | None:
    try:
        response = request_json("/api/tags", timeout=2)
        return [
            str(model.get("name", ""))
            for model in response.get("models", [])
            if isinstance(model, dict)
        ]
    except (OSError, ValueError, urllib.error.URLError):
        return None


def model_present(models: list[str], model: str) -> bool:
    wanted = model.split(":", 1)[0]
    return any(
        name == model or (":" not in model and name.split(":", 1)[0] == wanted)
        for name in models
    )


def start_server() -> bool:
    if server_models() is not None:
        return True
    binary = ollama_binary()
    if not binary:
        return False

    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    environment.setdefault("OLLAMA_HOST", "127.0.0.1:11434")
    environment.setdefault("OLLAMA_CONTEXT_LENGTH", "4096")
    environment.setdefault("OLLAMA_VULKAN", "1")
    library_root = USER_PREFIX / "lib" / "ollama"
    environment.setdefault("OLLAMA_LIBRARY_PATH", str(library_root))
    search_paths = [str(library_root), str(library_root / "vulkan")]
    if environment.get("LD_LIBRARY_PATH"):
        search_paths.append(environment["LD_LIBRARY_PATH"])
    environment["LD_LIBRARY_PATH"] = os.pathsep.join(search_paths)
    with LOG_PATH.open("ab") as log:
        subprocess.Popen(
            [binary, "serve"],
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=subprocess.STDOUT,
            start_new_session=True,
            env=environment,
        )

    for _ in range(40):
        if server_models() is not None:
            return True
        time.sleep(0.25)
    return False


def arch_package_urls() -> list[str]:
    output = subprocess.check_output(
        ["pacman", "-Sp", "--print-format", "%l", "ollama", "ollama-vulkan"],
        text=True,
        stderr=subprocess.STDOUT,
    )
    return [line.strip() for line in output.splitlines() if line.startswith("http")]


def install_user_ollama() -> tuple[bool, str]:
    if ollama_binary():
        return True, ""
    if not shutil.which("pacman") or not shutil.which("bsdtar"):
        return False, "Ollama fehlt. Installiere es über deinen Paketmanager."

    try:
        urls = arch_package_urls()
        if len(urls) < 2:
            return False, "Ollama-Pakete konnten nicht gefunden werden."
        USER_PREFIX.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="quickshell-ollama-") as folder:
            for index, url in enumerate(urls):
                archive = Path(folder) / f"ollama-{index}.pkg.tar.zst"
                urllib.request.urlretrieve(url, archive)
                members = subprocess.check_output(
                    ["bsdtar", "-tf", str(archive)], text=True
                ).splitlines()
                selected_paths = [
                    path
                    for path in ("usr/bin", "usr/lib")
                    if any(member.startswith(path + "/") for member in members)
                ]
                if not selected_paths:
                    continue
                subprocess.run(
                    [
                        "bsdtar",
                        "-xf",
                        str(archive),
                        "-C",
                        str(USER_PREFIX),
                        "--strip-components=1",
                        *selected_paths,
                    ],
                    check=True,
                    stdout=subprocess.DEVNULL,
                )
        return bool(ollama_binary()), ""
    except (OSError, subprocess.CalledProcessError, urllib.error.URLError) as error:
        return False, f"Lokale Installation fehlgeschlagen: {error}"


def command_status(model: str) -> None:
    binary = ollama_binary()
    if not binary:
        emit(ok=False, state="missing_runtime", message="OLLAMA FEHLT")
        return
    if not start_server():
        emit(ok=False, state="offline", message="OLLAMA IST OFFLINE")
        return
    models = server_models() or []
    ready = model_present(models, model)
    emit(
        ok=ready,
        state="ready" if ready else "missing_model",
        message="BEREIT" if ready else "MODELL FEHLT",
        model=model,
    )


def command_prepare(model: str) -> None:
    installed, error = install_user_ollama()
    if not installed:
        emit(ok=False, state="missing_runtime", message=error)
        return
    if not start_server():
        emit(ok=False, state="offline", message="Ollama konnte nicht gestartet werden.")
        return

    binary = ollama_binary()
    assert binary is not None
    try:
        process = subprocess.run(
            [binary, "pull", model],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=1800,
        )
        if process.returncode != 0:
            last_line = process.stdout.strip().splitlines()[-1:] or ["Unbekannter Fehler"]
            emit(ok=False, state="pull_failed", message=last_line[0])
            return
    except (OSError, subprocess.TimeoutExpired) as error:
        emit(ok=False, state="pull_failed", message=f"Modelldownload fehlgeschlagen: {error}")
        return
    command_status(model)


def compact_messages(messages: object) -> list[dict[str, str]]:
    if not isinstance(messages, list):
        return []
    result: list[dict[str, str]] = []
    for message in messages[-12:]:
        if not isinstance(message, dict):
            continue
        role = str(message.get("role", ""))
        content = str(message.get("content", ""))[:6000]
        if role in {"user", "assistant"} and content:
            result.append({"role": role, "content": content})
    return result


def command_chat(model: str, raw_messages: str) -> None:
    if not start_server():
        emit(ok=False, state="offline", message="Ollama ist nicht erreichbar.")
        return
    try:
        messages = compact_messages(json.loads(raw_messages))
    except (TypeError, ValueError):
        emit(ok=False, state="invalid_request", message="Die Anfrage war ungültig.")
        return
    if not messages:
        emit(ok=False, state="invalid_request", message="Die Anfrage war leer.")
        return

    payload = {
        "model": model,
        "stream": False,
        "think": False,
        "keep_alive": "10m",
        "messages": [
            {
                "role": "system",
                "content": (
                    "Du bist Nova, ein freundlicher lokaler Alltagsassistent. "
                    "Antworte standardmäßig auf Deutsch, klar, kompakt und ehrlich. "
                    "Erfinde keine aktuellen Fakten und sage offen, wenn du etwas nicht weißt."
                ),
            },
            *messages,
        ],
        "options": {"temperature": 0.6, "num_ctx": 4096},
    }
    try:
        response = request_json("/api/chat", payload, timeout=180)
        message = response.get("message", {}) if isinstance(response, dict) else {}
        content = str(message.get("content", "")).strip()
        if not content:
            raise ValueError("Leere Modellantwort")
        emit(ok=True, state="ready", message=content)
    except urllib.error.HTTPError as error:
        state = "missing_model" if error.code == 404 else "request_failed"
        emit(ok=False, state=state, message=f"Ollama antwortete mit HTTP {error.code}.")
    except (OSError, ValueError, urllib.error.URLError) as error:
        emit(ok=False, state="request_failed", message=f"Antwort fehlgeschlagen: {error}")


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    model = sys.argv[2] if len(sys.argv) > 2 else DEFAULT_MODEL
    if command == "status":
        command_status(model)
    elif command == "prepare":
        command_prepare(model)
    elif command == "chat" and len(sys.argv) > 3:
        command_chat(model, sys.argv[3])
    else:
        emit(ok=False, state="invalid_request", message="Unbekannter Befehl.")


if __name__ == "__main__":
    main()
