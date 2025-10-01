import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:echo/pages/home_page.dart';

void main() {
  testWidgets('App builds smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: HomePage(),
      ),
    );

    // Let initial async work render at least one frame
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Echo'), findsOneWidget);
  });
}