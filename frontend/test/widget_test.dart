import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/main.dart';

void main() {
  testWidgets('renders app shell', (WidgetTester tester) async {
    await tester.pumpWidget(const StudyQuestionApp());

    expect(find.text('QA Study Tool'), findsOneWidget);
    expect(find.text('Generate Questions'), findsOneWidget);
  });
}
