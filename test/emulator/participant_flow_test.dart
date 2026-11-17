import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/data/emulator_backend.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/repository.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'register_plugins.dart';

class CourtRepository extends FirebaseParticipantRepository {
  CourtRepository(super.backend);
  // A simulated GPS fix; every other request uses the real local emulators.
  @override
  Future<Record> location() async => {'lat': -33.8926, 'lng': 151.2511};
}

void main() {
  testWidgets(
    'emulator participant intent -> scan -> coach decision -> live confirmed UI',
    (tester) async {
      try {
        final originalErrorHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          debugPrint('E2E rendering error: ${details.exceptionAsString()}');
          originalErrorHandler?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalErrorHandler);
        registerTestPlugins();
        tz.initializeTimeZones();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        late EmulatorBackend backend;
        late CourtRepository repo;
        late FirebaseApp coachApp;
        late FirebaseFunctions coachFunctions;
        late String qr;
        await tester.runAsync(() async {
          backend = await EmulatorBackend.connect(enabled: true);
          debugPrint("E2E: emulator backend ready");
          repo = CourtRepository(backend);
          await repo.signIn(
            'member10@example.test',
            'Emulator-only-Password-123!',
          );
          debugPrint('E2E: participant authenticated');
          coachApp = await Firebase.initializeApp(
            name: 'coach-e2e',
            options: const FirebaseOptions(
              apiKey: 'demo-api-key',
              appId: '1:123456789:web:coach-test',
              messagingSenderId: '123456789',
              projectId: 'demo-rally4ever',
              authDomain: 'demo-rally4ever.firebaseapp.com',
            ),
          );
          final auth = FirebaseAuth.instanceFor(app: coachApp);
          await auth.useAuthEmulator('127.0.0.1', 9099);
          await auth.signInWithEmailAndPassword(
            email: 'dan@rally4ever.org',
            password: 'Emulator-only-Password-123!',
          );
          coachFunctions = FirebaseFunctions.instanceFor(
            app: coachApp,
            region: 'australia-southeast1',
          );
          coachFunctions.useFunctionsEmulator('127.0.0.1', 5001);
          qr =
              ((await coachFunctions
                              .httpsCallable('rotateEventSecret')
                              .call<dynamic>({'eventId': 'event-1'}))
                          .data
                      as Map)['url']
                  as String;
        });
        Future<void> until(bool Function() condition) async {
          for (var attempt = 0; attempt < 150; attempt++) {
            if (condition()) return;
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await tester.pump();
          }
          fail('Timed out; repository error: ${repo.streamError}');
        }

        await until(() => repo.ready);
        await tester.pumpWidget(
          ParticipantApp(
            repository: repo,
            initialPage: 'session',
            initialEventId: 'event-1',
            cameraEnabled: false,
          ),
        );
        await tester.pumpAndSettle();
        expect(repo.checkin('event-1'), isNull);
        await tester.tap(find.byKey(const Key('count-me-in')));
        await until(() => repo.countedIn('event-1'));
        expect(repo.checkin('event-1'), isNull);
        await tester.tap(find.byKey(const Key('open-checkin')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('start-scan')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('qr-link')), qr);
        await tester.tap(find.byKey(const Key('use-qr')));
        await until(
          () => find.byKey(const Key('emergencyName')).evaluate().isNotEmpty,
        );
        for (final field in {
          'firstName': 'Sam',
          'mobile': '0400000000',
          'emergencyName': 'Mei',
          'emergencyMobile': '0400000001',
        }.entries) {
          await tester.ensureVisible(find.byKey(Key(field.key)));
          await tester.enterText(find.byKey(Key(field.key)), field.value);
        }
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await until(
          () => find.byKey(const Key('accept-forms')).evaluate().isNotEmpty,
        );
        await tester.ensureVisible(find.byKey(const Key('accept-forms')));
        await tester.tap(find.byKey(const Key('accept-forms')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('sign-and-checkin')));
        await until(
          () =>
              repo.checkin('event-1')?['status'] == 'pending' &&
              find.text('Pending confirmation').evaluate().isNotEmpty,
        );
        expect(find.text('Pending confirmation'), findsOneWidget);
        await tester.runAsync(() async {
          await coachFunctions.httpsCallable('coachDecision').call<dynamic>({
            'eventId': 'event-1',
            'uid': 'participant-10',
            'decision': 'confirm',
          });
        });
        await until(
          () =>
              repo.checkin('event-1')?['status'] == 'confirmed' &&
              find.text('Confirmed').evaluate().isNotEmpty,
        );
        await tester.pump();
        final renderingIssue = tester.takeException();
        if (renderingIssue != null) {
          throw StateError('Rendering issue: $renderingIssue');
        }
        expect(find.text('Confirmed'), findsOneWidget);
        expect(find.text('You’re in,\nSam'), findsOneWidget);
        expect(repo.countedIn('event-1'), true);
        debugPrint('E2E: live confirmed UI verified');
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await repo.signOut();
          repo.dispose();
          await FirebaseAuth.instanceFor(app: coachApp).signOut();
          await coachApp.delete();
          await backend.app.delete();
        });
      } catch (error, stack) {
        debugPrint('E2E failure: $error\n$stack');
        rethrow;
      }
    },
    skip: !const bool.fromEnvironment('USE_FIREBASE_EMULATORS'),
  );
}
