# Design tokens — brand book v5

## Typography

Two families, defined once in `lib/theme/typography.dart`'s `AppTypography` --
no widget should set `fontFamily`/`fontWeight` directly; use a named style
(`display`, `h1`, `h2`, `subhead`, `body`, `bodyStrong`, `label`, `button`,
`caption`).

- **Jellee** (headlines/display) -- Bold only, the only weight the brand book
  calls for and the only one registered. Font-file identity was confirmed via
  the file's own `name` table (not the filename): family "Jellee", weight
  class 700, no italic.
- **Inter** (subheadings, body, labels, buttons, form text) -- a temporary
  stand-in for Proxima Nova, which hasn't been supplied/licensed yet. Inter
  ships as a single Regular (400) file, so `AppTypography`'s different
  `fontWeight`s on it are synthetic (Flutter faux-bolds a single-weight
  family) until real Proxima Nova weight files arrive. Swapping
  `AppTypography`'s `_bodyFamily` constant is the only change needed then.
- **Proxima Nova Extra Condensed**: supplied files are Fontspring *DEMO*
  fonts with no commercial licence alongside them -- not used or committed
  (gitignored). Real, regular-width, licensed Proxima Nova files (Light 300 /
  Medium 500 / Bold 700 / Extra Bold 800 / Black 900) are still needed.
- `scripts/validate-build.py` fails release/profile builds with a clear
  message if the registered font files are missing; debug/test builds fall
  back to the platform default so tests keep running either way.

## Colours

Exact brand hex values, defined once in `lib/theme/colors.dart`:

| Token | Name | Hex |
|---|---|---|
| `navy` | Nimble Navy | `#001751` |
| `coral` | Rally Red | `#ff4b4c` |
| `pink` | Power Pink | `#ffb7b7` |
| `cream` | Bounce Beige | `#f2eeeb` |
| — | White | `#ffffff` |

Never pure black (`#000000`) -- text and icons use navy. `test/typography_test.dart` asserts this holds across `lib/`.

### Contrast (WCAG AA: 4.5:1 normal text, 3:1 large/bold text or UI graphics)

| Pair | Ratio | Verdict | Where used |
|---|---|---|---|
| navy on cream | 14.67:1 | Pass (normal) | Default body/heading text |
| navy on white | 16.92:1 | Pass (normal) | Panels, inputs |
| white on navy | 16.92:1 | Pass (normal) | Dark screens (`frame(dark: true)`) |
| navy on pink | 10.24:1 | Pass (normal) | Pink banners/panels (see `Panel` below) |
| navy/coral mutual | 5.13:1 | Pass (normal) | Coral-background screens |
| slate on cream | 5.83:1 | Pass (normal) | Secondary/muted body text |
| slate on white | 6.72:1 | Pass (normal) | Secondary/muted body text |
| **coral on cream** | **2.86:1** | **Fails even AA-large (needs 3:1)** | Large/bold display text only, per the brand book's own acknowledgement of this pairing's limits -- never body, labels or small text |
| **pink on coral** | **2.00:1** | **Fail** | Not used as a text/icon-on-background pair anywhere found |
| **grey (#929292) on cream** | **2.70:1** | **Fail** | Not used as a text colour anywhere found (0 occurrences) -- safe, but don't introduce one |
| **pink on cream/white** | **1.43:1 / 1.65:1** | **Fail** | Not used -- every `pink`-coloured text/icon in the app is on a navy background (10.24:1), confirmed by reading each of the 19 call sites |

**Fixed**: `Panel` (in `lib/participant/theme.dart`) previously left its child's text colour to whatever ambient theme default was in scope regardless of the panel's own background -- for `Panel(color: pink, ...)` specifically, that resolved to `slate` on pink (4.07:1, fails AA-normal). `Panel` now defaults its child's text colour based on its own background (navy text, or white on a navy panel), fixing every current and future panel at once rather than patching call sites individually.

### Brand pairings

Red on Beige (large/bold only, see above), Pink on Red (decorative only, not
verified as a text pairing), Red on Navy, Navy on Pink -- all as specified in
the brand book; `brand()`/`Wordmark`'s `light` parameter already encodes
navy-vs-white by background across every place the logo/wordmark appears.

## Logo

`assets/brand/rally4ever_logo.svg` -- the symbol only (no wordmark text),
rendered via `flutter_svg` and tinted with a `ColorFilter` (navy on light
backgrounds, white on dark/coloured ones) in `lib/shared/logo.dart`'s `Logo`.
`Wordmark` pairs it with the "RALLY4EVER" text (Jellee Bold) at a consistent
gap -- the official wordmark artwork (reversed final R, baked-in text) isn't
supplied yet; swap `Wordmark`'s `Row` for that artwork directly once it is,
nothing else should need to change at call sites.

Also used for both platforms' launch screens (centred on Bounce Beige),
rendered to PNG at each required density/scale since native splash screens
can't reference SVG directly. The app icon is unchanged -- it needs a
separate square, padded export and explicit confirmation before changing.

## Copy tone

Sentence case throughout (no Title Case headings, no ALL CAPS except the
"RALLY4EVER"/"4EVER" wordmark lock-ups) -- scanned for ALL-CAPS strings and
Title-Case `title:` patterns outside the wordmark; none found needing a fix.
Friendly, encouraging, no-judgement tone is already the house style (e.g.
"Turn up as you are", "How was your last session?").
