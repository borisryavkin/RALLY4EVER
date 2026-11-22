import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/repository.dart';

import 'support/fake_participant.dart';

class AnonymousRepo extends FakeParticipantRepository {
  AnonymousRepo() : super(authenticated: false);
  Record? submitted;
  @override
  Future<Record> call(String name, Record data) async {
    if (name == 'getNoAppForms') {
      return {
        'eventId': 'event-1',
        'name': 'Community pickleball',
        'venue': {'name': 'Courts'},
        'forms': [
          for (final id in [
            'conduct',
            'waiver',
            'data-collection',
            'photo-release',
          ])
            {
              'id': id,
              'title': id,
              'body': 'Test agreement',
              'version': '2026-11-20',
              'required': true,
            },
        ],
      };
    }
    if (name == 'beginNoAppCheckIn') {
      submitted = data;
      return {'status': 'pending'};
    }
    return super.call(name, data);
  }
}

void main() {
  testWidgets(
    'skip personal details sends only anonymous +1 and explicitly accepted agreements',
    (tester) async {
      tester.view.physicalSize = const Size(393, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = AnonymousRepo()
        ..lastNoAppCheckIn = {
          'email': 'private@example.test',
          'firstName': 'Private',
        };
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'noapp',
          cameraEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('toggle-paste-link')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('noapp-qr')),
        'https://rally4ever.org/c/EVENT-1?k=${'a' * 43}',
      );
      await tester.tap(find.byKey(const Key('noapp-use-code')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-session')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('noapp-count-only')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('noapp-email')), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('agreement-continue')))
            .onPressed,
        isNull,
      );
      for (final id in ['conduct', 'data-collection', 'photo-release']) {
        await tester.tap(find.byKey(Key('agree-$id')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('agreement-continue')));
        await tester.pumpAndSettle();
      }
      expect(repo.submitted!['countOnly'], true);
      expect(repo.submitted!.containsKey('email'), false);
      expect(repo.submitted!.containsKey('firstName'), false);
      expect(repo.submitted!.containsKey('mobile'), false);
      expect(repo.submitted!.containsKey('emergencyContact'), false);
      expect(repo.submitted!['signedVersions'], {
        'conduct': '2026-11-20',
        'waiver': '2026-11-20',
        'data-collection': '2026-11-20',
        'photo-release': '2026-11-20',
      });
      final token = repo.submitted!['anonymousToken'];
      expect(token, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(repo.anonymousTokenFor('event-1'), token);
      expect(repo.anonymousTokenFor('event-2'), isNot(token));
      expect(repo.lastNoAppCheckIn['email'], 'private@example.test');
      expect(find.text('Checked in. Waiting for your coach'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
