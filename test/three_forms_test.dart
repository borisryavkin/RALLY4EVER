import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';
import 'package:rally4ever/participant/form_groups.dart';
import 'package:rally4ever/participant/profile_summary.dart';

import 'support/fake_participant.dart';

void main() {
  test('three forms retain verbatim conduct and waiver with all original receipt IDs', () {
    final raw = [
      for (final id in requiredAgreementIds)
        <String, dynamic>{'id': id, 'body': '$id exact text  \n', 'version': 1},
    ];
    final groups = agreementGroups(raw);
    expect(groups.map((f) => f['title']), [
      'Code of Conduct',
      'Data Collection',
      'Photo Release',
    ]);
    expect(
      groups.first['body'],
      'conduct exact text  \n\n\nwaiver exact text  \n',
    );
    expect(formSources(groups.first).map((f) => f['id']), [
      'conduct',
      'waiver',
    ]);
    expect(groups.every((f) => f['required'] == true), true);
  });
  testWidgets(
    'Me has one Sign forms action, no Account button, and signs all three required groups',
    (tester) async {
      tester.view.physicalSize = const Size(393, 3600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = FakeParticipantRepository()..consents = [];
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'profile',
          cameraEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('go-to-account')), findsNothing);
      expect(find.widgetWithText(TextButton, 'Sign forms'), findsOneWidget);
      await tester.tap(find.byKey(const Key('profile-sign-forms')));
      await tester.pumpAndSettle();
      for (final title in [
        'Code of Conduct',
        'Data Collection',
        'Photo Release',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Liability waiver'), findsNothing);
      expect(find.textContaining('Optional:'), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sign-and-checkin')))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byKey(const Key('accept-forms')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('sign-and-checkin')));
      await tester.pumpAndSettle();
      expect(
        repo.consents.map((c) => c['formId']).toSet(),
        requiredAgreementIds.toSet(),
      );
      expect(find.byType(ProfileSummary), findsOneWidget);
    },
  );
  test(
    'signing missing agreements preserves existing receipt timestamps',
    () async {
      final repo = FakeParticipantRepository();
      final existing = {
        ...repo.consents.first,
        'signedAt': 'original-timestamp',
      };
      repo.consents = [existing];
      await repo.signForms(repo.forms);
      expect(repo.consents.length, 4);
      expect(
        repo.consents.singleWhere((c) => c['formId'] == existing['formId']),
        existing,
      );
    },
  );
  testWidgets(
    'missing required release blocks signing instead of silently skipping it',
    (tester) async {
      final repo = FakeParticipantRepository()..consents = [];
      repo.forms.removeWhere((f) => f['id'] == 'photo-release');
      await tester.pumpWidget(
        ParticipantApp(
          repository: repo,
          initialPage: 'agreements',
          cameraEnabled: false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('missing or unpublished'), findsOneWidget);
      expect(find.byKey(const Key('sign-and-checkin')), findsNothing);
    },
  );
}
