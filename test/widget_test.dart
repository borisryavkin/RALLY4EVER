// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:rally4ever/main.dart';

void main() {
  testWidgets('shows the Rally4ever welcome flow', (WidgetTester tester) async {
    // Use a phone/tablet portrait viewport: the onboarding page is designed
    // around the vertical layout used by the supported mobile clients.
    tester.view.physicalSize = const Size(1600, 2560);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MyApp());
    expect(find.text('Find your\nprogram'), findsOneWidget);
  });
}
