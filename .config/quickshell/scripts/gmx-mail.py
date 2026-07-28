#!/usr/bin/env python3

"""Privacy-preserving GMX unread counter for Quickshell.

The helper intentionally uses IMAP SEARCH only. It never requests headers,
sender addresses, subjects, previews, or message bodies.
"""

from __future__ import annotations

import imaplib
import json
import os
from pathlib import Path
import ssl
import stat
import sys


CREDENTIALS_PATH = (
    Path.home() / ".local" / "state" / "quickshell-gmx" / "credentials"
)
IMAP_HOST = "imap.gmx.net"
IMAP_PORT = 993


def emit(**payload: object) -> None:
    print(json.dumps(payload, ensure_ascii=False))


def read_credentials() -> tuple[str, str]:
    file_stat = CREDENTIALS_PATH.stat()
    if stat.S_IMODE(file_stat.st_mode) & 0o077:
        raise PermissionError("credentials file is not private")

    values: dict[str, str] = {}
    with CREDENTIALS_PATH.open(encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.rstrip("\r\n")
            if not line or line.lstrip().startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value

    email = values.get("GMX_EMAIL", "").strip()
    password = values.get("GMX_PASSWORD", "")
    if "@" not in email or not password:
        raise ValueError("credentials incomplete")
    return email, password


def unread_count(email: str, password: str) -> int:
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_2

    client = imaplib.IMAP4_SSL(
        IMAP_HOST,
        IMAP_PORT,
        ssl_context=context,
        timeout=10,
    )
    try:
        client.login(email, password)
        status, _ = client.select("INBOX", readonly=True)
        if status != "OK":
            raise imaplib.IMAP4.error("inbox unavailable")

        # SEARCH returns sequence IDs only. No private mail metadata is fetched.
        status, result = client.search(None, "UNSEEN")
        if status != "OK":
            raise imaplib.IMAP4.error("search failed")
        return len(result[0].split()) if result and result[0] else 0
    finally:
        try:
            client.logout()
        except (imaplib.IMAP4.error, OSError):
            pass


def mark_all_read(email: str, password: str) -> int:
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_2

    client = imaplib.IMAP4_SSL(
        IMAP_HOST,
        IMAP_PORT,
        ssl_context=context,
        timeout=10,
    )
    try:
        client.login(email, password)
        status, _ = client.select("INBOX", readonly=False)
        if status != "OK":
            raise imaplib.IMAP4.error("inbox unavailable")

        status, result = client.uid("search", None, "UNSEEN")
        if status != "OK":
            raise imaplib.IMAP4.error("search failed")
        message_ids = result[0].split() if result and result[0] else []
        if not message_ids:
            return 0

        status, _ = client.uid(
            "store",
            b",".join(message_ids),
            "+FLAGS.SILENT",
            r"(\Seen)",
        )
        if status != "OK":
            raise imaplib.IMAP4.error("store failed")
        return len(message_ids)
    finally:
        try:
            client.logout()
        except (imaplib.IMAP4.error, OSError):
            pass


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if not CREDENTIALS_PATH.exists():
        emit(
            ok=False,
            configured=False,
            state="missing_credentials",
            message="GMX-ZUGANG FEHLT",
        )
        return

    try:
        email, password = read_credentials()
    except PermissionError:
        emit(
            ok=False,
            configured=False,
            state="insecure_credentials",
            message="GMX-DATEI IST NICHT PRIVAT",
        )
        return
    except (OSError, ValueError):
        emit(
            ok=False,
            configured=False,
            state="incomplete_credentials",
            message="GMX-ZUGANG UNVOLLSTÄNDIG",
        )
        return

    try:
        if command == "mark-all-read":
            changed = mark_all_read(email, password)
            emit(
                ok=True,
                configured=True,
                state="ready",
                unread=0,
                hasUnread=False,
                changed=changed,
                message="ALLE E-MAILS GELESEN",
            )
            return

        count = unread_count(email, password)
        emit(
            ok=True,
            configured=True,
            state="ready",
            unread=count,
            hasUnread=count > 0,
            message="BEREIT",
        )
    except imaplib.IMAP4.error:
        emit(
            ok=False,
            configured=True,
            state="auth_failed",
            message="GMX-ANMELDUNG FEHLGESCHLAGEN",
        )
    except (OSError, ssl.SSLError):
        emit(
            ok=False,
            configured=True,
            state="offline",
            message="GMX IST NICHT ERREICHBAR",
        )


if __name__ == "__main__":
    main()
