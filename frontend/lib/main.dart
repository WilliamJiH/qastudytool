import 'dart:convert';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dropzone/flutter_dropzone.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import 'i18n_strings.dart';

void main() {
  runApp(const StudyQuestionApp());
}

class StudyQuestionApp extends StatelessWidget {
  const StudyQuestionApp({super.key});

  @override
  Widget build(BuildContext context) {
    final String? montserratFamily = GoogleFonts.montserrat().fontFamily;
    return MaterialApp(
      title: 'QA Study Tool',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A5F8F),
          brightness: Brightness.light,
        ),
        fontFamily: montserratFamily,
        fontFamilyFallback: const <String>['Calibri'],
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF3F6FA),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
      ),
      home: const StudyHomePage(),
    );
  }
}

class StudyHomePage extends StatefulWidget {
  const StudyHomePage({super.key});

  @override
  State<StudyHomePage> createState() => _StudyHomePageState();
}

class _StudyHomePageState extends State<StudyHomePage> {
  static const String _backendUrl = 'http://localhost:8080';
  static const String _proModel = 'gpt-5.2';
  static const String _freeModel = 'deepseek/deepseek-r1-0528:free';
  static const int _questionCount = 10;
  static const int _defaultMaxQuestionsPerSource = 50;

  bool _isLoading = false;
  String? _error;
  List<dynamic> _questions = <dynamic>[];
  List<dynamic> _sourceFiles = <dynamic>[];
  List<dynamic> _wrongAnswerItems = <dynamic>[];
  List<dynamic> _errorCollections = <dynamic>[];
  List<dynamic> _favoriteCollections = <dynamic>[];
  List<dynamic> _generatedItems = <dynamic>[];
  bool _showErrorCollectionList = false;
  bool _showErrorCollectionQuestions = false;
  bool _showFavoriteList = false;
  bool _showFavoriteQuestions = false;
  String _selectedErrorSourceFile = '';
  String _selectedFavoriteSourceFile = '';

  int _currentQuestionIndex = 0;
  int? _selectedOptionIndex;
  int _correctAnswers = 0;
  int _totalQuestionsForSource = 0;
  int _maxQuestionsPerSource = _defaultMaxQuestionsPerSource;
  String _modelTier = 'Pro';
  String _locale = 'en';

  I18nStrings get _i18n => I18nStrings(_locale);

  String get _activeModel => _modelTier == 'Pro' ? _proModel : _freeModel;
  String get _modelButtonText {
    if (_locale == 'zh') {
      return _modelTier == 'Pro'
          ? _i18n.t('model_pro_zh')
          : _i18n.t('model_free_zh');
    }
    return _modelTier == 'Pro' ? _i18n.t('model_pro') : _i18n.t('model_free');
  }

  Future<void> _generateQuestionsFromUpload(
    PlatformFile file, {
    bool override = false,
  }) async {
    if (file.bytes == null) {
      setState(() {
        _error = _i18n.t('error_unable_read_file');
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _questions = <dynamic>[];
      _sourceFiles = <dynamic>[];
      _showErrorCollectionList = false;
      _showErrorCollectionQuestions = false;
      _showFavoriteList = false;
      _showFavoriteQuestions = false;
      _errorCollections = <dynamic>[];
      _favoriteCollections = <dynamic>[];
      _generatedItems = <dynamic>[];
      _selectedErrorSourceFile = '';
      _selectedFavoriteSourceFile = '';
      _currentQuestionIndex = 0;
      _selectedOptionIndex = null;
      _correctAnswers = 0;
      _totalQuestionsForSource = 0;
      _maxQuestionsPerSource = _defaultMaxQuestionsPerSource;
    });

    try {
      final Uri uri = Uri.parse('$_backendUrl/api/questions/upload');
      final request = http.MultipartRequest('POST', uri)
        ..fields['question_count'] = _questionCount.toString()
        ..fields['model'] = _activeModel
        ..fields['model_tier'] = _modelTier.toLowerCase()
        ..fields['override'] = override.toString()
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            file.bytes!,
            filename: file.name,
          ),
        );

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final dynamic payload = jsonDecode(response.body);

      if (response.statusCode == 409 &&
          payload is Map<String, dynamic> &&
          payload['code'] == 'file_exists') {
        final bool shouldOverride =
            await _askOverrideFile(payload['file_name']?.toString() ?? file.name);
        if (shouldOverride) {
          await _generateQuestionsFromUpload(file, override: true);
        }
        return;
      }

      if (response.statusCode != 200) {
        throw Exception(
          payload is Map<String, dynamic>
              ? payload['error'] ?? _i18n.t('error_request_failed')
              : _i18n.t('error_request_failed'),
        );
      }

      if (payload is! Map<String, dynamic>) {
        throw Exception(_i18n.t('error_unexpected_response'));
      }

      setState(() {
        _questions = (payload['questions'] as List<dynamic>? ?? <dynamic>[]);
        _sourceFiles = (payload['source_files'] as List<dynamic>? ?? <dynamic>[]);
        _totalQuestionsForSource =
            payload['total_questions_for_source'] as int? ?? _questions.length;
        _maxQuestionsPerSource =
            payload['max_questions_per_source'] as int? ?? _defaultMaxQuestionsPerSource;
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<bool> _askOverrideFile(String fileName) async {
    final bool? result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_i18n.t('dialog_file_uploaded_title')),
          content: Text(
            _i18n.t(
              'dialog_file_uploaded_content',
              vars: <String, String>{'fileName': fileName},
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_i18n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_i18n.t('override')),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _onSelectOption(int optionIndex, int correctIndex) async {
    if (_selectedOptionIndex != null) {
      return;
    }

    final int selectedAtQuestion = _currentQuestionIndex;
    final Map<String, dynamic> currentItem =
        _questions[_currentQuestionIndex] as Map<String, dynamic>;
    if (optionIndex != correctIndex) {
        _reportWrongAnswer(
          question: currentItem['question']?.toString() ?? '',
          options: (currentItem['options'] as List<dynamic>? ?? <dynamic>[])
              .map((dynamic e) => e.toString())
              .toList(),
          correctIndex: correctIndex,
          selectedIndex: optionIndex,
        );
    }

    setState(() {
      _selectedOptionIndex = optionIndex;
      if (optionIndex == correctIndex) {
        _correctAnswers += 1;
      }
    });

    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) {
      return;
    }

    if (_selectedOptionIndex == null || _currentQuestionIndex != selectedAtQuestion) {
      return;
    }

    setState(() {
      _currentQuestionIndex += 1;
      _selectedOptionIndex = null;
    });
  }

  Future<void> _reportWrongAnswer({
    required String question,
    required List<String> options,
    required int correctIndex,
    required int selectedIndex,
  }) async {
    try {
      final Uri uri = Uri.parse('$_backendUrl/api/wrong-answer');
      await http.post(
        uri,
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(
          <String, dynamic>{
            'question': question,
            'options': options,
            'correct_index': correctIndex,
            'selected_index': selectedIndex,
            'source_file': _sourceFiles.isNotEmpty ? _sourceFiles.first.toString() : '',
            'model': _activeModel,
          },
        ),
      );
    } catch (_) {
      // Ignore tracking failures to avoid interrupting quiz flow.
    }
  }

  Future<void> _loadErrorCollection() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _showErrorCollectionList = true;
      _showErrorCollectionQuestions = false;
      _showFavoriteList = false;
      _showFavoriteQuestions = false;
      _questions = <dynamic>[];
      _wrongAnswerItems = <dynamic>[];
      _errorCollections = <dynamic>[];
      _favoriteCollections = <dynamic>[];
      _generatedItems = <dynamic>[];
      _selectedErrorSourceFile = '';
      _selectedFavoriteSourceFile = '';
      _totalQuestionsForSource = 0;
      _maxQuestionsPerSource = _defaultMaxQuestionsPerSource;
    });

    try {
      final Uri uri = Uri.parse('$_backendUrl/api/error-collections');
      final response = await http.get(uri);
      final dynamic payload = jsonDecode(response.body);

      if (response.statusCode != 200) {
        throw Exception(
          payload is Map<String, dynamic>
              ? payload['error'] ?? _i18n.t('error_request_failed')
              : _i18n.t('error_request_failed'),
        );
      }
      if (payload is! Map<String, dynamic>) {
        throw Exception(_i18n.t('error_unexpected_response'));
      }

      setState(() {
        _errorCollections = (payload['items'] as List<dynamic>? ?? <dynamic>[]);
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadWrongAnswersForSource(String sourceFile) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _showErrorCollectionList = false;
      _showErrorCollectionQuestions = true;
      _showFavoriteList = false;
      _showFavoriteQuestions = false;
      _wrongAnswerItems = <dynamic>[];
      _selectedErrorSourceFile = sourceFile;
    });

    try {
      final String encoded = Uri.encodeQueryComponent(sourceFile);
      final Uri uri = Uri.parse('$_backendUrl/api/wrong-answers?source_file=$encoded&limit=300');
      final response = await http.get(uri);
      final dynamic payload = jsonDecode(response.body);

      if (response.statusCode != 200) {
        throw Exception(
          payload is Map<String, dynamic>
              ? payload['error'] ?? _i18n.t('error_request_failed')
              : _i18n.t('error_request_failed'),
        );
      }
      if (payload is! Map<String, dynamic>) {
        throw Exception(_i18n.t('error_unexpected_response'));
      }

      setState(() {
        _wrongAnswerItems = (payload['items'] as List<dynamic>? ?? <dynamic>[]);
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _redoErrorCollectionQuestions() {
    if (_wrongAnswerItems.isEmpty) {
      return;
    }

    final List<Map<String, dynamic>> redoQuestions = _wrongAnswerItems
        .map((dynamic raw) => raw as Map<String, dynamic>)
        .map(
          (Map<String, dynamic> item) => <String, dynamic>{
            'question': item['question']?.toString() ?? '',
            'options': (item['options'] as List<dynamic>? ?? <dynamic>[])
                .map((dynamic e) => e.toString())
                .toList(),
            'correct_index': item['correct_index'] as int? ?? -1,
            'explanation': '',
          },
        )
        .where(
          (Map<String, dynamic> item) =>
              (item['question'] as String).trim().isNotEmpty &&
              (item['options'] as List<dynamic>).length == 4 &&
              (item['correct_index'] as int) >= 0 &&
              (item['correct_index'] as int) <= 3,
        )
        .toList();

    if (redoQuestions.isEmpty) {
      setState(() {
        _error = _i18n.t('no_wrong_answers_for_file');
      });
      return;
    }

    setState(() {
      _showErrorCollectionList = false;
      _showErrorCollectionQuestions = false;
      _showFavoriteList = false;
      _showFavoriteQuestions = false;
      _questions = redoQuestions;
      _sourceFiles = <dynamic>[_selectedErrorSourceFile];
      _currentQuestionIndex = 0;
      _selectedOptionIndex = null;
      _correctAnswers = 0;
      _error = null;
      _totalQuestionsForSource = 0;
      _maxQuestionsPerSource = _defaultMaxQuestionsPerSource;
    });
  }

  Future<void> _deleteErrorCollection(String sourceFile) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_i18n.t('dialog_delete_collection_title')),
          content: Text(
            _i18n.t(
              'dialog_delete_collection_content',
              vars: <String, String>{'sourceFile': sourceFile},
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_i18n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_i18n.t('delete')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final Uri uri = Uri.parse('$_backendUrl/api/error-collections');
      final response = await http.delete(
        uri,
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{'source_file': sourceFile}),
      );
      final dynamic payload = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(
          payload is Map<String, dynamic>
              ? payload['error'] ?? _i18n.t('error_request_failed')
              : _i18n.t('error_request_failed'),
        );
      }
      await _loadErrorCollection();
    } catch (err) {
      setState(() {
        _error = err.toString();
        _isLoading = false;
      });
    }
  }

  void _startNewSession() {
    setState(() {
      _showErrorCollectionList = false;
      _showErrorCollectionQuestions = false;
      _showFavoriteList = false;
      _showFavoriteQuestions = false;
      _error = null;
      _questions = <dynamic>[];
      _wrongAnswerItems = <dynamic>[];
      _errorCollections = <dynamic>[];
      _favoriteCollections = <dynamic>[];
      _generatedItems = <dynamic>[];
      _selectedErrorSourceFile = '';
      _selectedFavoriteSourceFile = '';
      _sourceFiles = <dynamic>[];
      _currentQuestionIndex = 0;
      _selectedOptionIndex = null;
      _correctAnswers = 0;
      _totalQuestionsForSource = 0;
      _maxQuestionsPerSource = _defaultMaxQuestionsPerSource;
    });
  }

  Future<void> _loadFavoriteCollections() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _showFavoriteList = true;
      _showFavoriteQuestions = false;
      _showErrorCollectionList = false;
      _showErrorCollectionQuestions = false;
      _questions = <dynamic>[];
      _wrongAnswerItems = <dynamic>[];
      _generatedItems = <dynamic>[];
      _favoriteCollections = <dynamic>[];
      _sourceFiles = <dynamic>[];
      _selectedFavoriteSourceFile = '';
      _selectedErrorSourceFile = '';
      _totalQuestionsForSource = 0;
      _maxQuestionsPerSource = _defaultMaxQuestionsPerSource;
    });

    try {
      final Uri uri = Uri.parse('$_backendUrl/api/favorite-collections');
      final response = await http.get(uri);
      final dynamic payload = jsonDecode(response.body);

      if (response.statusCode != 200) {
        throw Exception(
          payload is Map<String, dynamic>
              ? payload['error'] ?? _i18n.t('error_request_failed')
              : _i18n.t('error_request_failed'),
        );
      }
      if (payload is! Map<String, dynamic>) {
        throw Exception(_i18n.t('error_unexpected_response'));
      }

      setState(() {
        _favoriteCollections = (payload['items'] as List<dynamic>? ?? <dynamic>[]);
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadGeneratedQuestionsForSource(String sourceFile) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _showFavoriteList = false;
      _showFavoriteQuestions = true;
      _showErrorCollectionList = false;
      _showErrorCollectionQuestions = false;
      _generatedItems = <dynamic>[];
      _selectedFavoriteSourceFile = sourceFile;
    });

    try {
      final String encoded = Uri.encodeQueryComponent(sourceFile);
      final Uri uri = Uri.parse('$_backendUrl/api/generated-questions?source_file=$encoded&limit=500');
      final response = await http.get(uri);
      final dynamic payload = jsonDecode(response.body);

      if (response.statusCode != 200) {
        throw Exception(
          payload is Map<String, dynamic>
              ? payload['error'] ?? _i18n.t('error_request_failed')
              : _i18n.t('error_request_failed'),
        );
      }
      if (payload is! Map<String, dynamic>) {
        throw Exception(_i18n.t('error_unexpected_response'));
      }

      setState(() {
        _generatedItems = (payload['items'] as List<dynamic>? ?? <dynamic>[]);
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreQuestions() async {
    if (_sourceFiles.isEmpty || _isLoading) {
      return;
    }
    final String sourceFile = _sourceFiles.first.toString();
    if (sourceFile.isEmpty || _totalQuestionsForSource >= _maxQuestionsPerSource) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final Uri uri = Uri.parse('$_backendUrl/api/questions/more');
      final response = await http.post(
        uri,
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(
          <String, dynamic>{
            'source_file': sourceFile,
            'model': _activeModel,
            'model_tier': _modelTier.toLowerCase(),
          },
        ),
      );
      final dynamic payload = jsonDecode(response.body);
      if (response.statusCode != 200) {
        if (payload is Map<String, dynamic> && payload['code'] == 'max_reached') {
          setState(() {
            _totalQuestionsForSource =
                payload['total_questions_for_source'] as int? ?? _totalQuestionsForSource;
            _maxQuestionsPerSource =
                payload['max_questions_per_source'] as int? ?? _maxQuestionsPerSource;
          });
          return;
        }
        throw Exception(
          payload is Map<String, dynamic>
              ? payload['error'] ?? _i18n.t('error_request_failed')
              : _i18n.t('error_request_failed'),
        );
      }
      if (payload is! Map<String, dynamic>) {
        throw Exception(_i18n.t('error_unexpected_response'));
      }

      final List<dynamic> moreQuestions =
          (payload['questions'] as List<dynamic>? ?? <dynamic>[]);
      if (moreQuestions.isEmpty) {
        throw Exception(_i18n.t('error_no_more_questions'));
      }

      setState(() {
        _questions.addAll(moreQuestions);
        _sourceFiles = (payload['source_files'] as List<dynamic>? ?? _sourceFiles);
        _totalQuestionsForSource =
            payload['total_questions_for_source'] as int? ?? _questions.length;
        _maxQuestionsPerSource =
            payload['max_questions_per_source'] as int? ?? _maxQuestionsPerSource;
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteFavoriteCollection(String sourceFile) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(_i18n.t('dialog_delete_favorite_title')),
          content: Text(
            _i18n.t(
              'dialog_delete_favorite_content',
              vars: <String, String>{'sourceFile': sourceFile},
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(_i18n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(_i18n.t('delete')),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final Uri uri = Uri.parse('$_backendUrl/api/favorite-collections');
      final response = await http.delete(
        uri,
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{'source_file': sourceFile}),
      );
      final dynamic payload = jsonDecode(response.body);
      if (response.statusCode != 200) {
        throw Exception(
          payload is Map<String, dynamic>
              ? payload['error'] ?? _i18n.t('error_request_failed')
              : _i18n.t('error_request_failed'),
        );
      }
      await _loadFavoriteCollections();
    } catch (err) {
      setState(() {
        _error = err.toString();
        _isLoading = false;
      });
    }
  }

  void _redoFavoriteQuestions() {
    if (_generatedItems.isEmpty) {
      return;
    }

    final List<Map<String, dynamic>> redoQuestions = _generatedItems
        .map((dynamic raw) => raw as Map<String, dynamic>)
        .map(
          (Map<String, dynamic> item) => <String, dynamic>{
            'question': item['question']?.toString() ?? '',
            'options': (item['options'] as List<dynamic>? ?? <dynamic>[])
                .map((dynamic e) => e.toString())
                .toList(),
            'correct_index': item['correct_index'] as int? ?? -1,
            'explanation': item['explanation']?.toString() ?? '',
          },
        )
        .where(
          (Map<String, dynamic> item) =>
              (item['question'] as String).trim().isNotEmpty &&
              (item['options'] as List<dynamic>).length == 4 &&
              (item['correct_index'] as int) >= 0 &&
              (item['correct_index'] as int) <= 3,
        )
        .toList();

    if (redoQuestions.isEmpty) {
      setState(() {
        _error = _i18n.t('no_generated_questions_for_file');
      });
      return;
    }

    setState(() {
      _showFavoriteList = false;
      _showFavoriteQuestions = false;
      _showErrorCollectionList = false;
      _showErrorCollectionQuestions = false;
      _questions = redoQuestions;
      _sourceFiles = <dynamic>[_selectedFavoriteSourceFile];
      _currentQuestionIndex = 0;
      _selectedOptionIndex = null;
      _correctAnswers = 0;
      _error = null;
      _totalQuestionsForSource = 0;
      _maxQuestionsPerSource = _defaultMaxQuestionsPerSource;
    });
  }

  Future<void> _openCustomizePanel() async {
    DropzoneViewController? dropzoneController;
    bool isHovering = false;

    Future<void> pickFromFileDialog() async {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        withData: true,
        allowedExtensions: <String>['txt', 'pdf'],
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final PlatformFile file = result.files.first;
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
      await _generateQuestionsFromUpload(file);
    }

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: _i18n.t('customize'),
      barrierColor: Colors.black26,
      pageBuilder: (BuildContext context, _, __) {
        final double width = MediaQuery.of(context).size.width * 0.6;
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: const SizedBox.expand(),
              ),
            ),
            Center(
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              child: StatefulBuilder(
                  builder: (BuildContext context, StateSetter setInnerState) {
                    Future<void> handleDrop(dynamic event) async {
                      if (dropzoneController == null) {
                        return;
                      }
                      final String fileName =
                          await dropzoneController!.getFilename(event);
                      final Uint8List bytes =
                          await dropzoneController!.getFileData(event);
                      final PlatformFile file = PlatformFile(
                        name: fileName,
                        size: bytes.length,
                        bytes: bytes,
                      );
                      if (!context.mounted) {
                        return;
                      }
                      Navigator.of(context).pop();
                      await _generateQuestionsFromUpload(file);
                    }

                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: width,
                        maxWidth: width,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _i18n.t('customize'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 14),
                            GestureDetector(
                              onTap: pickFromFileDialog,
                              child: Container(
                                height: 180,
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: isHovering
                                      ? const Color(0xFFEAF6FC)
                                      : const Color(0xFFF8FBFD),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isHovering
                                        ? const Color(0xFF0F6B94)
                                        : const Color(0xFFB9D5E4),
                                    width: 2,
                                  ),
                                ),
                                child: Stack(
                                  children: <Widget>[
                                    if (kIsWeb)
                                      Positioned.fill(
                                        child: DropzoneView(
                                          onCreated: (DropzoneViewController ctrl) {
                                            dropzoneController = ctrl;
                                          },
                                          onHover: () {
                                            isHovering = true;
                                            setInnerState(() {});
                                          },
                                          onLeave: () {
                                            isHovering = false;
                                            setInnerState(() {});
                                          },
                                          onDropFile: (dynamic event) async {
                                            isHovering = false;
                                            setInnerState(() {});
                                            await handleDrop(event);
                                          },
                                          operation: DragOperation.copy,
                                          cursor: CursorType.grab,
                                        ),
                                      ),
                                    Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          const Icon(Icons.upload_file, size: 34),
                                          const SizedBox(height: 10),
                                          Text(
                                            _i18n.t('upload_file'),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            _i18n.t('upload_hint'),
                                            style: TextStyle(fontSize: 12),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildModernHeader(context),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (_isLoading) ...<Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: const LinearProgressIndicator(minHeight: 8),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_sourceFiles.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _sourceFiles
                            .map(
                              (dynamic name) => Chip(
                                avatar: const Icon(Icons.description, size: 16),
                                label: Text(name.toString()),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  if (_error != null)
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.onErrorContainer,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _error!,
                                style: TextStyle(
                                  color:
                                      Theme.of(context).colorScheme.onErrorContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (_error != null) const SizedBox(height: 12),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _buildBody(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernHeader(BuildContext context) {
    const double headerHeight = 78;
    return Container(
      width: double.infinity,
      height: headerHeight,
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FA),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Image.asset(
              'assets/images/qastudylogo.png',
              height: headerHeight - 2,
              fit: BoxFit.fitHeight,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _buildHeaderLink(
                  label: _i18n.t('customize'),
                  onTap: _isLoading ? null : () => _openCustomizePanel(),
                ),
                _buildHeaderLink(
                  label: _i18n.t('error_collection'),
                  onTap: _isLoading ? null : () => _loadErrorCollection(),
                ),
                _buildHeaderLink(
                  label: _i18n.t('favorite'),
                  onTap: _isLoading ? null : () => _loadFavoriteCollections(),
                ),
                _buildHeaderLink(
                  label: _i18n.t('new'),
                  onTap: _isLoading ? null : _startNewSession,
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: () {
                    setState(() {
                      _locale = _locale == 'en' ? 'zh' : 'en';
                    });
                  },
                  child: Text(_locale == 'en' ? 'English' : '中文'),
                ),
                const SizedBox(width: 10),
                FilledButton.tonal(
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _modelTier = _modelTier == 'Pro' ? 'Free' : 'Pro';
                          });
                        },
                  child: Text(_modelButtonText),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_showFavoriteList) {
      if (_favoriteCollections.isEmpty) {
        return const SizedBox.shrink();
      }
      return ListView.builder(
        itemCount: _favoriteCollections.length,
        itemBuilder: (BuildContext context, int index) {
          final Map<String, dynamic> item =
              _favoriteCollections[index] as Map<String, dynamic>;
          final String sourceFile = item['source_file']?.toString() ?? '';
          final String dateCreated = item['date_created']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                enabled: !_isLoading,
                onTap: _isLoading ? null : () => _loadGeneratedQuestionsForSource(sourceFile),
                title: Text('$sourceFile - $dateCreated'),
                trailing: IconButton(
                  tooltip: _i18n.t('delete_tooltip'),
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  onPressed: _isLoading ? null : () => _deleteFavoriteCollection(sourceFile),
                ),
              ),
            ),
          );
        },
      );
    }

    if (_showFavoriteQuestions) {
      if (_generatedItems.isEmpty) {
        return Center(child: Text(_i18n.t('no_generated_questions_for_file')));
      }
      return Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                TextButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _showFavoriteQuestions = false;
                            _showFavoriteList = true;
                          });
                        },
                  icon: const Icon(Icons.arrow_back),
                  label: Text(_i18n.t('back_to_favorites')),
                ),
                FilledButton(
                  onPressed: _isLoading ? null : _redoFavoriteQuestions,
                  child: Text(_i18n.t('redo_error_questions')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: Text(
              _selectedFavoriteSourceFile,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _generatedItems.length,
              itemBuilder: (BuildContext context, int index) {
                final Map<String, dynamic> item =
                    _generatedItems[index] as Map<String, dynamic>;
                final List<dynamic> options =
                    item['options'] as List<dynamic>? ?? <dynamic>[];
                final int correctIndex = item['correct_index'] as int? ?? -1;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item['question']?.toString() ?? '',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (int i = 0; i < options.length; i++)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: i == correctIndex ? Colors.green : Colors.transparent,
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Text(
                              '${String.fromCharCode(65 + i)}. ${options[i]}',
                              style: TextStyle(
                                color: i == correctIndex ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                        if ((item['explanation']?.toString() ?? '').isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4, bottom: 6),
                            child: Text(
                              item['explanation']?.toString() ?? '',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        Text(
                          _i18n.t(
                            'source_line',
                            vars: <String, String>{
                              'source': (item['source_file'] ?? '').toString(),
                              'time': (item['created_at'] ?? '').toString(),
                            },
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    if (_showErrorCollectionList) {
      if (_errorCollections.isEmpty) {
        return const SizedBox.shrink();
      }
      return ListView.builder(
        itemCount: _errorCollections.length,
        itemBuilder: (BuildContext context, int index) {
          final Map<String, dynamic> item =
              _errorCollections[index] as Map<String, dynamic>;
          final String sourceFile = item['source_file']?.toString() ?? '';
          final String dateUploaded = item['date_uploaded']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              child: ListTile(
                enabled: !_isLoading,
                onTap: _isLoading ? null : () => _loadWrongAnswersForSource(sourceFile),
                title: Text('$sourceFile - $dateUploaded'),
                trailing: IconButton(
                  tooltip: _i18n.t('delete_tooltip'),
                  icon: const Icon(Icons.delete_outline),
                  color: Colors.red,
                  onPressed: _isLoading ? null : () => _deleteErrorCollection(sourceFile),
                ),
              ),
            ),
          );
        },
      );
    }

    if (_showErrorCollectionQuestions) {
      if (_wrongAnswerItems.isEmpty) {
        return Center(child: Text(_i18n.t('no_wrong_answers_for_file')));
      }
      return Column(
        children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                TextButton.icon(
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _showErrorCollectionQuestions = false;
                            _showErrorCollectionList = true;
                          });
                        },
                  icon: const Icon(Icons.arrow_back),
                  label: Text(_i18n.t('back_to_collections')),
                ),
                FilledButton(
                  onPressed: _isLoading ? null : _redoErrorCollectionQuestions,
                  child: Text(_i18n.t('redo_error_questions')),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black12),
            ),
            child: Text(
              _selectedErrorSourceFile,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _wrongAnswerItems.length,
              itemBuilder: (BuildContext context, int index) {
                final Map<String, dynamic> item =
                    _wrongAnswerItems[index] as Map<String, dynamic>;
                final List<dynamic> options =
                    item['options'] as List<dynamic>? ?? <dynamic>[];
                final int correctIndex = item['correct_index'] as int? ?? -1;
                final int selectedIndex = item['selected_index'] as int? ?? -1;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item['question']?.toString() ?? '',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        for (int i = 0; i < options.length; i++)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: i == correctIndex
                                  ? Colors.green
                                  : (i == selectedIndex ? Colors.red : Colors.transparent),
                              border: Border.all(color: Colors.black12),
                            ),
                            child: Text(
                              '${String.fromCharCode(65 + i)}. ${options[i]}',
                              style: TextStyle(
                                color: (i == correctIndex || i == selectedIndex)
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                            ),
                          ),
                        Text(
                          _i18n.t(
                            'source_line',
                            vars: <String, String>{
                              'source': (item['source_file'] ?? '').toString(),
                              'time': (item['created_at'] ?? '').toString(),
                            },
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    if (_questions.isEmpty) {
      return const SizedBox.shrink();
    }

    if (_currentQuestionIndex >= _questions.length) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _i18n.t(
                'completed_questions',
                vars: <String, String>{'count': _questions.length.toString()},
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _i18n.t(
                'score_line',
                vars: <String, String>{
                  'correct': _correctAnswers.toString(),
                  'total': _questions.length.toString(),
                },
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (_sourceFiles.isNotEmpty &&
                _totalQuestionsForSource > 0 &&
                _questions.length % _questionCount == 0 &&
                _totalQuestionsForSource < _maxQuestionsPerSource) ...<Widget>[
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _isLoading ? null : _loadMoreQuestions,
                child: Text(_i18n.t('more_questions')),
              ),
            ],
          ],
        ),
      );
    }

    final Map<String, dynamic> item =
        _questions[_currentQuestionIndex] as Map<String, dynamic>;
    final List<dynamic> options = item['options'] as List<dynamic>? ?? <dynamic>[];
    final int correctIndex = item['correct_index'] as int? ?? -1;

    return SingleChildScrollView(
      key: const ValueKey<String>('quiz-view'),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                _i18n.t(
                  'question_progress',
                  vars: <String, String>{
                    'index': (_currentQuestionIndex + 1).toString(),
                    'total': _questions.length.toString(),
                  },
                ),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Text(
                item['question']?.toString() ?? '',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              for (int i = 0; i < options.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: _buttonBackgroundColor(i, correctIndex) ?? Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _selectedOptionIndex == null
                          ? () => _onSelectOption(i, correctIndex)
                          : null,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Text(
                          '${String.fromCharCode(65 + i)}. ${options[i]}',
                          style: TextStyle(
                            color: _buttonForegroundColor(i) ?? Colors.black87,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_selectedOptionIndex != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_i18n.t('moving_next')),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color? _buttonBackgroundColor(int optionIndex, int correctIndex) {
    if (_selectedOptionIndex == null) {
      return null;
    }
    final bool selectedIsCorrect = _selectedOptionIndex == correctIndex;

    if (optionIndex == correctIndex) {
      return Colors.green;
    }

    if (!selectedIsCorrect && optionIndex == _selectedOptionIndex) {
      return Colors.red;
    }

    return null;
  }

  Color? _buttonForegroundColor(int optionIndex) {
    if (_selectedOptionIndex == optionIndex) {
      return Colors.white;
    }
    return null;
  }

  Widget _buildHeaderLink({
    required String label,
    required VoidCallback? onTap,
  }) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF4B5563),
          fontWeight: FontWeight.w600,
          fontSize: 16,
        ),
      ),
    );
  }
}
