import 'package:flutter/material.dart';

import 'colors.dart';

/// Every text style used anywhere in the app, named, so no widget needs to
/// set `fontFamily`/`fontWeight` directly. Two families only:
///
/// - **Jellee** (display/headlines) -- the brand's only available weight is
///   Bold; it's the only one registered in pubspec.yaml and the only one
///   used here.
/// - **Inter** (subheadings, body, labels, buttons, form text) -- a
///   temporary stand-in for Proxima Nova, which hasn't been supplied/
///   licensed yet. Inter is bundled as a single Regular (400) file, so the
///   different `fontWeight`s below are synthetic (Flutter faux-bolds a
///   single-weight family) until real Proxima Nova weight files replace
///   it -- changing [_bodyFamily] to the real family name is the only edit
///   needed then; every style below stays the same otherwise.
abstract final class AppTypography {
  static const _displayFamily = 'Jellee';
  static const _bodyFamily = 'Inter';

  /// Largest display text (e.g. the welcome carousel headlines).
  static const display = TextStyle(
    fontFamily: _displayFamily,
    fontWeight: FontWeight.w700,
    fontSize: 34,
    height: 1.05,
    color: navy,
    letterSpacing: -1,
  );

  /// Section/page-level headline (e.g. "Play near you").
  static const h1 = TextStyle(
    fontFamily: _displayFamily,
    fontWeight: FontWeight.w700,
    fontSize: 27,
    height: 1.12,
    color: navy,
    letterSpacing: -.6,
  );

  /// Card/app-bar-title-level headline.
  static const h2 = TextStyle(
    fontFamily: _displayFamily,
    fontWeight: FontWeight.w700,
    fontSize: 20,
    color: navy,
  );

  /// A smaller, secondary heading under an h1/h2.
  static const subhead = TextStyle(
    fontFamily: _bodyFamily,
    fontWeight: FontWeight.w500,
    fontSize: 16,
    color: navy,
  );

  /// Default paragraph/body copy.
  static const body = TextStyle(
    fontFamily: _bodyFamily,
    fontWeight: FontWeight.w300,
    fontSize: 14,
    height: 1.5,
    color: navy,
  );

  /// Body copy that needs emphasis without becoming a heading.
  static const bodyStrong = TextStyle(
    fontFamily: _bodyFamily,
    fontWeight: FontWeight.w700,
    fontSize: 14,
    height: 1.5,
    color: navy,
  );

  /// Form field labels, chip labels, small UI labels.
  static const label = TextStyle(
    fontFamily: _bodyFamily,
    fontWeight: FontWeight.w500,
    fontSize: 12,
    color: navy,
  );

  /// Button text. Colour is set per-button (white on a filled red/navy
  /// button, navy on an outlined one) -- this carries the family/weight/size
  /// only.
  static const button = TextStyle(
    fontFamily: _bodyFamily,
    fontWeight: FontWeight.w700,
    fontSize: 14,
  );

  /// Timestamps, helper text, fine print.
  static const caption = TextStyle(
    fontFamily: _bodyFamily,
    fontWeight: FontWeight.w300,
    fontSize: 12,
    color: navy,
  );
}
