import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../participant/theme.dart';

/// The Rally4ever symbol (assets/brand/rally4ever_logo.svg -- a single path,
/// no wordmark baked in) tinted with a ColorFilter. Height is the only size
/// knob; width follows the SVG's own ~1.31:1 aspect ratio automatically.
class Logo extends StatelessWidget {
  const Logo({super.key, this.height = 30, this.color = navy});
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/brand/rally4ever_logo.svg',
    height: height,
    colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
  );
}

/// Symbol + "RALLY4EVER" wordmark text, vertically centred with a
/// consistent gap -- the brand's official wordmark artwork isn't available
/// yet (assets/brand/rally4ever_wordmark.svg), so this keeps the existing
/// typed text next to the real symbol. Swap this for the artwork directly
/// once it's supplied; nothing else should need to change at call sites.
class Wordmark extends StatelessWidget {
  const Wordmark({
    super.key,
    this.height = 30,
    this.color = navy,
    this.textStyle,
  });
  final double height;
  final Color color;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Logo(height: height, color: color),
      const SizedBox(width: 10),
      Text(
        'RALLY4EVER',
        style:
            textStyle ??
            TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: height * .6,
              letterSpacing: .5,
            ),
      ),
    ],
  );
}
