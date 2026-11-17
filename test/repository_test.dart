import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rally4ever/participant/repository.dart';

FirebaseFunctionsException exception(String message, {String code = 'internal'}) =>
    FirebaseFunctionsException(message: message, code: code);

void main() {
  test('known short business messages from functions/src pass through unchanged', () {
    for (final message in [
      'Sign in to continue',
      'Verify your email to continue',
      'You are already checked in',
      'Event is not public',
      'Unable to complete the request; please retry',
    ]) {
      expect(friendlyFunctionsError(exception(message)), message);
    }
  });

  test(
    'raw platform-level diagnostics (token/claim verification, long or multi-line text) become one friendly sentence',
    () {
      const fallback = 'Something went wrong completing that action. Please try again.';
      // Regression case: the exact shape of the "aud" claim incident this app hit
      // in production when Cloud Functions verified a real ID token against a
      // hardcoded demo project id.
      expect(
        friendlyFunctionsError(
          exception(
            'Firebase ID token has incorrect "aud" claim. Expected '
            '"demo-rally4ever" but got "rally4ever-3adaf".',
          ),
        ),
        fallback,
      );
      expect(
        friendlyFunctionsError(exception('A' * 141)),
        fallback,
      );
      expect(
        friendlyFunctionsError(exception('line one\nline two')),
        fallback,
      );
      expect(
        friendlyFunctionsError(
          FirebaseFunctionsException(message: '', code: 'internal'),
        ),
        fallback,
      );
    },
  );
}
