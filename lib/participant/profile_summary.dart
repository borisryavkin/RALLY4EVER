import 'package:flutter/material.dart';

import 'form_groups.dart';
import 'repository.dart';
import 'theme.dart';
import 'user_avatar.dart';

/// Deduplicate RSVP intent and actual attendance; future RSVPs are not absences.
List<Record> profileHistory(ParticipantRepository repo) {
  final ids = {
    ...repo.rsvps
        .where((r) => r['cancelledAt'] == null)
        .map((r) => r['eventId']),
    ...repo.checkins.map((c) => c['eventId']),
  };
  final rows = <Record>[];
  for (final id in ids) {
    final event = repo.events
        .where((e) => (e['id'] ?? e['eventId']) == id)
        .firstOrNull;
    final checkin = repo.checkins.where((c) => c['eventId'] == id).firstOrNull;
    final attended = checkin?['status'] == 'confirmed';
    final ended =
        event?['endsAt'] != null &&
        !dateOf(event!['endsAt']).isAfter(repo.now());
    final counted = repo.rsvps.any(
      (r) => r['eventId'] == id && r['cancelledAt'] == null,
    );
    rows.add({
      'id': id,
      'event': event,
      'attended': attended,
      'missed':
          counted && ended && !attended && checkin?['status'] != 'pending',
      'label': attended
          ? 'Attended'
          : checkin?['status'] == 'pending'
          ? 'Awaiting coach'
          : counted
          ? (ended ? 'Counted in only' : 'Counted in')
          : 'Not attended',
    });
  }
  rows.sort(
    (a, b) =>
        dateOf(b['event']?['startsAt'])
            .compareTo(dateOf(a['event']?['startsAt'])),
  );
  return rows;
}

class ProfileSummary extends StatelessWidget {
  const ProfileSummary({
    super.key,
    required this.repo,
    required this.onEdit,
    required this.onPhoto,
    required this.onSignForms,
    required this.onSession,
    required this.sessionDate,
  });
  final ParticipantRepository repo;
  final VoidCallback onEdit, onPhoto, onSignForms;
  final ValueChanged<String> onSession;
  final String Function(Record) sessionDate;

  Widget card(Widget child) => Material(
    color: Colors.white,
    elevation: 1,
    shadowColor: navy.withValues(alpha: .12),
    borderRadius: BorderRadius.circular(22),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: navy),
        child: child,
      ),
    ),
  );
  Widget section(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: slate,
      ),
    ),
  );
  Widget badge(String text, bool current) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: current ? const Color(0xFFDEEFE5) : const Color(0xFFFFEFD3),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: current ? const Color(0xFF237847) : const Color(0xFF865600),
      ),
    ),
  );
  Widget row(Widget text, Widget status) => LayoutBuilder(
    builder: (context, constraints) {
      if (MediaQuery.textScalerOf(context).scale(16) > 21 ||
          constraints.maxWidth < 280) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [text, const SizedBox(height: 8), status],
        );
      }
      return Row(
        children: [
          Expanded(child: text),
          const SizedBox(width: 10),
          status,
        ],
      );
    },
  );
  @override
  Widget build(BuildContext context) {
    final history = profileHistory(repo);
    final groups = agreementGroups(repo.forms);
    final formRows = <Widget>[];
    for (final group in groups) {
      final sources = formSources(group);
      final current =
          sources.length == (group['id'] == 'conduct' ? 2 : 1) &&
          sources.every(repo.signed) &&
          sources.every(repo.formPublished);
      final receipts = sources
          .map(
            (f) => repo.consents
                .where(
                  (c) => c['formId'] == f['id'] && c['version'] == f['version'],
                )
                .firstOrNull,
          )
          .toList();
      final dates =
          receipts
              .whereType<Record>()
              .where((c) => c['signedAt'] != null)
              .map((c) => dateOf(c['signedAt']))
              .toList()
            ..sort();
      final versions = sources
          .map((s) => '${s['version']}')
          .toSet()
          .join(' / ');
      if (formRows.isNotEmpty) {
        formRows.add(const Divider(height: 28, color: Color(0xFFE0DBD7)));
      }
      formRows.add(
        row(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group['title'] as String,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'v$versions${current && dates.isNotEmpty ? ' · signed ${dateLabel(dates.last)}' : ''}',
                style: const TextStyle(fontSize: 12, color: slate),
              ),
            ],
          ),
          badge(current ? 'Current' : 'Needs signing', current),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Profile & preferences',
          container: true,
          child: Row(
            children: [
              Semantics(
                button: true,
                label: 'Change profile photo',
                child: InkWell(
                  onTap: onPhoto,
                  borderRadius: BorderRadius.circular(28),
                  child: UserAvatar(
                    repository: repo,
                    radius: 28,
                    textStyle: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      repo.profile['firstName'] as String? ?? 'Member',
                      style: const TextStyle(
                        fontSize: 26,
                        color: navy,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${repo.email ?? ''} · one profile',
                      style: const TextStyle(fontSize: 12, color: slate),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 22),
                tooltip: 'Edit details',
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final stat in [
                (
                  '${history.where((r) => r['attended'] == true).length}',
                  'Sessions attended',
                ),
                (
                  '${history.where((r) => r['missed'] == true).length}',
                  'Counted in, did not attend',
                ),
              ]) ...[
                if (stat.$2 != 'Sessions attended') const SizedBox(width: 12),
                Expanded(
                  child: card(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stat.$1,
                          style: const TextStyle(
                            fontSize: 28,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          stat.$2,
                          style: const TextStyle(fontSize: 12, color: slate),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        section('FORMS'),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...formRows,
              if (groups.length != 3)
                const Text('A required agreement is missing or unpublished.'),
              const Divider(height: 26, color: Color(0xFFE0DBD7)),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('profile-sign-forms'),
                  onPressed: onSignForms,
                  icon: const Icon(Icons.draw_outlined, size: 18),
                  label: const Text('Sign forms'),
                ),
              ),
            ],
          ),
        ),
        section('RECENT SESSIONS'),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (history.isEmpty)
                const Text(
                  'Your attendance history will appear after your first check-in.',
                  style: TextStyle(color: slate),
                ),
              for (final entry in history) ...[
                if (entry != history.first)
                  const Divider(height: 24, color: Color(0xFFE0DBD7)),
                InkWell(
                  onTap: () => onSession('${entry['id']}'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: row(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry['event']?['name'] as String? ??
                                'Session ${entry['id']}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            entry['event'] == null
                                ? 'Session details unavailable'
                                : sessionDate(entry['event'] as Record),
                            style: const TextStyle(fontSize: 12, color: slate),
                          ),
                        ],
                      ),
                      badge(
                        entry['label'] as String,
                        entry['attended'] == true,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

String dateLabel(DateTime d) =>
    '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';
