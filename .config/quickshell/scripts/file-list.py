#!/usr/bin/env python3

import json
import os
import sys
from datetime import datetime


def human_size(size):
    units = ("B", "KB", "MB", "GB", "TB")
    value = float(size)
    for unit in units:
        if value < 1024 or unit == units[-1]:
            return f"{value:.0f} {unit}" if unit == "B" else f"{value:.1f} {unit}"
        value /= 1024


requested = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~")
path = os.path.realpath(os.path.expanduser(requested))
result = {"path": path, "parent": os.path.dirname(path), "entries": [], "error": ""}

try:
    with os.scandir(path) as directory:
        items = []
        for entry in directory:
            try:
                stat = entry.stat(follow_symlinks=False)
                is_dir = entry.is_dir(follow_symlinks=True)
                items.append({
                    "name": entry.name,
                    "path": entry.path,
                    "directory": is_dir,
                    "hidden": entry.name.startswith("."),
                    "size": "" if is_dir else human_size(stat.st_size),
                    "modified": datetime.fromtimestamp(stat.st_mtime).strftime("%d.%m.%Y"),
                })
            except OSError:
                continue

        result["entries"] = sorted(
            items,
            key=lambda item: (not item["directory"], item["name"].casefold()),
        )
except OSError as error:
    result["error"] = str(error)

print(json.dumps(result, ensure_ascii=False))
