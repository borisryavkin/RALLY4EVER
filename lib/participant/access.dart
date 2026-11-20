import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'forms.dart'
    show occupationOptions, heardAboutOptions, culturalBackgroundOptions;
import 'repository.dart';
import 'theme.dart';

String _csvField(Object? value) {
  final text = value?.toString() ?? '';
  return text.contains(RegExp(r'[,"\n]'))
      ? '"${text.replaceAll('"', '""')}"'
      : text;
}

String _optionLabels(Record about, String key, Map<String, String> options) =>
    (about[key] as List? ?? const []).map((k) => options[k] ?? k).join('; ');

/// Admin-only: email, role, and about/phone/emergency-contact details come
/// straight from the listUsers callable -- never a direct Firestore read of
/// another participant's profile or private/contact subcollection.
String usersToCsv(List<Record> users) {
  final header = [
    'email',
    'firstName',
    'role',
    'coachEnabled',
    'hasPhoto',
    'occupation',
    'heardAbout',
    'culturalBackground',
    'mobile',
    'emergencyContactName',
    'emergencyContactMobile',
  ];
  final rows = users.map((u) {
    final about = Map<String, dynamic>.from(u['about'] as Map? ?? {});
    final emergency = Map<String, dynamic>.from(
      u['emergencyContact'] as Map? ?? {},
    );
    return [
      u['email'],
      u['firstName'],
      u['role'],
      u['coachEnabled'],
      u['hasPhoto'],
      _optionLabels(about, 'occupation', occupationOptions),
      _optionLabels(about, 'heardAbout', heardAboutOptions),
      _optionLabels(about, 'culturalBackground', culturalBackgroundOptions),
      u['mobile'],
      emergency['name'],
      emergency['mobile'],
    ].map(_csvField).join(',');
  });
  return [header.join(','), ...rows].join('\n');
}

class AdminAccessPanel extends StatefulWidget {
  const AdminAccessPanel({super.key, required this.repository});
  final ParticipantRepository repository;
  @override
  State<AdminAccessPanel> createState() => _AdminAccessPanelState();
}

class _AdminAccessPanelState extends State<AdminAccessPanel> {
  final search = TextEditingController(), reason = TextEditingController();
  List<Record> users = [], events = [];
  String? error, selectedEventId, cursor;
  String roleFilter = 'all';
  Set<String> selectedCoaches = {};
  bool busy = false;
  List<Record> get filteredUsers => roleFilter == 'all'
      ? users
      : users.where((u) => u['role'] == roleFilter).toList();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load({bool more = false}) => run(() async {
    final result = await widget.repository.call('listUsers', {
      'query': search.text.trim(),
      if (more && cursor != null) 'cursor': cursor,
    });
    if (!mounted) return;
    setState(() {
      users = [
        if (more) ...users,
        ...(result['users'] as List).map(
          (u) => Map<String, dynamic>.from(u as Map),
        ),
      ];
      events = (result['events'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      cursor = result['cursor'] as String?;
    });
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'People & permissions',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 10),
      const Text(
        'Coach access comes from an admin-issued claim. A work email alone never grants it.',
      ),
      const SizedBox(height: 20),
      TextField(
        key: const Key('admin-email-search'),
        controller: search,
        keyboardType: TextInputType.emailAddress,
        decoration: const InputDecoration(labelText: 'Find a user by email'),
        onSubmitted: (_) => load(),
      ),
      const SizedBox(height: 10),
      OutlinedButton(
        onPressed: busy ? null : () => load(),
        child: const Text('Search users'),
      ),
      const SizedBox(height: 14),
      TextField(
        key: const Key('access-reason'),
        controller: reason,
        onChanged: (_) => setState(() {}),
        maxLength: 1000,
        decoration: const InputDecoration(
          labelText: 'Reason for access or assignment change',
        ),
      ),
      if (error != null) Panel(color: pink, child: Text(error!)),
      if (busy) const LinearProgressIndicator(),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
        key: const Key('role-filter'),
        initialValue: roleFilter,
        decoration: const InputDecoration(labelText: 'Filter by role'),
        items: const [
          DropdownMenuItem(value: 'all', child: Text('All roles')),
          DropdownMenuItem(value: 'participant', child: Text('Participant')),
          DropdownMenuItem(value: 'coach', child: Text('Coach')),
          DropdownMenuItem(value: 'admin', child: Text('Admin')),
        ],
        onChanged: (v) => setState(() => roleFilter = v ?? 'all'),
      ),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          key: const Key('export-csv'),
          onPressed: users.isEmpty
              ? null
              : () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('CSV export'),
                    content: SizedBox(
                      width: 480,
                      child: SelectableText(
                        usersToCsv(filteredUsers),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Clipboard.setData(
                          ClipboardData(text: usersToCsv(filteredUsers)),
                        ),
                        child: const Text('Copy to clipboard'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                ),
          child: const Text('Export CSV'),
        ),
      ),
      const SizedBox(height: 10),
      for (final user in filteredUsers)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user['email'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  user['firstName'] as String? ?? '',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  [
                    _optionLabels(
                      Map<String, dynamic>.from(user['about'] as Map? ?? {}),
                      'occupation',
                      occupationOptions,
                    ),
                    if (user['hasPhoto'] == true) 'Has photo',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: const TextStyle(fontSize: 11, color: slate),
                ),
                // Admin-only, per listUsers: never shown to coaches or other participants.
                if ((user['mobile'] as String?)?.isNotEmpty == true ||
                    ((user['emergencyContact'] as Map?)?['name'] as String?)
                            ?.isNotEmpty ==
                        true)
                  Text(
                    'Mobile: ${user['mobile'] ?? '—'} · Emergency: '
                    '${(user['emergencyContact'] as Map?)?['name'] ?? '—'} '
                    '(${(user['emergencyContact'] as Map?)?['mobile'] ?? '—'})',
                    style: const TextStyle(fontSize: 11, color: slate),
                  ),
                if (user['mergedInto'] == null)
                  DropdownButtonFormField<String>(
                    key: ValueKey('role-${user['uid']}-${user['role']}'),
                    initialValue: user['role'] as String? ?? 'participant',
                    decoration: const InputDecoration(
                      labelText: 'Account role',
                    ),
                    items: [
                      for (final role in ['participant', 'coach', 'admin'])
                        DropdownMenuItem(value: role, child: Text(role)),
                    ],
                    onChanged:
                        busy ||
                            reason.text.trim().isEmpty ||
                            user['uid'] == widget.repository.uid
                        ? null
                        : (role) => run(() async {
                            await widget.repository.call('setUserRole', {
                              'uid': user['uid'],
                              'role': role,
                              'reason': reason.text.trim(),
                            });
                            final result = await widget.repository.call(
                              'listUsers',
                              {'query': search.text.trim()},
                            );
                            if (mounted) {
                              setState(
                                () => users = (result['users'] as List)
                                    .map(
                                      (u) =>
                                          Map<String, dynamic>.from(u as Map),
                                    )
                                    .toList(),
                              );
                            }
                          }),
                  ),
                if (user['mergedInto'] != null)
                  const StatusPill('Merged profile')
                else
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Coach access',
                      style: TextStyle(fontSize: 13),
                    ),
                    subtitle: Text(
                      user['role'] == 'admin'
                          ? 'Admin access is retained.'
                          : 'Participant access is always retained.',
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: user['coachEnabled'] == true,
                    onChanged:
                        busy ||
                            reason.text.trim().isEmpty ||
                            user['uid'] == widget.repository.uid
                        ? null
                        : (value) => run(() async {
                            await widget.repository.call('setUserRole', {
                              'uid': user['uid'],
                              'role': 'coach',
                              'enabled': value,
                              'reason': reason.text.trim(),
                            });
                            final result = await widget.repository.call(
                              'listUsers',
                              {'query': search.text.trim()},
                            );
                            if (mounted) {
                              setState(
                                () => users = (result['users'] as List)
                                    .map(
                                      (u) =>
                                          Map<String, dynamic>.from(u as Map),
                                    )
                                    .toList(),
                              );
                            }
                          }),
                  ),
              ],
            ),
          ),
        ),
      if (cursor != null)
        TextButton(
          onPressed: () => load(more: true),
          child: const Text('Load more users'),
        ),
      const SizedBox(height: 24),
      Text(
        'Assign event coaches',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 12),
      DropdownButtonFormField<String>(
        initialValue: selectedEventId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Event'),
        items: events
            .map(
              (e) => DropdownMenuItem(
                value: e['eventId'] as String,
                child: Text(e['name'] as String),
              ),
            )
            .toList(),
        onChanged: (id) {
          final e = events.firstWhere((e) => e['eventId'] == id);
          setState(() {
            selectedEventId = id;
            selectedCoaches = Set<String>.from(e['coachUids'] as List);
          });
        },
      ),
      if (selectedEventId != null) ...[
        const SizedBox(height: 12),
        for (final user in users.where(
          (u) =>
              u['mergedInto'] == null &&
              (u['role'] == 'admin' ||
                  u['coachEnabled'] == true ||
                  selectedCoaches.contains(u['uid'])),
        ))
          CheckboxListTile(
            title: Text(
              user['email'] as String,
              style: const TextStyle(fontSize: 12),
            ),
            value: selectedCoaches.contains(user['uid']),
            onChanged: busy
                ? null
                : (yes) => setState(
                    () => yes == true
                        ? selectedCoaches.add(user['uid'] as String)
                        : selectedCoaches.remove(user['uid']),
                  ),
          ),
        FilledButton(
          onPressed: busy || reason.text.trim().isEmpty
              ? null
              : () => run(() async {
                  await widget.repository.call('assignEventCoaches', {
                    'eventId': selectedEventId,
                    'coachUids': selectedCoaches.toList(),
                    'reason': reason.text.trim(),
                  });
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Event coaches updated')),
                    );
                  }
                }),
          child: const Text('Save event coaches'),
        ),
      ],
    ],
  );
}

class CoachOverviewPanel extends StatefulWidget {
  const CoachOverviewPanel({super.key, required this.repository});
  final ParticipantRepository repository;
  @override
  State<CoachOverviewPanel> createState() => _CoachOverviewPanelState();
}

class _CoachOverviewPanelState extends State<CoachOverviewPanel> {
  late Future<Record> overview = widget.repository.call('coachOverview', {});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: Text(
              'Arrivals to review',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            onPressed: () => setState(
              () => overview = widget.repository.call('coachOverview', {}),
            ),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh arrivals',
          ),
        ],
      ),
      FutureBuilder<Record>(
        future: overview,
        builder: (context, s) {
          if (s.hasError) {
            return const Panel(
              color: pink,
              child: Text(
                'Coach access is unavailable. Refresh your access or contact your admin.',
              ),
            );
          }
          if (!s.hasData) return const LinearProgressIndicator();
          final pending = s.data!['pending'] as List;
          if (pending.isEmpty) {
            return const Panel(
              child: Text('No pending arrivals for your assigned events.'),
            );
          }
          return Column(
            children: pending
                .map(
                  (scan) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            scan['firstName'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(scan['eventName'] as String),
                          Text(
                            'Scan: ${friendlyDateTime(DateTime.parse(scan['scannedAt'] as String))}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            scan['distanceM'] == null
                                ? 'Distance: manual'
                                : 'Distance: ${(scan['distanceM'] as num).round()} m',
                            style: const TextStyle(fontSize: 12),
                          ),
                          if (scan['identityVerification'] == 'email-only')
                            const StatusPill('Email not verified', dark: true),
                          const SizedBox(height: 8),
                          const Text(
                            'Confirm in person before marking attendance.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    ],
  );
}
