import 'package:flutter/material.dart';

String formText(Map<String, dynamic> form) =>
    (form['body'] ?? form['content'] ?? '') as String;

/// Styles source lines without trimming or rewriting their displayed text.
class LegalFormText extends StatelessWidget {
  const LegalFormText(this.body, {super.key});
  final String body;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final line in body.split('\n'))
        if (line.isEmpty)
          const SizedBox(height: 8)
        else
          Text(
            line,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              fontWeight: _heading(line) ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
    ],
  );
  bool _heading(String line) =>
      [
        'RALLY4EVER Code of Conduct',
        'RALLY4EVER Waive and Release',
        'Grievance Procedures',
        'Photo Release',
        'Data Collection',
      ].contains(line.trim()) ||
      RegExp(r'^\d+\.\s+[^.]{1,45}$').hasMatch(line);
}
