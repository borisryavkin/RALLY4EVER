import 'package:flutter/material.dart';

import 'repository.dart';
import 'theme.dart';

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
  Set<String> selectedCoaches = {};
  bool busy = false;
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
      if (mounted) setState(() => error = e.toString());
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
      for (final user in users)
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
                    onChanged: busy || reason.text.trim().isEmpty
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
              (u['coachEnabled'] == true || selectedCoaches.contains(u['uid'])),
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
                            'Scan: ${DateTime.parse(scan['scannedAt'] as String).toLocal()}',
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
