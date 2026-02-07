"""Local backend API tests (no external network required)."""

import io
import os
import tempfile
import unittest
from unittest.mock import patch

import app as app_module
from app import app


class BackendApiTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.temp_db_path = os.path.join(self.temp_dir.name, "test_study_data.db")
        self.original_db_path = app_module.DB_PATH
        app_module.DB_PATH = self.temp_db_path
        app_module.init_db()
        self.client = app.test_client()

    def tearDown(self) -> None:
        app_module.DB_PATH = self.original_db_path
        self.temp_dir.cleanup()

    def test_health_endpoint(self) -> None:
        response = self.client.get('/api/health')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.get_json(), {'ok': True})

    @patch('app.generate_questions')
    @patch('app.load_notes_content')
    def test_questions_endpoint(self, mock_load_notes_content, mock_generate_questions) -> None:
        mock_load_notes_content.return_value = (
            [{'type': 'input_text', 'text': '# Source: sample.txt\\nhello world'}],
            [],
            ['sample.txt'],
        )
        mock_generate_questions.return_value = [
            {
                'question': 'What is hello?',
                'options': ['A', 'B', 'C', 'D'],
                'correct_index': 0,
                'explanation': 'Because.',
            }
        ]

        response = self.client.post('/api/questions', json={
            'question_count': 1,
            'model': 'gpt-5.2',
            'model_tier': 'pro',
        })

        self.assertEqual(response.status_code, 200)
        payload = response.get_json()
        self.assertIn('questions', payload)
        self.assertEqual(payload['model'], 'gpt-5.2')
        self.assertEqual(payload['source_files'], ['sample.txt'])

    @patch('app.generate_questions')
    def test_upload_duplicate_returns_409_then_override_succeeds(self, mock_generate_questions) -> None:
        mock_generate_questions.return_value = [
            {
                'question': 'Q1',
                'options': ['A', 'B', 'C', 'D'],
                'correct_index': 0,
                'explanation': 'E',
            }
        ]

        first_data = {
            'file': (io.BytesIO(b'hello world'), 'notes.txt'),
            'question_count': '1',
            'model_tier': 'pro',
            'model': 'gpt-5.2',
        }
        first = self.client.post('/api/questions/upload', data=first_data, content_type='multipart/form-data')
        self.assertEqual(first.status_code, 200)

        dup_data = {
            'file': (io.BytesIO(b'hello world again'), 'notes.txt'),
            'question_count': '1',
            'model_tier': 'pro',
            'model': 'gpt-5.2',
        }
        second = self.client.post('/api/questions/upload', data=dup_data, content_type='multipart/form-data')
        self.assertEqual(second.status_code, 409)
        self.assertEqual(second.get_json().get('code'), 'file_exists')

        override_data = {
            'file': (io.BytesIO(b'hello override'), 'notes.txt'),
            'question_count': '1',
            'model_tier': 'pro',
            'model': 'gpt-5.2',
            'override': 'true',
        }
        third = self.client.post('/api/questions/upload', data=override_data, content_type='multipart/form-data')
        self.assertEqual(third.status_code, 200)

    @patch('app.generate_questions')
    def test_favorite_collections_and_generated_questions_flow(self, mock_generate_questions) -> None:
        mock_generate_questions.return_value = [
            {
                'question': 'Q1',
                'options': ['A', 'B', 'C', 'D'],
                'correct_index': 1,
                'explanation': 'E1',
            },
            {
                'question': 'Q2',
                'options': ['A2', 'B2', 'C2', 'D2'],
                'correct_index': 2,
                'explanation': 'E2',
            },
        ]

        upload_data = {
            'file': (io.BytesIO(b'hello world'), 'fav_notes.txt'),
            'question_count': '2',
            'model_tier': 'pro',
            'model': 'gpt-5.2',
        }
        upload_resp = self.client.post('/api/questions/upload', data=upload_data, content_type='multipart/form-data')
        self.assertEqual(upload_resp.status_code, 200)

        collections_resp = self.client.get('/api/favorite-collections')
        self.assertEqual(collections_resp.status_code, 200)
        collections = collections_resp.get_json().get('items', [])
        self.assertEqual(len(collections), 1)
        self.assertEqual(collections[0]['source_file'], 'fav_notes.txt')
        self.assertEqual(collections[0]['question_count'], 2)

        questions_resp = self.client.get('/api/generated-questions?source_file=fav_notes.txt&limit=10')
        self.assertEqual(questions_resp.status_code, 200)
        items = questions_resp.get_json().get('items', [])
        self.assertEqual(len(items), 2)
        self.assertEqual(items[0]['source_file'], 'fav_notes.txt')
        self.assertIn('question', items[0])
        self.assertIn('options', items[0])

        delete_resp = self.client.delete('/api/favorite-collections', json={'source_file': 'fav_notes.txt'})
        self.assertEqual(delete_resp.status_code, 200)
        self.assertEqual(delete_resp.get_json().get('deleted'), 2)

        collections_after_delete = self.client.get('/api/favorite-collections')
        self.assertEqual(collections_after_delete.status_code, 200)
        self.assertEqual(collections_after_delete.get_json().get('items', []), [])

    @patch('app.generate_questions')
    def test_more_questions_until_50_limit(self, mock_generate_questions) -> None:
        def fake_generate_questions(_text_inputs, _pdf_inputs, question_count, _model, model_tier='pro'):
            return [
                {
                    'question': f'Q{i+1}',
                    'options': ['A', 'B', 'C', 'D'],
                    'correct_index': 0,
                    'explanation': 'E',
                }
                for i in range(question_count)
            ]

        mock_generate_questions.side_effect = fake_generate_questions

        upload_data = {
            'file': (io.BytesIO(b'hello world'), 'limit_notes.txt'),
            'question_count': '10',
            'model_tier': 'pro',
            'model': 'gpt-5.2',
        }
        upload_resp = self.client.post('/api/questions/upload', data=upload_data, content_type='multipart/form-data')
        self.assertEqual(upload_resp.status_code, 200)
        self.assertEqual(upload_resp.get_json().get('total_questions_for_source'), 10)

        for expected_total in (20, 30, 40, 50):
            more_resp = self.client.post('/api/questions/more', json={
                'source_file': 'limit_notes.txt',
                'model_tier': 'pro',
                'model': 'gpt-5.2',
            })
            self.assertEqual(more_resp.status_code, 200)
            self.assertEqual(more_resp.get_json().get('total_questions_for_source'), expected_total)

        limit_resp = self.client.post('/api/questions/more', json={
            'source_file': 'limit_notes.txt',
            'model_tier': 'pro',
            'model': 'gpt-5.2',
        })
        self.assertEqual(limit_resp.status_code, 400)
        self.assertEqual(limit_resp.get_json().get('code'), 'max_reached')

    def test_wrong_answer_collection_and_delete_flow(self) -> None:
        payload = {
            'question': 'What is 2+2?',
            'options': ['1', '2', '3', '4'],
            'correct_index': 3,
            'selected_index': 1,
            'source_file': 'math.txt',
            'model': 'gpt-5.2',
        }

        log_resp = self.client.post('/api/wrong-answer', json=payload)
        self.assertEqual(log_resp.status_code, 200)
        self.assertTrue(log_resp.get_json().get('stored'))

        list_resp = self.client.get('/api/wrong-answers?source_file=math.txt&limit=10')
        self.assertEqual(list_resp.status_code, 200)
        items = list_resp.get_json().get('items', [])
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]['question'], 'What is 2+2?')

        collections_resp = self.client.get('/api/error-collections')
        self.assertEqual(collections_resp.status_code, 200)
        collections = collections_resp.get_json().get('items', [])
        self.assertEqual(len(collections), 1)
        self.assertEqual(collections[0]['source_file'], 'math.txt')

        delete_resp = self.client.delete('/api/error-collections', json={'source_file': 'math.txt'})
        self.assertEqual(delete_resp.status_code, 200)
        self.assertEqual(delete_resp.get_json().get('deleted'), 1)

        list_after_delete = self.client.get('/api/wrong-answers?source_file=math.txt&limit=10')
        self.assertEqual(list_after_delete.status_code, 200)
        self.assertEqual(list_after_delete.get_json().get('items', []), [])


if __name__ == '__main__':
    unittest.main()
