"""Direct OpenRouter connectivity/auth check.

Usage:
  python3 test_openrouter_connection.py
"""

import os
import sys
from pathlib import Path

import requests
from dotenv import load_dotenv

OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models"
PROJECT_ENV = Path(__file__).resolve().parent / ".env"
HOME_ENV = Path.home() / ".env"
DESKTOP_ENV = Path.home() / "Desktop" / ".env"

project_loaded = load_dotenv(PROJECT_ENV)
home_loaded = load_dotenv(HOME_ENV)
desktop_loaded = load_dotenv(DESKTOP_ENV)


def get_openrouter_api_key() -> str:
    raw = os.environ.get("OPENROUTER_API_KEY", "")
    return raw.strip().strip('"').strip("'")


def main() -> int:
    api_key = get_openrouter_api_key()
    print(f"Loaded .env status: project={project_loaded}, home={home_loaded}, desktop={desktop_loaded}")
    if not api_key:
        print(f"Checked env files: {PROJECT_ENV}, {HOME_ENV}, {DESKTOP_ENV}")
        print("ERROR: OPENROUTER_API_KEY is not set.")
        return 1

    try:
        response = requests.get(
            OPENROUTER_MODELS_URL,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            timeout=(10, 20),
        )
    except requests.RequestException as exc:
        print(f"ERROR: Network/connectivity issue: {exc}")
        return 2

    print(f"Status: {response.status_code}")
    if response.status_code >= 400:
        print("ERROR: OpenRouter request failed")
        print(response.text)
        return 3

    body = response.json()
    data = body.get("data", [])
    print(f"Models listed: {len(data)}")
    has_target = any(
        (item.get("id") == "deepseek/deepseek-r1-0528:free")
        for item in data
        if isinstance(item, dict)
    )
    print(f"Has deepseek/deepseek-r1-0528:free: {has_target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
