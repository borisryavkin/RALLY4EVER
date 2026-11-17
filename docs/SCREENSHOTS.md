# Screenshot review

[Open the full gallery](screenshots/index.html). All captures are actual Flutter widget renders at 390 × 844 using synthetic fixture data. They are not generated mockups.

Bundled Inter/Figtree and Material icons are loaded. Camera preview and external basemap tiles are disabled only in capture tests; normal runs use the real scanner/OSM. The live Chrome emulator test separately verifies the complete RSVP-to-confirmed journey with real local services and a simulated GPS fix.

| Screen | Capture |
| --- | --- |
| A01 admin access | [PNG](screenshots/participant/A01-admin-access.png) |
| A02 coach view | [PNG](screenshots/participant/A02-coach-view.png) |
| S01 intro program | [PNG](screenshots/participant/S01-intro-program.png) |
| S02 intro people | [PNG](screenshots/participant/S02-intro-people.png) |
| S03 intro wellbeing | [PNG](screenshots/participant/S03-intro-wellbeing.png) |
| S04 account | [PNG](screenshots/participant/S04-account.png) |
| S05 profile basics | [PNG](screenshots/participant/S05-profile-basics.png) |
| S06 profile inclusion | [PNG](screenshots/participant/S06-profile-inclusion.png) |
| S07 profile research | [PNG](screenshots/participant/S07-profile-research.png) |
| S08 profile wellbeing | [PNG](screenshots/participant/S08-profile-wellbeing.png) |
| S09 profile consent | [PNG](screenshots/participant/S09-profile-consent.png) |
| S10 home counted in | [PNG](screenshots/participant/S10-home-counted-in.png) |
| S11 map | [PNG](screenshots/participant/S11-map.png) |
| S12 session | [PNG](screenshots/participant/S12-session.png) |
| S13 counted in people | [PNG](screenshots/participant/S13-counted-in-people.png) |
| S14 checkin not open | [PNG](screenshots/participant/S14-checkin-not-open.png) |
| S15 qr scan | [PNG](screenshots/participant/S15-qr-scan.png) |
| S16 before session | [PNG](screenshots/participant/S16-before-session.png) |
| S17 current agreements | [PNG](screenshots/participant/S17-current-agreements.png) |
| S18 waiting | [PNG](screenshots/participant/S18-waiting.png) |
| S19 confirmed | [PNG](screenshots/participant/S19-confirmed.png) |
| S20 no app | [PNG](screenshots/participant/S20-no-app.png) |
| S21 feedback reminder | [PNG](screenshots/participant/S21-feedback-reminder.png) |
| S22 feedback | [PNG](screenshots/participant/S22-feedback.png) |
| S23 profile | [PNG](screenshots/participant/S23-profile.png) |
| S24 help | [PNG](screenshots/participant/S24-help.png) |

Regenerate deliberately with `flutter test --update-goldens test/participant_widgets_test.dart`; regular `flutter test` compares the committed captures and tests behavior. The A-series captures are additional access screens, not claims about the canvas’s later S25+ coach-console designs.
