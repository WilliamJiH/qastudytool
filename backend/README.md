# Backend

Flask API that reads notes from `../notes` (txt/pdf), asks an OpenAI model to generate multiple-choice questions, and returns structured JSON.
Text files are read locally; PDF files are sent directly to OpenAI as file inputs for model-side reading.

## Setup

```bash
cd backend
python3 -m pip install -r requirements.txt
```

API key loading order:
- `backend/.env`
- `~/.env` (for example `/Users/jihaohua/.env`)

`.env` format:

```bash
OPENAI_API_KEY="sk-..."
OPENAI_MODEL="gpt-5.2"
OPENROUTER_API_KEY="your_openrouter_key"
OPENROUTER_MODEL="deepseek/deepseek-r1-0528:free"
```

Model tier routing:
- `Pro` -> uses `OPENAI_API_KEY`
- `Free` -> uses `OPENROUTER_API_KEY` (OpenRouter)

Note:
- Free mode supports uploaded text files and PDFs.
- PDF parsing in Free mode uses `PyPDF2` with a `pdfminer.six` fallback for CJK/advanced encodings.

## Run

```bash
python3 app.py
```

## API

- `GET /` -> `Hello`
- `GET /api/health` -> health check
- `POST /api/questions`
- `POST /api/questions/upload` -> generate questions from one uploaded `.txt` or `.pdf`
- `POST /api/wrong-answer` -> store one wrong answer event
- `GET /api/wrong-answers` -> list wrong-answer records from SQLite
- `GET /api/error-collections` -> list grouped source files with upload date and wrong count

`POST /api/questions/upload` supports duplicate-name handling:
- if same file name exists, returns `409` with code `file_exists`
- send form field `override=true` to replace existing record

`GET /api/wrong-answers` supports filtering:
- query param `source_file` to return only wrong answers for a specific file

Example request body:

```json
{
  "question_count": 5,
  "model": "gpt-5.2"
}
```

By default it reads files under `notes/` at project root.

## SQLite Storage

Database file:
- `backend/study_data.db`

Tables:
- `generated_questions`: questions generated from uploaded files
- `wrong_answers`: questions users answered incorrectly

## Tests

Backend API smoke test (no OpenAI call):

```bash
python3 test_app.py
```

Direct OpenAI connectivity test:

```bash
python3 test_openai_connection.py
```
