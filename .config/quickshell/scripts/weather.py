#!/usr/bin/env python3

import json
from pathlib import Path
import urllib.parse
import urllib.request


CONFIG_PATH = Path.home() / ".local" / "state" / "quickshell-weather" / "config.json"

SUMMARIES = {
    0: "KLAR",
    1: "ÜBERWIEGEND KLAR",
    2: "TEILWEISE BEWÖLKT",
    3: "BEWÖLKT",
    45: "NEBEL",
    48: "NEBEL",
    51: "NIESELREGEN",
    53: "NIESELREGEN",
    55: "NIESELREGEN",
    61: "REGEN",
    63: "REGEN",
    65: "STARKER REGEN",
    71: "SCHNEE",
    73: "SCHNEE",
    75: "STARKER SCHNEE",
    77: "SCHNEE",
    80: "REGENSCHAUER",
    81: "REGENSCHAUER",
    82: "STARKER SCHAUER",
    95: "GEWITTER",
    96: "GEWITTER",
    99: "GEWITTER",
}


def emit(**payload: object) -> None:
    print(json.dumps(payload, ensure_ascii=False))


def load_config() -> tuple[str, float, float]:
    with CONFIG_PATH.open(encoding="utf-8") as handle:
        config = json.load(handle)

    label = str(config.get("label", "WEATHER")).strip() or "WEATHER"
    latitude = float(config["latitude"])
    longitude = float(config["longitude"])
    if not -90 <= latitude <= 90 or not -180 <= longitude <= 180:
        raise ValueError("coordinates out of range")
    return label, latitude, longitude


def main() -> None:
    try:
        label, latitude, longitude = load_config()
    except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError):
        emit(
            ok=False,
            location="WEATHER",
            temperature=0,
            code=0,
            isDay=True,
            summary="CONFIGURE WEATHER.JSON",
            hourly=[],
        )
        return

    params = {
        "latitude": str(latitude),
        "longitude": str(longitude),
        "current": "temperature_2m,weather_code,is_day",
        "hourly": "temperature_2m,weather_code,is_day",
        "forecast_days": "2",
        "timezone": "auto",
    }
    url = "https://api.open-meteo.com/v1/forecast?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(url, timeout=8) as response:
        data = json.load(response)

    current = data["current"]
    times = data["hourly"]["time"]
    temperatures = data["hourly"]["temperature_2m"]
    codes = data["hourly"]["weather_code"]
    daylight = data["hourly"]["is_day"]
    current_hour = current["time"][:13] + ":00"

    try:
        start = times.index(current_hour)
    except ValueError:
        start = 0

    hourly = []
    for index in range(start, min(start + 6, len(times))):
        hourly.append(
            {
                "time": times[index][11:13] + " UHR",
                "temperature": round(temperatures[index]),
                "code": int(codes[index]),
                "isDay": bool(daylight[index]),
            }
        )

    code = int(current["weather_code"])
    emit(
        ok=True,
        location=label,
        temperature=round(current["temperature_2m"]),
        code=code,
        isDay=bool(current["is_day"]),
        summary=SUMMARIES.get(code, "WECHSELHAFT"),
        hourly=hourly,
    )


if __name__ == "__main__":
    main()
