#!/usr/bin/env python3

import json
import os
import shutil
import sys


def respond(ok, action, message="", path=""):
    print(json.dumps({
        "ok": ok,
        "action": action,
        "message": message,
        "path": path,
    }, ensure_ascii=False))


action = sys.argv[1] if len(sys.argv) > 1 else ""

try:
    if action == "mkdir":
        parent = os.path.realpath(sys.argv[2])
        name = sys.argv[3].strip()
        if not name or name in (".", "..") or "/" in name or "\0" in name:
            raise ValueError("Ungültiger Ordnername")

        destination = os.path.join(parent, name)
        os.mkdir(destination)
        respond(True, action, "Ordner erstellt", destination)

    elif action == "move":
        source = os.path.abspath(os.path.expanduser(sys.argv[2]))
        destination_dir = os.path.realpath(sys.argv[3])
        if source == destination_dir:
            raise ValueError("Ein Ordner kann nicht in sich selbst verschoben werden")

        destination = os.path.join(destination_dir, os.path.basename(source))
        if os.path.exists(destination):
            raise FileExistsError("Am Ziel existiert bereits ein Element mit diesem Namen")
        if (
            os.path.isdir(source)
            and not os.path.islink(source)
            and os.path.commonpath((os.path.realpath(source), os.path.realpath(destination)))
                == os.path.realpath(source)
        ):
            raise ValueError("Ein Ordner kann nicht in einen Unterordner von sich verschoben werden")

        shutil.move(source, destination)
        respond(True, action, "Element verschoben", destination)

    else:
        raise ValueError("Unbekannte Dateiaktion")

except (OSError, ValueError) as error:
    respond(False, action, str(error))
