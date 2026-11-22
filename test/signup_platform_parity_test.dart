import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/app.dart';

import 'support/fake_participant.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'Inter',
    )..addFont(rootBundle.load('assets/fonts/Inter.ttf'))).load();
    await (FontLoader('Jellee')..addFont(
          rootBundle.load('assets/fonts/Jellee_1223/TTF/Jellee-Bold.ttf'),
        ))
        .load();
  });
  for (final size in [const Size(393, 852), const Size(800, 1280)]) {
    testWidgets('iOS and Android sign-up screens match at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      try {
        for (final page in [
          'entry',
          'signup',
          'signin',
          for (var i = 1; i <= 7; i++) 'profile$i',
        ]) {
          List<int>? ios;
          for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
            debugDefaultTargetPlatformOverride = platform;
            final repo = FakeParticipantRepository(
              authenticated: page.startsWith('profile'),
            )..hasSignedInBefore = false;
            final key = GlobalKey();
            await tester.pumpWidget(
              RepaintBoundary(
                key: key,
                child: ParticipantApp(
                  repository: repo,
                  initialPage: page,
                  cameraEnabled: false,
                  mapTilesEnabled: false,
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$page / $platform');
            final bytes = await tester.runAsync(() async {
              final image =
                  await (key.currentContext!.findRenderObject()
                          as RenderRepaintBoundary)
                      .toImage(pixelRatio: 1);
              final data = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!.buffer.asUint8List().toList();
              image.dispose();
              return data;
            });
            if (platform == TargetPlatform.iOS) {
              ios = bytes;
            } else {
              expect(
                listEquals(bytes, ios),
                isTrue,
                reason: '$page should retain the iOS design on Android',
              );
            }
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            repo.dispose();
          }
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
