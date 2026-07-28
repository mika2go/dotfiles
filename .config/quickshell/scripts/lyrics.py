#!/usr/bin/env python3

import hashlib
import json
import re
import sys
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


API_URL = "https://lrclib.net/api/search"
CACHE_DIR = Path("/home/mika/.cache/quickshell/lyrics")
USER_AGENT = "MikaQuickshell/1.0 (LRCLIB lyrics display)"
MISSING_CACHE_SECONDS = 24 * 60 * 60
CACHE_VERSION = 2


def normalized(value: str) -> str:
    decomposed = unicodedata.normalize("NFKD", value.casefold())
    ascii_value = "".join(
        character
        for character in decomposed
        if not unicodedata.combining(character)
    )
    return re.sub(r"[^a-z0-9]+", " ", ascii_value).strip()


def simplified_title(value: str) -> str:
    simplified = re.sub(
        r"\s*[\(\[].*?(?:feat|ft|with|remaster|version|edit).*?[\)\]]",
        "",
        value,
        flags=re.IGNORECASE,
    )
    return simplified.strip() or value.strip()


def token_similarity(left: str, right: str) -> float:
    left_tokens = set(normalized(left).split())
    right_tokens = set(normalized(right).split())
    if not left_tokens or not right_tokens:
        return 0.0
    return len(left_tokens & right_tokens) / len(left_tokens | right_tokens)


def candidate_score(
    candidate: dict[str, object],
    title: str,
    artist: str,
    album: str,
    duration: float,
) -> float:
    candidate_title = str(candidate.get("trackName") or "")
    candidate_artist = str(candidate.get("artistName") or "")
    title_similarity = token_similarity(title, candidate_title)
    artist_similarity = token_similarity(artist, candidate_artist)

    if title_similarity < 0.5 or artist_similarity < 0.2:
        return -1

    score = title_similarity * 12 + artist_similarity * 8
    if normalized(title) == normalized(candidate_title):
        score += 6
    if normalized(artist) == normalized(candidate_artist):
        score += 4
    if album and normalized(album) == normalized(
        str(candidate.get("albumName") or "")
    ):
        score += 2

    candidate_duration = float(candidate.get("duration") or 0)
    if duration > 0 and candidate_duration > 0:
        difference = abs(duration - candidate_duration)
        if difference <= 3:
            score += 6
        elif difference <= 8:
            score += 3
        elif difference > 25:
            score -= 4
    return score


def search(title: str, artist: str) -> list[dict[str, object]]:
    query = urllib.parse.urlencode(
        {"track_name": title, "artist_name": artist}
    )
    request = urllib.request.Request(
        f"{API_URL}?{query}",
        headers={"User-Agent": USER_AGENT, "Accept": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=8) as response:
        payload = json.load(response)
    return payload if isinstance(payload, list) else []


def synced_lines(value: str) -> list[dict[str, object]]:
    lines: list[dict[str, object]] = []
    pattern = re.compile(r"^\[(\d+):(\d+(?:\.\d+)?)\]\s?(.*)$")
    offset_match = re.search(r"^\[offset:([+-]?\d+)\]$", value, re.MULTILINE)
    offset = int(offset_match.group(1)) / 1000 if offset_match else 0.0
    for raw_line in value.splitlines():
        match = pattern.match(raw_line.strip())
        if not match:
            continue
        timestamp = max(
            0.0,
            int(match.group(1)) * 60 + float(match.group(2)) + offset,
        )
        lines.append({"time": round(timestamp, 2), "text": match.group(3).strip()})
    lines.sort(key=lambda entry: float(entry["time"]))
    return lines


def plain_lines(value: str, duration: float) -> list[dict[str, object]]:
    entries: list[dict[str, object]] = []
    for raw_line in value.splitlines():
        text = raw_line.strip()
        if text:
            entries.append({"text": text, "section_breaks": 0})
        elif entries:
            entries[-1]["section_breaks"] = min(
                2, int(entries[-1]["section_breaks"]) + 1
            )

    if not entries:
        return []

    # Plain lyrics have no timestamps. Spread them across the actual track
    # instead of assigning every line a fixed three seconds: dense/fast lyrics
    # are compressed and sparse/slow lyrics naturally receive more time.
    weights: list[float] = []
    for entry in entries:
        text = str(entry["text"])
        word_count = max(1, len(re.findall(r"[\w']+", text, re.UNICODE)))
        punctuation = len(re.findall(r"[,;:!?]", text))
        section_breaks = int(entry["section_breaks"])
        weights.append(
            word_count ** 0.62
            + min(0.75, punctuation * 0.12)
            + section_breaks * 0.65
        )

    if duration <= 0:
        duration = max(10.0, len(entries) * 3.0)

    intro = min(6.0, max(1.5, duration * 0.04))
    outro = min(8.0, max(2.0, duration * 0.05))
    vocal_duration = max(1.0, duration - intro - outro)
    total_weight = sum(weights)
    elapsed = 0.0
    lines: list[dict[str, object]] = []
    for entry, weight in zip(entries, weights):
        lines.append({"time": round(intro + elapsed, 2), "text": entry["text"]})
        elapsed += vocal_duration * weight / total_weight
    return lines


def result_for(
    candidate: dict[str, object],
    duration: float,
    request_key: str,
) -> dict[str, object]:
    if bool(candidate.get("instrumental")):
        return {"key": request_key, "available": False, "lines": []}

    synced = str(candidate.get("syncedLyrics") or "")
    plain = str(candidate.get("plainLyrics") or "")
    lines = synced_lines(synced)
    is_synced = bool(lines)
    if not lines:
        track_duration = duration or float(candidate.get("duration") or 0)
        lines = plain_lines(plain, track_duration)

    return {
        "key": request_key,
        "available": bool(lines),
        "synced": is_synced,
        "lines": lines,
    }


def cache_path(title: str, artist: str, album: str, duration: float) -> Path:
    identity = "\0".join(
        [
            str(CACHE_VERSION),
            normalized(title),
            normalized(artist),
            normalized(album),
            str(round(duration)),
        ]
    )
    digest = hashlib.sha256(identity.encode("utf-8")).hexdigest()
    return CACHE_DIR / f"{digest}.json"


def load_cache(path: Path, request_key: str) -> dict[str, object] | None:
    try:
        cached = json.loads(path.read_text(encoding="utf-8"))
        if not cached.get("available"):
            age = time.time() - path.stat().st_mtime
            if age > MISSING_CACHE_SECONDS:
                return None
        cached["key"] = request_key
        return cached
    except (OSError, ValueError, TypeError):
        return None


def save_cache(path: Path, result: dict[str, object]) -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(".tmp")
    cache_value = dict(result)
    cache_value.pop("key", None)
    temporary.write_text(
        json.dumps(cache_value, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    temporary.replace(path)


def main() -> int:
    if len(sys.argv) != 6:
        print(
            json.dumps({"available": False, "lines": []}),
            end="",
        )
        return 2

    request_key, title, artist, album, raw_duration = sys.argv[1:]
    try:
        duration = max(0.0, float(raw_duration))
    except ValueError:
        duration = 0.0

    if not title.strip() or not artist.strip():
        print(
            json.dumps(
                {"key": request_key, "available": False, "lines": []},
                separators=(",", ":"),
            ),
            end="",
        )
        return 0

    path = cache_path(title, artist, album, duration)
    cached = load_cache(path, request_key)
    if cached is not None:
        print(json.dumps(cached, ensure_ascii=False, separators=(",", ":")), end="")
        return 0

    candidates: list[dict[str, object]] = []
    try:
        candidates = search(title, artist)
        shorter_title = simplified_title(title)
        if not candidates and shorter_title != title:
            candidates = search(shorter_title, artist)
    except (OSError, urllib.error.URLError, ValueError, TimeoutError):
        print(
            json.dumps(
                {"key": request_key, "available": False, "lines": []},
                separators=(",", ":"),
            ),
            end="",
        )
        return 0

    best = max(
        candidates,
        key=lambda candidate: candidate_score(
            candidate, title, artist, album, duration
        ),
        default=None,
    )
    if best is None or candidate_score(best, title, artist, album, duration) < 0:
        result: dict[str, object] = {
            "key": request_key,
            "available": False,
            "lines": [],
        }
    else:
        result = result_for(best, duration, request_key)

    save_cache(path, result)
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")), end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
