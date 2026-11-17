import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/catalogue.dart';
import 'package:rally4ever/participant/catalogue_admin.dart';
import 'package:rally4ever/participant/repository.dart';
import 'package:rally4ever/participant/theme.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'support/fake_participant.dart';

Record program({
  String id = 'bondi',
  String status = 'active',
  String state = 'NSW',
  String sport = 'tennis',
}) => {
  'id': id,
  'name': id == 'perth' ? 'Perth social pickleball' : 'Bondi community tennis',
  'status': status,
  'sport': sport,
  'venue': {
    'name': 'Community courts',
    'address': 'Park Parade',
    'suburb': id == 'perth' ? 'Perth' : 'Bondi Junction',
    'postcode': id == 'perth' ? '6000' : '2022',
    'state': state,
    'lat': -33.8926,
    'lng': 151.2511,
  },
  'timezone': 'Australia/Sydney',
  'scheduleText': 'Tuesdays during school terms',
  'coachUids': ['coach-1'],
  'coachNames': ['Dan'],
  'notes': 'Bring water. Equipment provided.',
  'photoUrl': '',
  'capacity': 12,
  'registrationStatus': 'open',
  'revision': 1,
};

class AdminRepo extends FakeParticipantRepository {
  Record? saved;
  @override
  Future<Record> call(String name, Record data) async {
    if (name == 'listUsers') {
      return {
        'users': [
          {
            'uid': 'coach-1',
            'email': 'dan@example.test',
            'role': 'coach',
            'coachEnabled': true,
            'mergedInto': null,
          },
        ],
        'cursor': null,
      };
    }
    if (name == 'listPrograms') return {'programs': programs};
    if (name == 'saveProgram') {
      saved = data;
      return {'programId': 'created'};
    }
    return super.call(name, data);
  }
}

void main() {
  setUpAll(() async {
    tz.initializeTimeZones();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    for (final name in ['Inter', 'Figtree']) {
      await (FontLoader(
        name,
      )..addFont(rootBundle.load('assets/fonts/$name.ttf'))).load();
    }
  });
  Future<void> show(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: rallyTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'availability separates full, closed, unlimited, remaining and cancelled',
    () {
      expect(
        availability({'capacity': 2, 'bookedCount': 1}),
        '1 spot available',
      );
      expect(availability({'capacity': 2, 'bookedCount': 2}), 'Full');
      expect(availability({'capacity': null}), 'Spots available');
      expect(acceptsReservations({'status': 'cancelled'}), isFalse);
      expect(acceptsReservations({'registrationStatus': 'closed'}), isFalse);
      expect(
        venuePoint({
          'venue': {'lat': null, 'lng': 1},
        }),
        isNull,
      );
      expect(
        venuePoint({
          'venue': {'lat': double.nan, 'lng': 1},
        }),
        isNull,
      );
    },
  );
  testWidgets('catalogue filters by postcode, sport, state and archive', (
    tester,
  ) async {
    final repo = FakeParticipantRepository()
      ..catalogueReady = true
      ..programs = [
        program(),
        program(id: 'perth', state: 'WA', sport: 'pickleball'),
        program(id: 'old', status: 'archived'),
      ];
    await show(tester, ProgramBrowser(repository: repo, onSelect: (_) {}));
    expect(find.text('Perth social pickleball'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('program-search')), '2022');
    await tester.pumpAndSettle();
    expect(find.text('Perth social pickleball'), findsNothing);
    await tester.enterText(find.byKey(const Key('program-search')), '');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pickleball'));
    await tester.pumpAndSettle();
    expect(find.text('Bondi community tennis'), findsNothing);
    await tester.tap(find.text('All').first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(SwitchListTile));
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Perth social pickleball'), findsNothing);
    expect(find.text('Bondi community tennis'), findsOneWidget);
  });
  testWidgets(
    'program detail shows coaches, notes and real calendar sessions',
    (tester) async {
      final repo = FakeParticipantRepository(counted: false)
        ..catalogueReady = true
        ..programs = [program()];
      repo.events.first.addAll({
        'programId': 'bondi',
        'catalogueManaged': true,
        'capacity': 1,
        'bookedCount': 1,
        'registrationStatus': 'open',
      });
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'programs',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('View program & dates').first);
      await tester.pumpAndSettle();
      expect(find.text('Dan'), findsOneWidget);
      expect(find.text('Bring water. Equipment provided.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const Key('event-event-1')).hitTestable(),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('event-event-1')).hitTestable());
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('count-me-in')),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Full'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'catalogue map shows program marker without requiring a dated session',
    (tester) async {
      final repo = FakeParticipantRepository()
        ..catalogueReady = true
        ..programs = [program()]
        ..events = [];
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'map',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1 programs on the map'), findsOneWidget);
      expect(find.byTooltip('Bondi community tennis'), findsOneWidget);
      await tester.tap(find.byTooltip('Bondi community tennis'));
      await tester.pumpAndSettle();
      expect(find.text('Your regular rally'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
  testWidgets(
    'catalogue error is clear and does not masquerade as zero programs',
    (tester) async {
      final repo = FakeParticipantRepository()
        ..catalogueReady = true
        ..catalogueError = 'permission-denied';
      await show(tester, ProgramBrowser(repository: repo, onSelect: (_) {}));
      expect(
        find.text('Programs could not load. Please try again.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'No published programs match your search. Try another suburb or state.',
        ),
        findsNothing,
      );
    },
  );
  testWidgets(
    'admin program editor sends validated fields and a required audit reason',
    (tester) async {
      final repo = AdminRepo();
      await tester.pumpWidget(
        MaterialApp(
          theme: rallyTheme(),
          home: ProgramEditor(repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in {
        'name': 'Community rally',
        'venue': 'Park courts',
        'suburb': 'Newtown',
        'schedule': 'Wednesdays, 10–11am',
        'reason': 'Reviewed schedule with coach',
      }.entries) {
        final f = find.byKey(Key('program-${entry.key}'));
        await tester.scrollUntilVisible(
          f,
          250,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.enterText(f, entry.value);
      }
      await tester.scrollUntilVisible(
        find.text('Save program'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Save program'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save program'));
      await tester.pumpAndSettle();
      expect(repo.saved?['reason'], 'Reviewed schedule with coach');
      expect((repo.saved?['program'] as Map)['status'], 'draft');
    },
  );
  testWidgets('capture live catalogue and program calendar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeParticipantRepository(counted: false)
      ..catalogueReady = true
      ..programs = [
        program(),
        program(id: 'perth', state: 'WA', sport: 'pickleball'),
      ];
    repo.events.first.addAll({
      'programId': 'bondi',
      'catalogueManaged': true,
      'capacity': 12,
      'bookedCount': 9,
      'registrationStatus': 'open',
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('catalogue-capture'),
        child: ParticipantApp(
          repository: repo,
          initialPage: 'programs',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('catalogue-capture')),
      matchesGoldenFile('goldens/catalogue-programs.png'),
    );
    await tester.tap(find.text('View program & dates').first);
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('catalogue-capture')),
      matchesGoldenFile('goldens/catalogue-calendar.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('capture admin catalogue management', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = AdminRepo()
      ..programs = [
        program(),
        program(id: 'perth', state: 'WA', sport: 'pickleball'),
      ];
    repo.profile['role'] = 'admin';
    repo.claimRole = 'admin';
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('admin-catalogue-capture'),
        child: ParticipantApp(
          repository: repo,
          initialPage: 'adminCatalogue',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('admin-catalogue-capture')),
      matchesGoldenFile('goldens/catalogue-admin.png'),
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'a restored member uses their program postcode instead of the Sydney default',
    (tester) async {
      final perth = program(id: 'perth', state: 'WA', sport: 'pickleball');
      (perth['venue'] as Map).addAll(<String, Object>{'lat': -31.95, 'lng': 115.86});
      final repo = FakeParticipantRepository()
        ..catalogueReady = true
        ..programs = [program(), perth]
        ..events = [];
      repo.profile['postcode'] = '6000';
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'map',
          cameraEnabled: false,
          mapTilesEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Perth 6000'), findsOneWidget);
      expect(
        tester
            .widget<FlutterMap>(find.byType(FlutterMap))
            .options
            .initialCenter
            .latitude,
        closeTo(-31.95, .001),
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
