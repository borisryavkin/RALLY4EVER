const requiredAgreementIds = [
  'conduct',
  'waiver',
  'data-collection',
  'photo-release',
];

List<Map<String, dynamic>> formSources(Map<String, dynamic> form) =>
    (form['sources'] as List?)?.cast<Map<String, dynamic>>() ?? [form];

/// Three presented forms; preserve both approved conduct/waiver texts and
/// their existing versioned consent IDs without rewriting legal wording.
List<Map<String, dynamic>> agreementGroups(List<Map<String, dynamic>> forms) =>
    [
      for (final group in [
        ('conduct', 'Code of Conduct', ['conduct', 'waiver']),
        ('data-collection', 'Data Collection', ['data-collection']),
        ('photo-release', 'Photo Release', ['photo-release']),
      ])
        if (forms.any((f) => group.$3.contains(f['id'])))
          (() {
            final sources = [
              for (final id in group.$3) ...forms.where((f) => f['id'] == id),
            ];
            return <String, dynamic>{
              ...sources.first,
              'id': group.$1,
              'title': group.$2,
              'body': sources
                  .map((f) => '${f['body'] ?? f['content'] ?? ''}')
                  .join('\n\n'),
              'required': true,
              'sources': sources,
            };
          })(),
    ];
