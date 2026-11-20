import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'repository.dart';
import 'theme.dart';

class StaffSessionsPanel extends StatefulWidget {
  const StaffSessionsPanel({super.key, required this.repository});
  final ParticipantRepository repository;
  @override
  State<StaffSessionsPanel> createState() => _StaffSessionsPanelState();
}

class _StaffSessionsPanelState extends State<StaffSessionsPanel> {
  late Future<Record> sessions = load();
  Future<Record> load() => widget.repository.call('listStaffSessions', {});
  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    if (!repo.canAdmin && !repo.canCoach) {
      return const Text('Staff access required.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          repo.canAdmin ? 'All session consoles' : 'My session consoles',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const Text(
          'Open a session for its QR, counted-in list and actual arrivals.',
        ),
        TextButton(
          onPressed: () => setState(() => sessions = load()),
          child: const Text('Refresh sessions'),
        ),
        FutureBuilder<Record>(
          future: sessions,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Panel(color: pink, child: Text('${snapshot.error}'));
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            final rows =
                (snapshot.data!['events'] as List)
                    .map((e) => Map<String, dynamic>.from(e as Map))
                    .toList()
                  ..sort(
                    (a, b) =>
                        dateOf(a['startsAt']).compareTo(dateOf(b['startsAt'])),
                  );
            if (rows.isEmpty) {
              return const Panel(
                child: Text(
                  'No sessions are assigned to you yet. Ask an admin to assign your account.',
                ),
              );
            }
            return Column(
              children: [
                for (final event in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${event['name']}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            '${dateOf(event['startsAt']).toLocal()} · ${event['status']}',
                          ),
                          Text('${event['venue']['name']}'),
                          FilledButton(
                            key: Key('console-${event['id']}'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => EventConsoleScreen(
                                  repository: repo,
                                  eventId: event['id'] as String,
                                ),
                              ),
                            ),
                            child: const Text('Open session console'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class EventConsoleScreen extends StatefulWidget {
  const EventConsoleScreen({
    super.key,
    required this.repository,
    required this.eventId,
  });
  final ParticipantRepository repository;
  final String eventId;
  @override
  State<EventConsoleScreen> createState() => _EventConsoleScreenState();
}

class _EventConsoleScreenState extends State<EventConsoleScreen> {
  Record? data, qr;
  String? error;
  String filter = 'All';
  bool busy = false;
  Timer? refresh;
  @override
  void initState() {
    super.initState();
    widget.repository.addListener(accessChanged);
    load();
    refresh = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  void accessChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    refresh?.cancel();
    widget.repository.removeListener(accessChanged);
    super.dispose();
  }

  bool get allowed {
    final repo = widget.repository;
    if (repo.canAdmin) return true;
    if (!repo.canCoach) return false;
    final live = repo.events
        .where((e) => (e['id'] ?? e['eventId']) == widget.eventId)
        .firstOrNull;
    final event = live ?? data?['event'] as Map?;
    return event == null ||
        (event['coachUids'] as List? ?? []).contains(repo.uid);
  }

  Future<void> load({bool rotate = false}) async {
    if (busy || !allowed) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.repository.call('getEventConsole', {
        'eventId': widget.eventId,
      });
      final event = result['event'] as Map;
      Record? nextQr = qr;
      if (event['status'] == 'published' &&
          dateOf(event['endsAt']).isAfter(widget.repository.now()) &&
          (rotate ||
              nextQr == null ||
              !dateOf(nextQr['expiresAt']).isAfter(
                widget.repository.now().add(const Duration(seconds: 30)),
              ))) {
        nextQr = await widget.repository.call('rotateEventSecret', {
          'eventId': widget.eventId,
        });
      }
      if (mounted) {
        setState(() {
          data = result;
          qr = nextQr;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = friendlyError(e);
          qr = null;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> decide(Record member, String decision) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.repository.call('coachDecision', {
        'eventId': widget.eventId,
        'uid': member['uid'],
        'decision': decision,
      });
      if (mounted) setState(() => busy = false);
      await load();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = friendlyError(e);
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!allowed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Session console')),
        body: const Padding(
          padding: EdgeInsets.all(24),
          child: Text('Staff access is unavailable for this session.'),
        ),
      );
    }
    final event = data?['event'] as Map?;
    final members = (data?['roster'] as List? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final counted = members.where((m) => m['countedIn'] == true).length;
    final checked = members.where((m) => m['checkinStatus'] != null).length;
    final confirmed = members
        .where((m) => m['checkinStatus'] == 'confirmed')
        .length;
    final currentQr =
        qr != null && dateOf(qr!['expiresAt']).isAfter(widget.repository.now());
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session console'),
        actions: [
          IconButton(
            onPressed: busy ? null : () => load(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh console',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Panel(color: pink, child: Text(error!)),
          if (event != null) ...[
            Text(
              '${event['name']}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            Text(
              '${event['venue']['name']} · ${friendlyDateTime(dateOf(event['startsAt']))}',
            ),
            Text(
              '$counted counted in · $checked checked in · $confirmed confirmed',
              key: const Key('console-counts'),
            ),
            const SizedBox(height: 18),
            if (currentQr)
              Center(
                child: Column(
                  children: [
                    Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(16),
                      child: QrImageView(
                        key: const Key('event-qr'),
                        data: qr!['url'] as String,
                        size: 240,
                        version: QrVersions.auto,
                      ),
                    ),
                    Text(
                      'QR generation ${qr!['generation']} · expires ${friendlyDateTime(dateOf(qr!['expiresAt']))}',
                    ),
                  ],
                ),
              )
            else
              const Panel(
                child: Text(
                  'QR is unavailable for ended, cancelled or unpublished sessions.',
                ),
              ),
            OutlinedButton(
              onPressed:
                  busy ||
                      event['status'] != 'published' ||
                      !dateOf(event['endsAt']).isAfter(widget.repository.now())
                  ? null
                  : () => load(rotate: true),
              child: const Text('Rotate QR now'),
            ),
            const Text(
              'Check-in opens 10 minutes before the start. Confirm each arrival in person; scan time and distance are shown below.',
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              children: [
                for (final value in [
                  'All',
                  'Counted in',
                  'Checked in',
                  'Walk-ins',
                ])
                  ChoiceChip(
                    label: Text(value),
                    selected: filter == value,
                    onSelected: (_) => setState(() => filter = value),
                  ),
              ],
            ),
            if (data?['limited'] == true)
              const Text('Showing the first 500 RSVP/check-in records.'),
            for (final member in members.where(
              (m) => switch (filter) {
                'Counted in' => m['countedIn'] == true,
                'Checked in' => m['checkinStatus'] != null,
                'Walk-ins' => m['walkIn'] == true,
                _ => true,
              },
            ))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${member['firstName']} ${member['lastName']}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('${member['email']}'),
                      Text(
                        '${member['countedIn'] == true ? 'Counted in' : 'Not counted in'} · ${member['checkinStatus'] ?? 'Not checked in'}',
                      ),
                      if (member['scannedAt'] != null)
                        Text(
                          'Scanned ${dateOf(member['scannedAt']).toLocal()} · ${member['distanceM'] == null ? 'Manual arrival' : '${member['distanceM']} m from venue'}',
                        ),
                      if (member['checkinStatus'] == 'pending')
                        Wrap(
                          spacing: 12,
                          children: [
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => decide(member, 'confirm'),
                              child: const Text('Confirm arrival'),
                            ),
                            OutlinedButton(
                              onPressed: busy
                                  ? null
                                  : () => decide(member, 'reject'),
                              child: const Text('Reject arrival'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (members.isEmpty)
              const Panel(
                child: Text('Nobody has counted in or checked in yet.'),
              ),
          ],
        ],
      ),
    );
  }
}
