import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum AboutIconKind { question, support, lock, clock, pencil }

class AboutIcon extends StatelessWidget {
  const AboutIcon(this.kind, {super.key});
  final AboutIconKind kind;
  @override
  Widget build(BuildContext context) {
    final paths = switch (kind) {
      AboutIconKind.question => '<circle cx="12" cy="12" r="9"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.4-1 .9-1 1.7M12 17v.01"/>',
      AboutIconKind.support => '<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.6-7 10-7 10z"/><path d="M8 11h2l1.5-2.5 2 4L15 11h1"/>',
      AboutIconKind.lock => '<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
      AboutIconKind.clock =>
        '<circle cx="12" cy="12" r="9"/><path d="M12 12V3M12 12l6.4 4.5"/>',
      AboutIconKind.pencil => '<path d="M4 20l1-4L16 5l3 3L8 19z"/>',
    };
    return SvgPicture.string(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#4d5b80" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">$paths</svg>',
      width: 18,
      height: 18,
      excludeFromSemantics: true,
    );
  }
}

class AboutNoteRow extends StatelessWidget {
  const AboutNoteRow(this.icon, this.text, {super.key});
  final AboutIconKind icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AboutIcon(icon),
      const SizedBox(width: 12),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 15,
            color: Color(0xff4d5b80),
            height: 1.5,
          ),
        ),
      ),
    ],
  );
}
