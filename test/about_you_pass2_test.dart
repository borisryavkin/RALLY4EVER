import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/forms.dart';
import 'package:rally4ever/participant/about_icons.dart';
import 'package:rally4ever/participant/theme.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'support/fake_participant.dart';

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    for (final f in ['Inter']) {
      await (FontLoader(
        f,
      )..addFont(rootBundle.load('assets/fonts/$f.ttf'))).load();
    }
    await (FontLoader('Jellee')..addFont(
          rootBundle.load('assets/fonts/Jellee_1223/TTF/Jellee-Bold.ttf'),
        ))
        .load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  const profile = {
    'firstName': '  Priya  ',
    'postcode': '2022',
    'about': {'gender': 'Woman', 'ageRange': '25–34'},
    'preferences': {'useInReports': true},
  };
  const contact = {
    'mobile': '0400 111 222',
    'emergencyContact': {'name': ' Sam ', 'mobile': '0400 333 444'},
  };
  Future<void> show(
    WidgetTester tester,
    int step, {
    Size size = const Size(393, 852),
    double scale = 1,
    Future<void> Function(Map<String, dynamic>)? save,
    VoidCallback? skip,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: rallyTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ProfileStep(
                key: ValueKey(step),
                step: step,
                profile: profile,
                contact: contact,
                onSave: save ?? (_) async {},
                onSkip: skip ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('preferred name, helper and postcode note retain existing keys', (
    t,
  ) async {
    await show(t, 1);
    expect(find.text('Preferred name'), findsWidgets);
    expect(find.text('What should we call you?'), findsOneWidget);
    expect(find.byKey(const Key('firstName')), findsOneWidget);
    expect(find.textContaining('We use your postcode'), findsOneWidget);
  });
  testWidgets(
    'two question buttons have topic semantics and a dismissible full-width sheet',
    (t) async {
      await show(t, 2);
      final handle = t.ensureSemantics();

      expect(find.text('Why we ask'), findsNWidgets(2));
      expect(find.bySemanticsLabel('Why we ask: Gender'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Why we ask: Cultural background'),
        findsOneWidget,
      );
      await t.tap(find.text('Why we ask').first);
      await t.pumpAndSettle();
      expect(find.text('Got it'), findsOneWidget);
      expect(find.textContaining('express permission'), findsOneWidget);
      await t.tap(find.text('Got it'));
      await t.pumpAndSettle();
      expect(find.text('Got it'), findsNothing);
      handle.dispose();
    },
  );
  testWidgets('support note is gentle and can open the Help tab safely', (
    t,
  ) async {
    await t.pumpWidget(
      ParticipantApp(
        repository: FakeParticipantRepository(),
        initialPage: 'profile4',
        mapTilesEnabled: false,
        cameraEnabled: false,
      ),
    );
    await t.pumpAndSettle();
    expect(
      find.text(
        'Optional. Answer only what feels okay. You can skip this step.',
      ),
      findsOneWidget,
    );
    expect(find.text('Skip this step'), findsOneWidget);
    await t.tap(
      find.text('Doing it tough? Support is always in the Help tab.'),
    );
    await t.pumpAndSettle();
    expect(find.text('A little help\ngoes a long way.'), findsOneWidget);
  });
  testWidgets('three reassurance rows precede four toggles in the same order', (
    t,
  ) async {
    await show(t, 5);
    expect(find.byType(AboutNoteRow), findsNWidgets(3));
    final switches = t
        .widgetList<SwitchListTile>(find.byType(SwitchListTile))
        .toList();
    expect(switches.length, 4);
    expect(switches.map((s) => (s.title as Text).data).toList(), [
      'Use my answers in reports',
      'Wellbeing check-ins',
      'Show me in “Who’s counted in”',
      'News and fundraising emails',
    ]);
    expect(
      find.text('You can change these choices in your profile.'),
      findsNothing,
    );
    expect(
      t.getTopLeft(find.byType(AboutNoteRow).last).dy,
      lessThan(t.getTopLeft(find.byType(SwitchListTile).first).dy),
    );
  });
  testWidgets(
    'emergency contact order and optional/skip copy have no duplicate privacy paragraphs',
    (t) async {
      var skipped = false;
      await show(t, 6, skip: () => skipped = true);
      expect(find.text('Someone we can call, just in case'), findsOneWidget);
      expect(find.text('Optional'), findsOneWidget);
      expect(
        find.text('Optional. Share what feels right for you.'),
        findsNothing,
      );
      expect(find.textContaining('Private. Only you'), findsOneWidget);
      expect(
        t.getTopLeft(find.byKey(const Key('emergencyName'))).dy,
        lessThan(t.getTopLeft(find.byKey(const Key('emergencyMobile'))).dy),
      );
      expect(
        t.getTopLeft(find.byKey(const Key('emergencyMobile'))).dy,
        lessThan(t.getTopLeft(find.byKey(const Key('mobile'))).dy),
      );
      await t.ensureVisible(find.text('Skip for now'));
      await t.tap(find.text('Skip for now'));
      expect(skipped, true);
    },
  );
  for (final step in [1, 2, 3, 4, 5, 6, 7]) {
    testWidgets('step $step save payload preserves keys and values', (t) async {
      Map<String, dynamic>? payload;
      await show(t, step, save: (p) async => payload = p);
      await t.ensureVisible(find.byKey(const Key('profile-next')));
      await t.tap(find.byKey(const Key('profile-next')));
      await t.pumpAndSettle();
      final expected = switch (step) {
        1 => {'firstName', 'postcode', 'about'},
        2 => {'about'},
        3 => {'about'},
        4 => {'about'},
        5 => {'preferences'},
        6 => {'mobile', 'emergencyContact'},
        7 => {'photoBytes', 'photoSkip'},
        _ => throw StateError('bad test'),
      };
      expect(payload!.keys.toSet(), expected);
      if (step == 1) {
        expect(payload!['firstName'], 'Priya');
        expect(payload!['postcode'], '2022');
      }
      if (step == 6) {
        expect(payload!['mobile'], '+61400111222');
        expect(payload!['emergencyContact'], {
          'name': 'Sam',
          'mobile': '+61400333444',
        });
      }
      if (step == 7) {
        expect(payload!['photoBytes'], null);
        expect(payload!['photoSkip'], true);
      }
    });
  }
  for (final step in [1, 2, 4, 5, 6]) {
    testWidgets(
      'step $step scrolls without overflow at 360x640 and text scale 1.5',
      (t) async {
        await show(t, step, size: const Size(360, 640), scale: 1.5);
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.byKey(const Key('profile-next')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (step == 2) {
          await t.ensureVisible(find.text('Why we ask').first);
          await t.tap(find.text('Why we ask').first);
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          await t.ensureVisible(find.text('Got it'));
          await t.tap(find.text('Got it'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        }
      },
    );
  }
  testWidgets('capture about-you pass 2 screens and open explanation', (
    t,
  ) async {
    for (final step in [1, 2, 4, 5, 6]) {
      await show(t, step);
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/about-you-2/step-$step.png'),
      );
      if (step == 2) {
        await t.tap(find.text('Why we ask').first);
        await t.pumpAndSettle();
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/about-you-2/step-2-why.png'),
        );
        await t.tap(find.text('Got it'));
        await t.pumpAndSettle();
      }
    }
  });
}
