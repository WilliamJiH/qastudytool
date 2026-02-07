# QA Study Tool

A study app that generates multiple-choice questions from uploaded notes (`.txt` / `.pdf`) using LLMs.

- Backend: Flask + SQLite
- Frontend: Flutter Web (Material 3)

## Features

- Upload a source file and auto-generate quiz questions.
- Model tier switch:
  - `Pro`: OpenAI (`gpt-5.2` by default)
  - `Free`: OpenRouter DeepSeek R1 (`deepseek/deepseek-r1-0528:free` by default)
- Language-aware generation: questions follow source-file language (e.g., Chinese stays Chinese).
- Quiz flow:
  - One question at a time
  - Choice click feedback (green/red)
  - Auto-advance after 2 seconds
- Error Collection:
  - Wrong answers are stored
  - Grouped by source file (`filename - date`)
  - Delete collection
  - Redo questions from that collection
- Favourite:
  - Stores all generated questions
  - Grouped by source file (`filename - date`)
  - Delete collection
  - Redo questions from that collection
- Generate more:
  - After each 10-question batch, `More question?` appears
  - Generates +10 per click
  - Hard cap: 50 questions per source file
- Duplicate upload check:
  - Same filename returns a conflict prompt
  - User can override

## Project Structure

- `backend/` Flask API, SQLite DB, tests
- `frontend/` Flutter app
- `notes/` Optional local notes folder for `/api/questions`

## Prerequisites

- Python 3
- Flutter SDK
- OpenAI API key for Pro mode
- OpenRouter API key for Free mode

## Environment Variables

Set at least one depending on mode:

- `OPENAI_API_KEY` (Pro)
- `OPENROUTER_API_KEY` (Free)

Backend loads `.env` from these paths (first existing values are used):

- `backend/.env`
- `~/.env`
- `~/Desktop/.env`

Example `.env`:

```env
OPENAI_API_KEY=your_openai_key
OPENROUTER_API_KEY=your_openrouter_key
```

## Start Backend

From project root:

```bash
cd backend
python3 -m pip install -r requirements.txt
python3 app.py
```

Backend runs at:

- `http://localhost:8080`
- Health check: `GET /api/health`

## Start Frontend

From project root:

```bash
cd frontend
flutter pub get
flutter run -d chrome
```

The app connects to backend URL hardcoded as:

- `http://localhost:8080`

## How to Use

1. Open frontend in browser.
2. Click `Customize`.
3. Upload a `.txt` or `.pdf` file.
4. Questions are generated automatically.
5. Answer quiz questions one by one.
6. Use:
   - `Error Collection` to review wrong answers
   - `Favourite` to review all generated questions
   - `More question?` after each 10-question batch (up to 50 per file)

## Key Backend APIs

- `GET /` -> `Hello`
- `GET /api/health`
- `POST /api/questions` (generate from `notes/`)
- `POST /api/questions/upload` (upload and generate)
- `POST /api/questions/more` (generate +10 for same source, max 50)
- `POST /api/wrong-answer`
- `GET /api/wrong-answers`
- `GET /api/error-collections`
- `DELETE /api/error-collections`
- `GET /api/favorite-collections`
- `DELETE /api/favorite-collections`
- `GET /api/generated-questions`

## Tests

Run backend tests:

```bash
python3 backend/test_app.py
```

## Notes

- Free mode does not send PDFs directly to OpenRouter; PDF text is extracted first.
- Pro mode can send PDFs directly to OpenAI as `input_file`.
- SQLite database file:
  - `backend/study_data.db`
