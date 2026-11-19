import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/legal_text.dart';

void main() {
  testWidgets('legal rendering preserves supplied wording and text-line spaces', (
    tester,
  ) async {
    const text =
        'RALLY4EVER Waive and Release\n\n1.  Respect for All\nRALLY4EVER , and its agents\nPhoto Release \n';
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LegalFormText(text))),
    );
    expect(find.text('RALLY4EVER Waive and Release'), findsOneWidget);
    expect(find.text('1.  Respect for All'), findsOneWidget);
    expect(find.text('RALLY4EVER , and its agents'), findsOneWidget);
    expect(find.text('Photo Release '), findsOneWidget);
    expect(formText({'body': text, 'content': 'other'}), text);
  });
}
