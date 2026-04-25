import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:college_student_app/main.dart';

void main() {
  testWidgets('App loads successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}