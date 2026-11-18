import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/access.dart';
import 'package:rally4ever/participant/forms.dart';

void main() {
  group('migrateAbout', () {
    test('converts legacy single-value fields to arrays of option keys', () {
      final migrated = migrateAbout({
        'currentActivity': 'Working',
        'referral': 'Friend',
        'culturalBackground': 'Born outside Australia',
      });
      expect(migrated['occupation'], ['working']);
      expect(migrated['heardAbout'], ['friend']);
      expect(migrated['culturalBackground'], ['born_outside_australia']);
      expect(migrated.containsKey('currentActivity'), false);
      expect(migrated.containsKey('referral'), false);
      expect(migrated['heardAboutOther'], '');
    });
    test('renames referralOther to heardAboutOther', () {
      final migrated = migrateAbout({
        'referral': 'Other',
        'referralOther': 'Saw a flyer',
      });
      expect(migrated['heardAbout'], ['other']);
      expect(migrated['heardAboutOther'], 'Saw a flyer');
      expect(migrated.containsKey('referralOther'), false);
    });
    test('an unrecognized legacy label becomes an empty array, not a guess', () {
      final migrated = migrateAbout({'currentActivity': 'Something new'});
      expect(migrated['occupation'], <String>[]);
    });
    test('already-current data and an empty map pass through unchanged', () {
      expect(migrateAbout({}), {
        'occupation': <String>[],
        'heardAbout': <String>[],
        'heardAboutOther': '',
        'culturalBackground': <String>[],
      });
      final current = migrateAbout({
        'occupation': ['studying', 'prefer_not_to_say'],
      });
      expect(migrateAbout(current), current);
    });
  });

  group('normalizeAustralianMobile', () {
    test('converts a local 0-prefixed number to E.164', () {
      expect(normalizeAustralianMobile('0400 000 000'), '+61400000000');
    });
    test('leaves an already-E.164 number alone', () {
      expect(normalizeAustralianMobile('+61400000000'), '+61400000000');
    });
    test('an empty or blank input stays empty', () {
      expect(normalizeAustralianMobile(''), '');
      expect(normalizeAustralianMobile('   '), '');
    });
  });

  group('usersToCsv', () {
    test('includes admin-only contact fields and readable option labels', () {
      final csv = usersToCsv([
        {
          'email': 'a@example.test',
          'firstName': 'Alex',
          'role': 'participant',
          'coachEnabled': false,
          'hasPhoto': true,
          'about': {
            'occupation': ['studying', 'prefer_not_to_say'],
          },
          'mobile': '+61400000000',
          'emergencyContact': {'name': 'Sam, Jr', 'mobile': '+61400000001'},
        },
      ]);
      final lines = csv.split('\n');
      expect(lines.first, contains('emergencyContactMobile'));
      expect(lines[1], contains('"Sam, Jr"'));
      expect(lines[1], contains('Studying; Prefer not to say'));
      expect(lines[1], contains('+61400000000'));
    });
  });
}
