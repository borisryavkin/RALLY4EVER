import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/theme/typography.dart';

void main() {
  test('display/headline styles resolve to Jellee', () {
    for (final style in [
      AppTypography.display,
      AppTypography.h1,
      AppTypography.h2,
    ]) {
      expect(style.fontFamily, 'Jellee');
    }
  });
  test('body/label/button/caption styles resolve to Inter (the Proxima Nova stand-in)', () {
    for (final style in [
      AppTypography.subhead,
      AppTypography.body,
      AppTypography.bodyStrong,
      AppTypography.label,
      AppTypography.button,
      AppTypography.caption,
    ]) {
      expect(style.fontFamily, 'Inter');
    }
  });
  test('no colour in lib/ is pure black (#000000) -- navy is the text/icon colour', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final content = file.readAsStringSync();
      if (RegExp(
            r'Colors\.black\b|0x[fF]{2}000000',
          ).hasMatch(content)) {
        offenders.add(file.path);
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: 'Pure black found in: ${offenders.join(', ')} -- use navy instead',
    );
  });
  test('no unapproved hardcoded font family in lib/ -- only Jellee/Inter/monospace/MaterialIcons', () {
    final allowed = {'Jellee', 'Inter', 'monospace', 'MaterialIcons'};
    final offenders = <String>[];
    final pattern = RegExp(r'''fontFamily:\s*['"]([^'"]+)['"]''');
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      for (final match in pattern.allMatches(file.readAsStringSync())) {
        final family = match.group(1);
        if (!allowed.contains(family)) {
          offenders.add('${file.path}: $family');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join(', '));
  });
}
