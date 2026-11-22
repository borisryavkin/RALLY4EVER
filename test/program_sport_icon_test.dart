import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/participant/catalogue.dart';

void main() {
  testWidgets('program cards use the pickleball asset and keep tennis racket', (
    tester,
  ) async {
    for (final sport in ['pickleball', 'tennis']) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProgramCard(
              program: {'name': 'Test program', 'sport': sport},
              onTap: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.sports), findsNothing);
      expect(
        find.byType(SvgPicture),
        sport == 'pickleball' ? findsOneWidget : findsNothing,
      );
      expect(
        find.byIcon(Icons.sports_tennis),
        sport == 'tennis' ? findsOneWidget : findsNothing,
      );
      expect(tester.takeException(), isNull);
    }
  });
}
