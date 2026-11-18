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
}
