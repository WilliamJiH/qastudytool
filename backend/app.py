"""Backend API for generating MCQ questions from local notes files."""

import base64
import io
import json
import os
import sqlite3
import warnings
from pathlib import Path
from typing import Dict, List, Tuple

import requests
from PyPDF2 import PdfReader
from PyPDF2.errors import PdfReadWarning
from pdfminer.high_level import extract_text as pdfminer_extract_text
from flask import Flask, jsonify, request
from flask_cors import CORS
from dotenv import load_dotenv


OPENAI_URL = "https://api.openai.com/v1/responses"
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
DEFAULT_MODEL = "gpt-5.2"
DEFAULT_OPENROUTER_MODEL = "deepseek/deepseek-r1-0528:free"
DEFAULT_NOTES_DIR = Path(__file__).resolve().parent.parent / "notes"
SUPPORTED_SUFFIXES = {".txt", ".pdf"}
DB_PATH = Path(__file__).resolve().parent / "study_data.db"
MORE_QUESTIONS_BATCH = 10
MAX_QUESTIONS_PER_SOURCE = 50

# Load env vars from project .env and user home .env if present.
load_dotenv(Path(__file__).resolve().parent / ".env")
load_dotenv(Path.home() / ".env")
load_dotenv(Path.home() / "Desktop" / ".env")

app = Flask(__name__)
CORS(app)


def get_db_connection() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db() -> None:
    conn = get_db_connection()
    try:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS generated_questions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_file TEXT NOT NULL,
                model TEXT NOT NULL,
                question_json TEXT NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS wrong_answers (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                source_file TEXT,
                question TEXT NOT NULL,
                options_json TEXT NOT NULL,
                correct_index INTEGER NOT NULL,
                selected_index INTEGER NOT NULL,
                model TEXT,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS uploaded_files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_name TEXT NOT NULL UNIQUE,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS uploaded_file_sources (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                file_name TEXT NOT NULL UNIQUE,
                file_data BLOB NOT NULL,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        conn.commit()
    finally:
        conn.close()


def store_generated_questions(source_files: List[str], model: str, questions: List[Dict]) -> None:
    source_file = source_files[0] if source_files else "unknown"
    conn = get_db_connection()
    try:
        for question in questions:
            conn.execute(
                """
                INSERT INTO generated_questions (source_file, model, question_json)
                VALUES (?, ?, ?)
                """,
                (source_file, model, json.dumps(question, ensure_ascii=False)),
            )
        conn.commit()
    finally:
        conn.close()


def store_wrong_answer(
    *,
    source_file: str,
    question: str,
    options: List[str],
    correct_index: int,
    selected_index: int,
    model: str,
) -> None:
    conn = get_db_connection()
    try:
        conn.execute(
            """
            INSERT INTO wrong_answers
            (source_file, question, options_json, correct_index, selected_index, model)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (
                source_file,
                question,
                json.dumps(options),
                correct_index,
                selected_index,
                model,
            ),
        )
        conn.commit()
    finally:
        conn.close()


def list_wrong_answers(limit: int = 100) -> List[Dict]:
    conn = get_db_connection()
    try:
        rows = conn.execute(
            """
            SELECT id, source_file, question, options_json, correct_index, selected_index, model, created_at
            FROM wrong_answers
            ORDER BY id DESC
            LIMIT ?
            """,
            (limit,),
        ).fetchall()
        result: List[Dict] = []
        for row in rows:
            options = json.loads(row["options_json"]) if row["options_json"] else []
            result.append(
                {
                    "id": row["id"],
                    "source_file": row["source_file"] or "",
                    "question": row["question"],
                    "options": options,
                    "correct_index": row["correct_index"],
                    "selected_index": row["selected_index"],
                    "model": row["model"] or "",
                    "created_at": row["created_at"],
                }
            )
        return result
    finally:
        conn.close()


def list_wrong_answers_by_source(source_file: str, limit: int = 200) -> List[Dict]:
    conn = get_db_connection()
    try:
        rows = conn.execute(
            """
            SELECT id, source_file, question, options_json, correct_index, selected_index, model, created_at
            FROM wrong_answers
            WHERE source_file = ?
            ORDER BY id DESC
            LIMIT ?
            """,
            (source_file, limit),
        ).fetchall()
        result: List[Dict] = []
        for row in rows:
            options = json.loads(row["options_json"]) if row["options_json"] else []
            result.append(
                {
                    "id": row["id"],
                    "source_file": row["source_file"] or "",
                    "question": row["question"],
                    "options": options,
                    "correct_index": row["correct_index"],
                    "selected_index": row["selected_index"],
                    "model": row["model"] or "",
                    "created_at": row["created_at"],
                }
            )
        return result
    finally:
        conn.close()


def list_error_collections() -> List[Dict]:
    conn = get_db_connection()
    try:
        rows = conn.execute(
            """
            SELECT
                wa.source_file AS source_file,
                COALESCE(uf.created_at, MIN(wa.created_at)) AS date_uploaded,
                COUNT(*) AS wrong_count
            FROM wrong_answers wa
            LEFT JOIN uploaded_files uf ON uf.file_name = wa.source_file
            WHERE wa.source_file IS NOT NULL AND TRIM(wa.source_file) != ''
            GROUP BY wa.source_file
            ORDER BY date_uploaded DESC
            """
        ).fetchall()
        return [
            {
                "source_file": row["source_file"],
                "date_uploaded": row["date_uploaded"],
                "wrong_count": row["wrong_count"],
            }
            for row in rows
        ]
    finally:
        conn.close()


def delete_error_collection(source_file: str) -> int:
    conn = get_db_connection()
    try:
        cur = conn.execute(
            "DELETE FROM wrong_answers WHERE source_file = ?",
            (source_file,),
        )
        conn.commit()
        return cur.rowcount
    finally:
        conn.close()


def list_generated_collections() -> List[Dict]:
    conn = get_db_connection()
    try:
        rows = conn.execute(
            """
            SELECT
                gq.source_file AS source_file,
                COALESCE(uf.created_at, MIN(gq.created_at)) AS date_created,
                COUNT(*) AS question_count
            FROM generated_questions gq
            LEFT JOIN uploaded_files uf ON uf.file_name = gq.source_file
            WHERE gq.source_file IS NOT NULL AND TRIM(gq.source_file) != ''
            GROUP BY gq.source_file
            ORDER BY date_created DESC
            """
        ).fetchall()
        return [
            {
                "source_file": row["source_file"],
                "date_created": row["date_created"],
                "question_count": row["question_count"],
            }
            for row in rows
        ]
    finally:
        conn.close()


def list_generated_questions_by_source(source_file: str, limit: int = 500) -> List[Dict]:
    conn = get_db_connection()
    try:
        rows = conn.execute(
            """
            SELECT id, source_file, model, question_json, created_at
            FROM generated_questions
            WHERE source_file = ?
            ORDER BY id DESC
            LIMIT ?
            """,
            (source_file, limit),
        ).fetchall()
        result: List[Dict] = []
        for row in rows:
            parsed: Dict = {}
            try:
                parsed = json.loads(row["question_json"]) if row["question_json"] else {}
            except json.JSONDecodeError:
                parsed = {}
            result.append(
                {
                    "id": row["id"],
                    "source_file": row["source_file"] or "",
                    "question": parsed.get("question", ""),
                    "options": parsed.get("options", []),
                    "correct_index": parsed.get("correct_index", -1),
                    "explanation": parsed.get("explanation", ""),
                    "model": row["model"] or "",
                    "created_at": row["created_at"],
                }
            )
        return result
    finally:
        conn.close()


def count_generated_questions_by_source(source_file: str) -> int:
    conn = get_db_connection()
    try:
        row = conn.execute(
            "SELECT COUNT(*) AS cnt FROM generated_questions WHERE source_file = ?",
            (source_file,),
        ).fetchone()
        return int(row["cnt"] if row and row["cnt"] is not None else 0)
    finally:
        conn.close()


def delete_generated_collection(source_file: str) -> int:
    conn = get_db_connection()
    try:
        cur = conn.execute(
            "DELETE FROM generated_questions WHERE source_file = ?",
            (source_file,),
        )
        conn.commit()
        return cur.rowcount
    finally:
        conn.close()


def has_uploaded_file(file_name: str) -> bool:
    conn = get_db_connection()
    try:
        row = conn.execute(
            "SELECT id FROM uploaded_files WHERE file_name = ?",
            (file_name,),
        ).fetchone()
        return row is not None
    finally:
        conn.close()


def upsert_uploaded_file(file_name: str) -> None:
    conn = get_db_connection()
    try:
        conn.execute(
            """
            INSERT INTO uploaded_files (file_name)
            VALUES (?)
            ON CONFLICT(file_name) DO UPDATE SET updated_at = CURRENT_TIMESTAMP
            """,
            (file_name,),
        )
        conn.commit()
    finally:
        conn.close()


def upsert_uploaded_file_source(file_name: str, file_data: bytes) -> None:
    conn = get_db_connection()
    try:
        conn.execute(
            """
            INSERT INTO uploaded_file_sources (file_name, file_data)
            VALUES (?, ?)
            ON CONFLICT(file_name) DO UPDATE SET
                file_data = excluded.file_data,
                updated_at = CURRENT_TIMESTAMP
            """,
            (file_name, file_data),
        )
        conn.commit()
    finally:
        conn.close()


def get_uploaded_file_source(file_name: str) -> bytes:
    conn = get_db_connection()
    try:
        row = conn.execute(
            "SELECT file_data FROM uploaded_file_sources WHERE file_name = ?",
            (file_name,),
        ).fetchone()
        if row is None or row["file_data"] is None:
            raise ValueError(f"No uploaded source found for '{file_name}'.")
        return bytes(row["file_data"])
    finally:
        conn.close()


init_db()


def get_openai_api_key() -> str:
    raw = os.environ.get("OPENAI_API_KEY", "")
    return raw.strip().strip('"').strip("'")


def get_openrouter_api_key() -> str:
    raw = os.environ.get("OPENROUTER_API_KEY", "")
    return raw.strip().strip('"').strip("'")


def read_text_file(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="ignore")


def normalize_upload_filename(filename: str) -> str:
    # Keep Unicode characters (including Chinese) while preventing path traversal.
    name = Path(filename).name.strip().replace("\x00", "")
    if not name:
        raise ValueError("Invalid file name.")
    return name


def encode_pdf_for_input(path: Path) -> str:
    raw = path.read_bytes()
    return encode_pdf_bytes(raw)


def encode_pdf_bytes(raw: bytes) -> str:
    encoded = base64.b64encode(raw).decode("ascii")
    return f"data:application/pdf;base64,{encoded}"


def extract_text_from_pdf_bytes(data: bytes) -> str:
    pages: List[str] = []
    saw_advanced_encoding_warning = False

    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always", PdfReadWarning)
        reader = PdfReader(io.BytesIO(data))
        for page in reader.pages:
            page_text = page.extract_text() or ""
            if page_text.strip():
                pages.append(page_text.strip())

        for w in caught:
            msg = str(w.message)
            if "Advanced encoding /UniGB-UCS2-H not implemented yet" in msg:
                saw_advanced_encoding_warning = True
                break

    extracted = "\n".join(pages).strip()
    if extracted and not saw_advanced_encoding_warning:
        return extracted

    # Fallback extractor for CJK/complex encodings where PyPDF2 can be incomplete.
    fallback = pdfminer_extract_text(io.BytesIO(data)) or ""
    return fallback.strip() if fallback.strip() else extracted


def load_notes_content(notes_dir: Path) -> Tuple[List[Dict], List[Dict], List[str]]:
    if not notes_dir.exists() or not notes_dir.is_dir():
        raise FileNotFoundError(f"Notes directory not found: {notes_dir}")

    text_inputs: List[Dict] = []
    pdf_inputs: List[Dict] = []
    used_files: List[str] = []

    for path in sorted(notes_dir.iterdir()):
        if not path.is_file() or path.suffix.lower() not in SUPPORTED_SUFFIXES:
            continue

        if path.suffix.lower() == ".txt":
            text = read_text_file(path).strip()
            if not text:
                continue
            text_inputs.append(
                {
                    "type": "input_text",
                    "text": f"# Source: {path.name}\n{text}",
                }
            )
            used_files.append(path.name)
            continue

        if path.suffix.lower() == ".pdf":
            pdf_inputs.append(
                {
                    "type": "input_file",
                    "filename": path.name,
                    "file_data": encode_pdf_for_input(path),
                }
            )
            used_files.append(path.name)

    if not text_inputs and not pdf_inputs:
        raise ValueError("No readable .txt or .pdf files found in notes directory.")

    return text_inputs, pdf_inputs, used_files


def load_uploaded_file_content(
    filename: str,
    data: bytes,
    model_tier: str = "pro",
) -> Tuple[List[Dict], List[Dict], List[str]]:
    clean_name = normalize_upload_filename(filename)
    suffix = Path(clean_name).suffix.lower()
    if suffix not in SUPPORTED_SUFFIXES:
        raise ValueError("Only .txt or .pdf files are supported.")

    if suffix == ".txt":
        text = data.decode("utf-8", errors="ignore").strip()
        if not text:
            raise ValueError("Uploaded text file is empty.")
        return (
            [{"type": "input_text", "text": f"# Source: {clean_name}\n{text}"}],
            [],
            [clean_name],
        )

    if suffix == ".pdf":
        if str(model_tier).strip().lower() == "free":
            text = extract_text_from_pdf_bytes(data)
            if not text:
                raise ValueError("Uploaded PDF does not contain extractable text.")
            return (
                [{"type": "input_text", "text": f"# Source: {clean_name}\n{text}"}],
                [],
                [clean_name],
            )
        return (
            [],
            [{"type": "input_file", "filename": clean_name, "file_data": encode_pdf_bytes(data)}],
            [clean_name],
        )

    raise ValueError("Unsupported file type.")


def build_prompt(question_count: int, language_hint: str = "unknown") -> str:
    language_rule = (
        "- Use the same language as the source notes for question, options, and explanation.\\n"
        "- Do NOT translate to English unless the source notes are English.\\n"
    )
    if language_hint == "chinese":
        language_rule += "- Language hint: source notes are primarily Chinese, so output Chinese.\\n"
    elif language_hint == "english":
        language_rule += "- Language hint: source notes are primarily English, so output English.\\n"

    return (
        "Generate multiple-choice study questions from the provided notes. "
        f"Create exactly {question_count} questions.\\n\\n"
        "Requirements:\\n"
        "- Output ONLY valid JSON.\\n"
        "- Use this exact JSON schema:\\n"
        "{\"questions\": [{\"question\": string, \"options\": [string, string, string, string], "
        "\"correct_index\": number, \"explanation\": string}]}\\n"
        "- Every question must have exactly 4 options.\\n"
        "- correct_index must be 0, 1, 2, or 3.\\n"
        "- Exactly one option is correct.\\n"
        "- Keep explanation concise.\\n"
        f"{language_rule}"
    )


def extract_text_from_response(response_json: Dict) -> str:
    output_text = response_json.get("output_text")
    if isinstance(output_text, str) and output_text.strip():
        return output_text.strip()

    texts: List[str] = []
    for item in response_json.get("output", []):
        for content in item.get("content", []):
            text = content.get("text")
            if isinstance(text, str):
                texts.append(text)
    return "\n".join(texts).strip()


def parse_model_json(text: str) -> Dict:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.strip("`")
        if cleaned.startswith("json"):
            cleaned = cleaned[4:].strip()
    return json.loads(cleaned)


def text_from_content_items(items: List[Dict]) -> str:
    texts: List[str] = []
    for item in items:
        if item.get("type") == "input_text":
            value = item.get("text")
            if isinstance(value, str) and value.strip():
                texts.append(value.strip())
    return "\n\n".join(texts)


def detect_language_hint_from_text(text: str) -> str:
    content = text.strip()
    if not content:
        return "unknown"

    cjk_count = sum(1 for ch in content if "\u4e00" <= ch <= "\u9fff")
    latin_count = sum(1 for ch in content if ("a" <= ch.lower() <= "z"))

    if cjk_count > 0 and cjk_count >= latin_count:
        return "chinese"
    if latin_count > 0:
        return "english"
    return "unknown"


def validate_questions(data: Dict) -> List[Dict]:
    questions = data.get("questions")
    if not isinstance(questions, list) or not questions:
        raise ValueError("Model response did not include a valid questions list.")

    validated: List[Dict] = []
    for item in questions:
        question = item.get("question")
        options = item.get("options")
        correct_index = item.get("correct_index")
        explanation = item.get("explanation", "")

        if not isinstance(question, str) or not question.strip():
            continue
        if not isinstance(options, list) or len(options) != 4 or not all(isinstance(o, str) for o in options):
            continue
        if not isinstance(correct_index, int) or correct_index < 0 or correct_index > 3:
            continue
        if not isinstance(explanation, str):
            explanation = ""

        validated.append(
            {
                "question": question.strip(),
                "options": [o.strip() for o in options],
                "correct_index": correct_index,
                "explanation": explanation.strip(),
            }
        )

    if not validated:
        raise ValueError("No valid questions were produced by the model.")

    return validated


def generate_questions(
    text_inputs: List[Dict],
    pdf_inputs: List[Dict],
    question_count: int,
    model: str,
    model_tier: str = "pro",
) -> List[Dict]:
    tier = str(model_tier).strip().lower()
    if tier not in {"pro", "free"}:
        raise ValueError("model_tier must be either 'pro' or 'free'.")
    model_name = str(model).strip()
    if not model_name:
        raise ValueError("model is required.")
    notes_text = text_from_content_items(text_inputs)
    language_hint = detect_language_hint_from_text(notes_text)

    if tier == "pro":
        api_key = get_openai_api_key()
        if not api_key:
            raise RuntimeError("OPENAI_API_KEY is not set.")

        user_content: List[Dict] = [{"type": "input_text", "text": build_prompt(question_count, language_hint)}]
        user_content.extend(text_inputs)
        user_content.extend(pdf_inputs)

        payload = {
            "model": model_name,
            "input": [
                {
                    "role": "system",
                    "content": [{"type": "input_text", "text": "You are a strict JSON generator for study questions."}],
                },
                {
                    "role": "user",
                    "content": user_content,
                },
            ],
        }

        response = requests.post(
            OPENAI_URL,
            headers={
                "Authorization": f"Bearer {api_key}",
                "Content-Type": "application/json",
            },
            json=payload,
            timeout=300,
        )

        if response.status_code >= 400:
            raise RuntimeError(f"OpenAI request failed ({response.status_code}): {response.text}")

        raw_text = extract_text_from_response(response.json())
    else:
        api_key = get_openrouter_api_key()
        if not api_key:
            raise RuntimeError("OPENROUTER_API_KEY is not set.")
        if pdf_inputs:
            raise RuntimeError("Free mode currently supports text files only. Use Pro for PDF files.")

        prompt = (
            f"{build_prompt(question_count, language_hint)}\n\n"
            f"NOTES:\n{notes_text}"
        )
        payload = {
            "model": model_name,
            "messages": [
                {"role": "system", "content": "You are a strict JSON generator for study questions."},
                {"role": "user", "content": prompt},
            ],
            "temperature": 0.2,
        }
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
        response = requests.post(
            OPENROUTER_URL,
            headers=headers,
            json=payload,
            timeout=300,
        )
        if response.status_code >= 400:
            raise RuntimeError(f"OpenRouter request failed ({response.status_code}): {response.text}")
        body = response.json()
        raw_text = (
            body.get("choices", [{}])[0]
            .get("message", {})
            .get("content", "")
            .strip()
        )

    if not raw_text:
        raise RuntimeError("Model response did not include text output.")

    parsed = parse_model_json(raw_text)
    return validate_questions(parsed)


@app.route("/")
def root() -> str:
    return "Hello"


@app.route("/api/health")
def health() -> Dict:
    return jsonify({"ok": True})


@app.route("/api/questions", methods=["POST"])
def questions() -> Tuple[Dict, int]:
    body = request.get_json(silent=True) or {}
    question_count = body.get("question_count", 5)
    model_tier = body.get("model_tier", "pro")
    tier = str(model_tier).strip().lower()
    default_model = DEFAULT_MODEL if tier == "pro" else DEFAULT_OPENROUTER_MODEL
    model = body.get("model", default_model)

    try:
        question_count = int(question_count)
        if question_count < 1 or question_count > 30:
            raise ValueError("question_count must be between 1 and 30.")

        notes_dir_value = body.get("notes_dir")
        notes_dir = Path(notes_dir_value).expanduser().resolve() if notes_dir_value else DEFAULT_NOTES_DIR

        text_inputs, pdf_inputs, source_files = load_notes_content(notes_dir)
        questions_data = generate_questions(
            text_inputs,
            pdf_inputs,
            question_count,
            model,
            model_tier=model_tier,
        )
        store_generated_questions(source_files, model, questions_data)

        return (
            jsonify(
                {
                    "questions": questions_data,
                    "source_files": source_files,
                    "model": model,
                    "model_tier": model_tier,
                    "notes_dir": str(notes_dir),
                }
            ),
            200,
        )
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/questions/upload", methods=["POST"])
def questions_upload() -> Tuple[Dict, int]:
    try:
        model_tier = request.form.get("model_tier", "pro")
        default_model = DEFAULT_MODEL if str(model_tier).lower() == "pro" else DEFAULT_OPENROUTER_MODEL
        model = request.form.get("model", default_model)
        question_count = int(request.form.get("question_count", 10))
        override = str(request.form.get("override", "false")).lower() == "true"
        if question_count < 1 or question_count > 30:
            raise ValueError("question_count must be between 1 and 30.")

        upload = request.files.get("file")
        if upload is None or not upload.filename:
            raise ValueError("No file uploaded.")

        file_name = normalize_upload_filename(upload.filename)
        if has_uploaded_file(file_name) and not override:
            return (
                jsonify(
                    {
                        "error": f"File '{file_name}' is already uploaded.",
                        "code": "file_exists",
                        "file_name": file_name,
                    }
                ),
                409,
            )

        file_bytes = upload.read()
        if not file_bytes:
            raise ValueError("Uploaded file is empty.")

        text_inputs, pdf_inputs, source_files = load_uploaded_file_content(
            file_name,
            file_bytes,
            model_tier=model_tier,
        )
        questions_data = generate_questions(
            text_inputs,
            pdf_inputs,
            question_count,
            model,
            model_tier=model_tier,
        )
        upsert_uploaded_file(file_name)
        upsert_uploaded_file_source(file_name, file_bytes)
        store_generated_questions(source_files, model, questions_data)
        total_questions_for_source = count_generated_questions_by_source(file_name)

        return (
            jsonify(
                {
                    "questions": questions_data,
                    "source_files": source_files,
                    "model": model,
                    "model_tier": model_tier,
                    "total_questions_for_source": total_questions_for_source,
                    "max_questions_per_source": MAX_QUESTIONS_PER_SOURCE,
                }
            ),
            200,
        )
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/wrong-answer", methods=["POST"])
def wrong_answer() -> Tuple[Dict, int]:
    try:
        body = request.get_json(silent=True) or {}
        question = body.get("question", "")
        options = body.get("options", [])
        correct_index = body.get("correct_index")
        selected_index = body.get("selected_index")
        source_file = body.get("source_file", "")
        model = body.get("model", DEFAULT_MODEL)

        if not isinstance(question, str) or not question.strip():
            raise ValueError("question is required.")
        if not isinstance(options, list) or len(options) != 4 or not all(isinstance(o, str) for o in options):
            raise ValueError("options must be a list of exactly 4 strings.")
        if not isinstance(correct_index, int) or correct_index < 0 or correct_index > 3:
            raise ValueError("correct_index must be 0..3.")
        if not isinstance(selected_index, int) or selected_index < 0 or selected_index > 3:
            raise ValueError("selected_index must be 0..3.")
        if selected_index == correct_index:
            return jsonify({"ok": True, "stored": False}), 200

        store_wrong_answer(
            source_file=source_file,
            question=question.strip(),
            options=[str(o).strip() for o in options],
            correct_index=correct_index,
            selected_index=selected_index,
            model=str(model),
        )
        return jsonify({"ok": True, "stored": True}), 200
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/questions/more", methods=["POST"])
def more_questions() -> Tuple[Dict, int]:
    try:
        body = request.get_json(silent=True) or {}
        source_file = normalize_upload_filename(str(body.get("source_file", "")))
        model_tier = str(body.get("model_tier", "pro")).strip().lower()
        if model_tier not in {"pro", "free"}:
            raise ValueError("model_tier must be either 'pro' or 'free'.")
        default_model = DEFAULT_MODEL if model_tier == "pro" else DEFAULT_OPENROUTER_MODEL
        model = str(body.get("model", default_model)).strip() or default_model

        current_total = count_generated_questions_by_source(source_file)
        if current_total >= MAX_QUESTIONS_PER_SOURCE:
            return (
                jsonify(
                    {
                        "error": f"Maximum {MAX_QUESTIONS_PER_SOURCE} questions reached for '{source_file}'.",
                        "code": "max_reached",
                        "total_questions_for_source": current_total,
                        "max_questions_per_source": MAX_QUESTIONS_PER_SOURCE,
                    }
                ),
                400,
            )

        remaining = MAX_QUESTIONS_PER_SOURCE - current_total
        question_count = min(MORE_QUESTIONS_BATCH, remaining)
        source_data = get_uploaded_file_source(source_file)
        text_inputs, pdf_inputs, source_files = load_uploaded_file_content(
            source_file,
            source_data,
            model_tier=model_tier,
        )
        questions_data = generate_questions(
            text_inputs,
            pdf_inputs,
            question_count,
            model,
            model_tier=model_tier,
        )
        store_generated_questions(source_files, model, questions_data)
        updated_total = count_generated_questions_by_source(source_file)

        return (
            jsonify(
                {
                    "questions": questions_data,
                    "source_files": source_files,
                    "model": model,
                    "model_tier": model_tier,
                    "total_questions_for_source": updated_total,
                    "max_questions_per_source": MAX_QUESTIONS_PER_SOURCE,
                }
            ),
            200,
        )
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/wrong-answers", methods=["GET"])
def wrong_answers() -> Tuple[Dict, int]:
    try:
        limit = int(request.args.get("limit", 100))
        if limit < 1 or limit > 500:
            raise ValueError("limit must be between 1 and 500.")
        source_file = request.args.get("source_file", "").strip()
        if source_file:
            items = list_wrong_answers_by_source(source_file=source_file, limit=limit)
        else:
            items = list_wrong_answers(limit=limit)
        return jsonify({"items": items}), 200
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/error-collections", methods=["GET"])
def error_collections() -> Tuple[Dict, int]:
    try:
        items = list_error_collections()
        return jsonify({"items": items}), 200
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/error-collections", methods=["DELETE"])
def delete_error_collections() -> Tuple[Dict, int]:
    try:
        body = request.get_json(silent=True) or {}
        source_file = str(body.get("source_file", "")).strip()
        if not source_file:
            raise ValueError("source_file is required.")
        deleted = delete_error_collection(source_file)
        return jsonify({"ok": True, "deleted": deleted}), 200
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/favorite-collections", methods=["GET"])
def favorite_collections() -> Tuple[Dict, int]:
    try:
        items = list_generated_collections()
        return jsonify({"items": items}), 200
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/favorite-collections", methods=["DELETE"])
def delete_favorite_collections() -> Tuple[Dict, int]:
    try:
        body = request.get_json(silent=True) or {}
        source_file = str(body.get("source_file", "")).strip()
        if not source_file:
            raise ValueError("source_file is required.")
        deleted = delete_generated_collection(source_file)
        return jsonify({"ok": True, "deleted": deleted}), 200
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


@app.route("/api/generated-questions", methods=["GET"])
def generated_questions() -> Tuple[Dict, int]:
    try:
        limit = int(request.args.get("limit", 500))
        if limit < 1 or limit > 1000:
            raise ValueError("limit must be between 1 and 1000.")
        source_file = request.args.get("source_file", "").strip()
        if not source_file:
            raise ValueError("source_file is required.")
        items = list_generated_questions_by_source(source_file=source_file, limit=limit)
        return jsonify({"items": items}), 200
    except Exception as exc:
        return jsonify({"error": str(exc)}), 400


if __name__ == "__main__":
    app.run(host="localhost", port=8080, debug=True)
