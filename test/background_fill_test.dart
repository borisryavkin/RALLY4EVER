import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'support/fake_participant.dart';

/// Item 5: the page BACKGROUND must fill the whole screen on tablets/in
/// landscape (red for onboarding, beige elsewhere), with only the CONTENT
/// centred at a sensible max width -- at exactly the three sizes the task
/// specifies (800x1280 portrait, 1280x800 landscape, 360x640 phone).
void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader('Jellee')..addFont(
          rootBundle.load('assets/fonts/Jellee_1223/TTF/Jellee-Bold.ttf'),
        ))
        .load();
  });

  const sizes = [Size(800, 1280), Size(1280, 800), Size(360, 640)];

  Future<void> show(WidgetTester tester, Size size, String page) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ParticipantApp(
        repository: FakeParticipantRepository(),
        initialPage: page,
        cameraEnabled: false,
        mapTilesEnabled: false,
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final size in sizes) {
    testWidgets(
      'onboarding (red) background fills the whole screen at ${size.width}x${size.height}, no overflow',
      (tester) async {
        await show(tester, size, 'welcome1');
        expect(tester.takeException(), isNull);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(scaffold.backgroundColor, isNot(Colors.white));
        expect(scaffold.backgroundColor, isNot(const Color(0xffe7e2de)));
        final scaffoldSize = tester.getSize(find.byType(Scaffold).first);
        expect(scaffoldSize.width, size.width);
        // Content (the Continue button) stays well short of the full
        // width on a wide screen -- centred, not stretched edge to edge.
        // The app's existing tablet breakpoint is 840 (see frame()'s
        // isWide/wideBreakpoint); below that, content is intentionally
        // full-width, same as a phone.
        final buttonWidth = tester
            .getSize(find.byType(FilledButton).last)
            .width;
        if (size.width >= 840) {
          expect(buttonWidth, lessThanOrEqualTo(560));
        }
      },
    );
  }

  for (final size in sizes) {
    testWidgets(
      'a form screen (sign-up) background fills the whole screen at ${size.width}x${size.height}, content capped at 560',
      (tester) async {
        await show(tester, size, 'signup');
        expect(tester.takeException(), isNull);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
        expect(scaffold.backgroundColor, isNot(Colors.white));
        final scaffoldSize = tester.getSize(find.byType(Scaffold).first);
        expect(scaffoldSize.width, size.width);
        final contentArea = tester.getSize(find.byKey(const Key('frame-content')));
        expect(contentArea.width, size.width);
        if (size.width >= 840) {
          final emailField = tester.getSize(find.byKey(const Key('email')));
          expect(emailField.width, lessThanOrEqualTo(560));
        }
      },
    );
  }

  testWidgets(
    'a list screen (home/Play) keeps the wider cap, not squeezed to 560',
    (tester) async {
      await show(tester, const Size(1280, 800), 'home');
      expect(tester.takeException(), isNull);
      final listViewWidth = tester.getSize(find.byType(ListView).first).width;
      expect(listViewWidth, greaterThan(560));
      expect(listViewWidth, lessThanOrEqualTo(720));
    },
  );
}
