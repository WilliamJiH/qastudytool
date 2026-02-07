class I18nStrings {
  I18nStrings(this.locale);

  final String locale;

  static const Map<String, Map<String, String>> _values = {
    'en': {
      'app_title': 'QA Study Tool',
      'error_unable_read_file': 'Unable to read selected file.',
      'error_request_failed': 'Request failed.',
      'error_unexpected_response': 'Unexpected response format.',
      'error_no_more_questions': 'No additional questions were generated.',
      'dialog_file_uploaded_title': 'File Already Uploaded',
      'dialog_file_uploaded_content':
          "'{fileName}' is already uploaded. Do you want to override it?",
      'cancel': 'Cancel',
      'override': 'Override',
      'dialog_delete_collection_title': 'Delete Collection',
      'dialog_delete_collection_content':
          "Delete error collection for '{sourceFile}'?",
      'dialog_delete_favorite_title': 'Delete Favourite',
      'dialog_delete_favorite_content': "Delete favourite questions for '{sourceFile}'?",
      'delete': 'Delete',
      'model': 'Model',
      'language': 'Language',
      'language_en': 'English',
      'language_zh': 'Chinese',
      'model_pro': 'Pro',
      'model_free': 'Free',
      'model_pro_zh': '专业',
      'model_free_zh': '免费',
      'customize': 'Customize',
      'error_collection': 'Error Collection',
      'favorite': 'Favourite',
      'new': 'New',
      'more_questions': 'More question?',
      'upload_file': 'Upload File',
      'upload_hint': 'Drag & drop .txt/.pdf here or click to browse',
      'no_wrong_answers_for_file': 'No wrong-answer records for this file.',
      'redo_error_questions': 'Redo these questions',
      'back_to_collections': 'Back To Collections',
      'no_generated_questions_for_file': 'No generated questions for this file.',
      'back_to_favorites': 'Back To Favourite',
      'source_line': 'Source: {source} | {time}',
      'completed_questions': 'Completed {count} questions',
      'score_line': 'Score: {correct}/{total}',
      'question_progress': 'Question {index} of {total}',
      'moving_next': 'Moving to next question...',
      'delete_tooltip': 'Delete',
      'no_error_collections': '',
    },
    'zh': {
      'app_title': '智学',
      'error_unable_read_file': '无法读取所选文件。',
      'error_request_failed': '请求失败。',
      'error_unexpected_response': '响应格式异常。',
      'error_no_more_questions': '未生成更多题目。',
      'dialog_file_uploaded_title': '文件已上传',
      'dialog_file_uploaded_content': "'{fileName}' 已上传，是否覆盖？",
      'cancel': '取消',
      'override': '覆盖',
      'dialog_delete_collection_title': '删除错题集',
      'dialog_delete_collection_content': "确定删除 '{sourceFile}' 的错题集吗？",
      'dialog_delete_favorite_title': '删除收藏',
      'dialog_delete_favorite_content': "确定删除 '{sourceFile}' 的收藏题目吗？",
      'delete': '删除',
      'model': '模型',
      'language': '语言',
      'language_en': '英语',
      'language_zh': '中文',
      'model_pro': '专业',
      'model_free': '免费',
      'model_pro_zh': '专业',
      'model_free_zh': '免费',
      'customize': '自定义',
      'error_collection': '错题集',
      'favorite': '收藏',
      'new': '新建',
      'more_questions': '更多题目？',
      'upload_file': '上传文件',
      'upload_hint': '拖拽 .txt/.pdf 到此处，或点击选择文件',
      'no_wrong_answers_for_file': '该文件暂无错题记录。',
      'redo_error_questions': '重做这些题目',
      'back_to_collections': '返回错题集列表',
      'no_generated_questions_for_file': '该文件暂无已生成题目。',
      'back_to_favorites': '返回收藏列表',
      'source_line': '来源：{source} | {time}',
      'completed_questions': '已完成 {count} 题',
      'score_line': '得分：{correct}/{total}',
      'question_progress': '第 {index}/{total} 题',
      'moving_next': '正在跳转到下一题...',
      'delete_tooltip': '删除',
      'no_error_collections': '',
    },
  };

  String t(String key, {Map<String, String>? vars}) {
    final selected = _values[locale] ?? _values['en']!;
    String value = selected[key] ?? _values['en']![key] ?? key;
    if (vars != null) {
      vars.forEach((k, v) {
        value = value.replaceAll('{$k}', v);
      });
    }
    return value;
  }
}
