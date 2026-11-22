import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/app_bootstrap.dart';
import 'package:rally4ever/data/staging_backend.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/repository.dart';

import 'support/fake_participant.dart';

class FixtureFirebaseApp extends Fake implements FirebaseApp {
  FixtureFirebaseApp({this.bucket});
  final String? bucket;
  @override
  void registerService<T extends FirebaseService>(
    T service, {
    Future<void> Function(T service)? dispose,
  }) {}
  @override
  String get name => 'startup-fixture-${bucket ?? 'no-bucket'}';
  @override
  FirebaseOptions get options => FirebaseOptions(
    apiKey: 'fixture',
    appId: 'fixture',
    messagingSenderId: 'fixture',
    projectId: 'demo-rally4ever',
    storageBucket: bucket,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'missing optional Storage bucket cannot disable staging sign-in',
    () async {
      final app = FixtureFirebaseApp();
      // Reproduce the SDK failure which previously happened during connect().
      expect(
        () => FirebaseStorage.instanceFor(app: app),
        throwsA(isA<FirebaseException>()),
      );
      final backend = StagingBackend.fromInitializedApp(app);
      final repo = FirebaseParticipantRepository(backend);
      await repo
          .restore(); // Signed-out startup must not touch any remote service.
      expect(repo.enabled, isTrue);
      expect(repo.uid, isNull);
      expect(backend.auth.app, same(app));
      expect(backend.firestore.app, same(app));
      expect(
        () => backend.storage,
        throwsA(
          isA<FirebaseException>().having(
            (e) => e.code,
            'code',
            'not-configured',
          ),
        ),
      );
      repo.dispose();
    },
  );

  test(
    'configured Storage stays available without making a network request',
    () {
      final backend = StagingBackend.fromInitializedApp(
        FixtureFirebaseApp(bucket: 'demo-rally4ever.appspot.com'),
      );
      expect(backend.storage.bucket, 'demo-rally4ever.appspot.com');
    },
  );

  testWidgets('backend failure stays visible and retry reconnects sign-in', (
    tester,
  ) async {
    var attempts = 0;
    await tester.pumpWidget(
      AppBootstrap(
        connect: () async {
          attempts++;
          if (attempts < 3) {
            throw FirebaseException(
              plugin: 'firebase_core',
              code: 'startup-fixture',
            );
          }
          return FakeParticipantRepository(authenticated: false);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('We couldn’t start sign-in'), findsOneWidget);
    expect(
      find.text('Support code: firebase_core/startup-fixture'),
      findsOneWidget,
    );
    expect(find.byType(ParticipantApp), findsNothing);
    expect(find.textContaining('Start the local emulators'), findsNothing);
    await tester.tap(find.byKey(const Key('retry-backend')));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.byKey(const Key('retry-backend')), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-backend')));
    await tester.pumpAndSettle();
    expect(attempts, 3);
    expect(find.byType(ParticipantApp), findsOneWidget);
    expect(find.byKey(const Key('retry-backend')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'legacy registerIdentity rejects hint then accepts original contract',
    () async {
      final payloads = <Record>[];
      final result = await registerIdentityCompatible((name, data) async {
        expect(name, 'registerIdentity');
        payloads.add(Map.of(data));
        if (data.containsKey('firstNameHint')) {
          throw const FunctionsCallError(
            'invalid-argument',
            'unknown-field',
            'Unexpected input field',
          );
        }
        return {
          'uid': 'existing-user',
          'created': false,
          'requiresSignIn': false,
        };
      }, firstNameHint: ' Boris ');
      expect(payloads, [
        {'firstNameHint': 'Boris'},
        {},
      ]);
      expect(result, {
        'uid': 'existing-user',
        'created': false,
        'requiresSignIn': false,
      });
    },
  );

  test('current registerIdentity retains name prefill without retry', () async {
    var calls = 0;
    final result = await registerIdentityCompatible((name, data) async {
      calls++;
      expect(data, {'firstNameHint': 'Priya'});
      return {'uid': 'new-user', 'created': true};
    }, firstNameHint: 'Priya');
    expect(calls, 1);
    expect(result['created'], true);
  });

  test(
    'no display name sends only the original verified-token contract',
    () async {
      var calls = 0;
      await registerIdentityCompatible((name, data) async {
        calls++;
        expect(data, isEmpty);
        return {'uid': 'existing-user'};
      });
      expect(calls, 1);
    },
  );

  test('compatibility does not retry identity, permission, quota or network failures', () async {
    for (final error in [
      const FunctionsCallError(
        'failed-precondition',
        'identity-conflict',
        'Resolve identity',
      ),
      const FunctionsCallError(
        'permission-denied',
        'email-mismatch',
        'Verify account',
      ),
      const FunctionsCallError('resource-exhausted', 'rate-limit', 'Try later'),
      const FunctionsCallError('unavailable', null, 'Offline'),
      const FunctionsCallError(
        'invalid-argument',
        'invalid-input',
        'Invalid name',
      ),
    ]) {
      var calls = 0;
      await expectLater(
        registerIdentityCompatible((name, data) async {
          calls++;
          throw error;
        }, firstNameHint: 'Boris'),
        throwsA(same(error)),
      );
      expect(calls, 1);
    }
  });

  testWidgets(
    'legacy function during startup reaches sign-in instead of backend failure',
    (tester) async {
      await tester.pumpWidget(
        AppBootstrap(
          connect: () async {
            await registerIdentityCompatible((name, data) async {
              if (data.isNotEmpty) {
                throw const FunctionsCallError(
                  'invalid-argument',
                  'unknown-field',
                  'Unexpected input field',
                );
              }
              return {'uid': 'existing-user', 'requiresSignIn': false};
            }, firstNameHint: 'Boris');
            return FakeParticipantRepository(authenticated: false);
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ParticipantApp), findsOneWidget);
      expect(find.text('We couldn’t start sign-in'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'function startup support code identifies failure without raw message',
    (tester) async {
      await tester.pumpWidget(
        AppBootstrap(
          connect: () async {
            throw const FunctionsCallError(
              'invalid-argument',
              'unknown-field',
              'Private backend diagnostic',
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Support code: functions/invalid-argument/unknown-field'),
        findsOneWidget,
      );
      expect(find.textContaining('Private backend diagnostic'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
