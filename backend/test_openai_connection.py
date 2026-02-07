"""Direct OpenAI connectivity check.

Usage:
  python3 test_openai_connection.py
"""

import os
import sys
from pathlib import Path

import requests
from dotenv import load_dotenv

OPENAI_URL = 'https://api.openai.com/v1/responses'
PROJECT_ENV = Path(__file__).resolve().parent / '.env'
HOME_ENV = Path.home() / '.env'
DESKTOP_ENV = Path.home() / 'Desktop' / '.env'

project_loaded = load_dotenv(PROJECT_ENV)
home_loaded = load_dotenv(HOME_ENV)
desktop_loaded = load_dotenv(DESKTOP_ENV)


def get_openai_api_key() -> str:
    raw = os.environ.get('OPENAI_API_KEY', '')
    return raw.strip().strip('"').strip("'")


def extract_text(payload: dict) -> str:
    output_text = payload.get('output_text')
    if isinstance(output_text, str) and output_text.strip():
        return output_text.strip()

    texts = []
    for item in payload.get('output', []):
        for content in item.get('content', []):
            text = content.get('text')
            if isinstance(text, str):
                texts.append(text)
    return '\n'.join(texts).strip()


def main() -> int:
    model = os.environ.get('OPENAI_MODEL', 'gpt-5.2')
    api_key = get_openai_api_key()
    print(f'Loaded .env status: project={project_loaded}, home={home_loaded}, desktop={desktop_loaded}')
    if not api_key:
        print(f'Checked env files: {PROJECT_ENV}, {HOME_ENV}, {DESKTOP_ENV}')
        print('ERROR: OPENAI_API_KEY is not set.')
        return 1

    payload = {
        'model': model,
        'input': 'Reply with exactly OK',
    }

    try:
        response = requests.post(
            OPENAI_URL,
            headers={
                'Authorization': f'Bearer {api_key}',
                'Content-Type': 'application/json',
            },
            json=payload,
            timeout=60,
        )
    except requests.RequestException as exc:
        print(f'ERROR: Network/connectivity issue: {exc}')
        return 2

    print(f'Status: {response.status_code}')
    if response.status_code >= 400:
        print('ERROR: OpenAI request failed')
        print(response.text)
        return 3

    data = response.json()
    output_text = extract_text(data)
    print(f'Model: {data.get("model", model)}')
    print(f'Output: {output_text!r}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
