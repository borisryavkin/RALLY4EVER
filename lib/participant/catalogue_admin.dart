import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

import 'repository.dart';
import 'theme.dart';

class CatalogueAdminPanel extends StatefulWidget {
  const CatalogueAdminPanel({super.key, required this.repository});
  final ParticipantRepository repository;
  @override
  State<CatalogueAdminPanel> createState() => _CatalogueAdminPanelState();
}

class _CatalogueAdminPanelState extends State<CatalogueAdminPanel> {
  List<Record> programs = [];
  Record? selected;
  String statusFilter = 'All', search = '';
  Future<void> publish(Record program) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          program['status'] == 'active'
              ? 'Unpublish program'
              : 'Publish program',
        ),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason / review confirmation',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (reason == null) return;
    await run(() async {
      final fields = {
        for (final key in [
          'name',
          'sport',
          'status',
          'venue',
          'timezone',
          'scheduleText',
          'coachUids',
          'coachNames',
          'notes',
          'photoUrl',
          'capacity',
          'registrationStatus',
        ])
          key: program[key],
      };
      fields['status'] = program['status'] == 'active' ? 'draft' : 'active';
      await widget.repository.call('saveProgram', {
        'programId': program['id'],
        'revision': program['revision'],
        'program': fields,
        'reason': reason,
      });
    });
    await load();
  }

  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> run(Future<void> Function() task) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() => run(() async {
    final result = await widget.repository.call('listPrograms', {});
    if (mounted) {
      setState(
        () => programs = (result['programs'] as List)
            .map((p) => Map<String, dynamic>.from(p as Map))
            .toList(),
      );
    }
  });
  Future<void> edit([Record? program]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            ProgramEditor(repository: widget.repository, program: program),
      ),
    );
    if (saved == true) await load();
  }

  Future<void> schedule(Record program, [Record? session]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionEditor(
          repository: widget.repository,
          program: program,
          session: session,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Programs & calendar',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 10),
      const Text(
        'Publish a program, assign its coaches, then add dated sessions. Archiving keeps its records and attendance history.',
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: busy ? null : () => edit(),
        child: const Text('Create program'),
      ),
      TextButton(
        onPressed: busy ? null : load,
        child: const Text('Refresh programs'),
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Panel(color: pink, child: Text(error!)),
      if (!busy && programs.isEmpty)
        const Text(
          'No programs yet. Create one or preview the bundled directory import.',
        ),
      TextField(
        decoration: const InputDecoration(labelText: 'Find program by name'),
        onChanged: (v) => setState(() => search = v.toLowerCase()),
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final value in ['All', 'draft', 'active', 'archived'])
            ChoiceChip(
              label: Text(value == 'active' ? 'published' : value),
              selected: statusFilter == value,
              onSelected: (_) => setState(() => statusFilter = value),
            ),
        ],
      ),
      for (final p in programs.where(
        (p) =>
            (statusFilter == 'All' || p['status'] == statusFilter) &&
            '${p['name']}'.toLowerCase().contains(search),
      ))
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p['name']}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('${p['status']} · ${p['venue']['state']} · ${p['sport']}'),
                Text('${p['scheduleText']}'),
                for (final e in widget.repository.events.where(
                  (e) => e['programId'] == p['id'],
                ))
                  TextButton(
                    onPressed: () => schedule(p, e),
                    child: Text(
                      'Edit ${dateOf(e['startsAt'])} · ${e['status']}',
                    ),
                  ),

                Wrap(
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: busy ? null : () => publish(p),
                      child: Text(
                        p['status'] == 'active' ? 'Unpublish' : 'Publish',
                      ),
                    ),
                    TextButton(
                      onPressed: () => edit(p),
                      child: const Text('Edit / archive'),
                    ),
                    TextButton(
                      onPressed: p['status'] == 'active'
                          ? () => schedule(p)
                          : null,
                      child: const Text('Add session'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
    ],
  );
}

class ProgramEditor extends StatefulWidget {
  const ProgramEditor({super.key, required this.repository, this.program});
  final ParticipantRepository repository;
  final Record? program;
  @override
  State<ProgramEditor> createState() => _ProgramEditorState();
}

class _ProgramEditorState extends State<ProgramEditor> {
  final fields = <String, TextEditingController>{};
  final form = GlobalKey<FormState>();
  String status = 'draft',
      sport = 'tennis',
      state = 'NSW',
      zone = 'Australia/Sydney',
      registration = 'open';
  List<Record> coaches = [];
  Set<String> coachUids = {};
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final p = widget.program ?? {}, v = p['venue'] as Map? ?? {};
    status = p['status'] as String? ?? status;
    sport = p['sport'] as String? ?? sport;
    state = v['state'] as String? ?? state;
    zone = p['timezone'] as String? ?? zone;
    registration = p['registrationStatus'] as String? ?? registration;
    coachUids = Set<String>.from(p['coachUids'] as List? ?? []);
    final initial = {
      'name': p['name'],
      'venue': v['name'],
      'address': v['address'],
      'suburb': v['suburb'],
      'postcode': v['postcode'],
      'lat': v['lat'],
      'lng': v['lng'],
      'schedule': p['scheduleText'],
      'coachNames': (p['coachNames'] as List? ?? []).join(', '),
      'notes': p['notes'],
      'photoUrl': p['photoUrl'],
      'capacity': p['capacity'],
      'reason': '',
    };
    for (final entry in initial.entries) {
      fields[entry.key] = TextEditingController(text: '${entry.value ?? ''}');
    }
    loadCoaches();
  }

  Future<void> loadCoaches() async {
    try {
      String? cursor;
      final users = <Record>[];
      do {
        final result = await widget.repository.call('listUsers', {
          'cursor': ?cursor,
        });
        users.addAll(
          (result['users'] as List).map(
            (p) => Map<String, dynamic>.from(p as Map),
          ),
        );
        cursor = result['cursor'] as String?;
      } while (cursor != null && mounted);
      if (mounted) {
        setState(
          () => coaches = users
              .where(
                (u) =>
                    (u['role'] == 'admin' ||
                        (u['role'] == 'coach' && u['coachEnabled'] != false)) &&
                    u['mergedInto'] == null,
              )
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String value(String key) => fields[key]!.text.trim();
  Widget field(
    String key,
    String label, {
    bool required = false,
    int lines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      key: Key('program-$key'),
      controller: fields[key],
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null
          : null,
    ),
  );
  Widget dropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChange,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final v in options) DropdownMenuItem(value: v, child: Text(v)),
      ],
      onChanged: (v) => setState(() => onChange(v!)),
    ),
  );
  Future<void> save() async {
    if (!(form.currentState?.validate() ?? false) || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      double? number(String key) {
        if (value(key).isEmpty) return null;
        final parsed = double.tryParse(value(key));
        return parsed;
      }

      final capacity = value('capacity').isEmpty
          ? null
          : int.tryParse(value('capacity'));
      if (value('capacity').isNotEmpty && capacity == null) {
        throw const FormatException('Capacity must be a whole number.');
      }
      for (final key in ['lat', 'lng']) {
        if (value(key).isNotEmpty && double.tryParse(value(key)) == null) {
          throw const FormatException('Enter valid venue coordinates.');
        }
      }
      final result = await widget.repository.call('saveProgram', {
        if (widget.program != null) 'programId': widget.program!['id'],
        if (widget.program != null) 'revision': widget.program!['revision'],
        'reason': value('reason'),
        'program': {
          'name': value('name'),
          'sport': sport,
          'status': status,
          'venue': {
            'name': value('venue'),
            'address': value('address'),
            'suburb': value('suburb'),
            'postcode': value('postcode'),
            'state': state,
            'lat': number('lat'),
            'lng': number('lng'),
          },
          'timezone': zone,
          'scheduleText': value('schedule'),
          'coachUids': coachUids.toList(),
          'coachNames': value('coachNames')
              .split(',')
              .map((v) => v.trim())
              .where((v) => v.isNotEmpty)
              .toList(),
          'notes': value('notes'),
          'photoUrl': value('photoUrl'),
          'capacity': capacity,
          'registrationStatus': registration,
        },
      });
      if (result['programId'] != null && mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.program == null ? 'New program' : 'Edit program'),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          field('name', 'Program name', required: true),
          dropdown('Sport', sport, ['tennis', 'pickleball'], (v) => sport = v),
          dropdown('Status', status, [
            'draft',
            'active',
            'archived',
          ], (v) => status = v),
          field('venue', 'Venue name', required: true),
          field('address', 'Street address'),
          field('suburb', 'Suburb', required: true),
          field('postcode', 'Postcode'),
          dropdown(
            'State or territory',
            state,
            ['ACT', 'NSW', 'NT', 'QLD', 'SA', 'TAS', 'VIC', 'WA'],
            (v) {
              state = v;
              zone = const {
                'ACT': 'Australia/Sydney',
                'NSW': 'Australia/Sydney',
                'NT': 'Australia/Darwin',
                'QLD': 'Australia/Brisbane',
                'SA': 'Australia/Adelaide',
                'TAS': 'Australia/Hobart',
                'VIC': 'Australia/Melbourne',
                'WA': 'Australia/Perth',
              }[v]!;
            },
          ),
          field('lat', 'Venue latitude'),
          field('lng', 'Venue longitude'),
          const Text(
            'Both coordinates are required before dated sessions can be published.',
          ),
          const SizedBox(height: 12),
          dropdown('Venue timezone', zone, [
            'Australia/Sydney',
            'Australia/Melbourne',
            'Australia/Brisbane',
            'Australia/Adelaide',
            'Australia/Perth',
            'Australia/Darwin',
            'Australia/Hobart',
          ], (v) => zone = v),
          field(
            'schedule',
            'Regular schedule / term dates',
            required: true,
            lines: 2,
          ),
          field('coachNames', 'Public coach names, separated by commas'),
          const Text(
            'Assigned coach accounts',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          if (coaches.isEmpty)
            const Text(
              'No active coaches loaded. Grant coach access in People & permissions first.',
            ),
          for (final coach in coaches)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${coach['email']}'),
              value: coachUids.contains(coach['uid']),
              onChanged: (v) => setState(
                () => v == true
                    ? coachUids.add(coach['uid'] as String)
                    : coachUids.remove(coach['uid']),
              ),
            ),
          field('notes', 'What participants should know', lines: 4),
          field('photoUrl', 'Photo URL (HTTPS)'),
          field('capacity', 'Default session capacity (blank = unlimited)'),
          dropdown('Reservations', registration, [
            'open',
            'full',
            'closed',
          ], (v) => registration = v),
          field('reason', 'Reason for this change', required: true, lines: 2),
          if (error != null) Panel(color: pink, child: Text(error!)),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving…' : 'Save program'),
          ),
        ],
      ),
    ),
  );
}

class SessionEditor extends StatefulWidget {
  const SessionEditor({
    super.key,
    required this.repository,
    required this.program,
    this.session,
  });
  final ParticipantRepository repository;
  final Record program;
  final Record? session;
  @override
  State<SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<SessionEditor> {
  DateTime? start, end;
  final venueFields = <String, TextEditingController>{};
  List<Record> coaches = [];
  Set<String> coachUids = {};
  String zone = 'Australia/Sydney', venueState = 'NSW';
  Future<void> loadCoaches() async {
    try {
      String? cursor;
      final all = <Record>[];
      do {
        final result = await widget.repository.call('listUsers', {
          'cursor': ?cursor,
        });
        all.addAll(
          (result['users'] as List).map(
            (u) => Map<String, dynamic>.from(u as Map),
          ),
        );
        cursor = result['cursor'] as String?;
      } while (cursor != null && mounted);
      if (mounted) {
        setState(
          () => coaches = all
              .where(
                (u) =>
                    u['mergedInto'] == null &&
                    (u['role'] == 'admin' ||
                        (u['role'] == 'coach' && u['coachEnabled'] != false)),
              )
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  final capacity = TextEditingController(), notes = TextEditingController();
  String registration = 'open', status = 'published';
  @override
  void initState() {
    super.initState();
    final session = widget.session;
    zone = (session?['timezone'] ?? widget.program['timezone']) as String;
    final venue = (session?['venue'] ?? widget.program['venue']) as Map;
    venueState = venue['state'] as String? ?? 'NSW';
    for (final key in ['name', 'address', 'suburb', 'postcode', 'lat', 'lng']) {
      venueFields[key] = TextEditingController(text: '${venue[key] ?? ''}');
    }
    coachUids = Set<String>.from(
      (session?['coachUids'] ?? widget.program['coachUids']) as List? ?? [],
    );
    loadCoaches();
    if (session != null) {
      final location = tz.getLocation(zone);
      start = tz.TZDateTime.from(dateOf(session['startsAt']), location);
      end = tz.TZDateTime.from(dateOf(session['endsAt']), location);
    }
    capacity.text =
        '${(session != null ? session['capacity'] : widget.program['capacity']) ?? ''}';
    notes.text = '${session?['notes'] ?? widget.program['notes'] ?? ''}';
    registration =
        session?['registrationStatus'] as String? ??
        widget.program['registrationStatus'] as String? ??
        'open';
    status = session?['status'] as String? ?? 'published';
  }

  String? error;
  bool busy = false;
  @override
  void dispose() {
    for (final controller in venueFields.values) {
      controller.dispose();
    }
    capacity.dispose();
    notes.dispose();
    super.dispose();
  }

  Future<void> pick(bool isStart) async {
    final location = tz.getLocation(zone);
    final now = tz.TZDateTime.from(widget.repository.now(), location);
    final date = await showDatePicker(
      context: context,
      initialDate: start ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (time == null) return;
    final selected = tz.TZDateTime(
      location,
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (selected.hour != time.hour || selected.minute != time.minute) {
      if (mounted) {
        setState(
          () => error = 'That time does not occur at the venue because of daylight saving.',
        );
      }
      return;
    }
    if (mounted) {
      setState(() {
        if (isStart) {
          start = selected;
        } else {
          end = selected;
        }
      });
    }
  }

  Future<void> save() async {
    if (start == null || end == null || !end!.isAfter(start!)) {
      setState(() => error = 'Choose a start and a later end.');
      return;
    }
    setState(() => busy = true);
    try {
      await widget.repository.call('saveSession', {
        if (widget.program['id'] != null) 'programId': widget.program['id'],
        if (widget.session != null) 'eventId': widget.session!['id'],
        if (widget.session != null) 'revision': widget.session!['revision'],
        'venue': {
          for (final key in ['name', 'address', 'suburb', 'postcode'])
            key: venueFields[key]!.text.trim(),
          'state': venueState,
          'lat': double.parse(venueFields['lat']!.text.trim()),
          'lng': double.parse(venueFields['lng']!.text.trim()),
        },
        'timezone': zone,
        'coachUids': coachUids.toList(),
        'capacity': capacity.text.trim().isEmpty
            ? null
            : int.parse(capacity.text.trim()),
        'registrationStatus': registration,
        'notes': notes.text.trim(),
        'status': status,
        'startsAt': start!.toUtc().toIso8601String(),
        'endsAt': end!.toUtc().toIso8601String(),
      });
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.session == null ? 'Create session' : 'Edit / cancel session',
      ),
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '${widget.program['name']}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text(
          'Times use $zone. Venue, capacity and coaches apply to this session only.',
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: zone,
          decoration: const InputDecoration(labelText: 'Session timezone'),
          items: [
            for (final value in [
              'Australia/Sydney',
              'Australia/Melbourne',
              'Australia/Brisbane',
              'Australia/Adelaide',
              'Australia/Perth',
              'Australia/Hobart',
              'Australia/Darwin',
              'Australia/Lord_Howe',
            ])
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (v) => setState(() {
            zone = v!;
            start = null;
            end = null;
          }),
        ),
        for (final key in venueFields.keys)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextField(
              controller: venueFields[key],
              decoration: InputDecoration(labelText: 'Session venue $key'),
            ),
          ),
        DropdownButtonFormField<String>(
          initialValue: venueState,
          decoration: const InputDecoration(labelText: 'Venue state'),
          items: [
            for (final value in [
              'ACT',
              'NSW',
              'NT',
              'QLD',
              'SA',
              'TAS',
              'VIC',
              'WA',
            ])
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (v) => setState(() => venueState = v!),
        ),
        const Text('Assigned session coaches'),
        for (final coach in coaches)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${coach['email']}'),
            value: coachUids.contains(coach['uid']),
            onChanged: (selected) => setState(() {
              if (selected == true) {
                coachUids.add(coach['uid'] as String);
              } else {
                coachUids.remove(coach['uid']);
              }
            }),
          ),
        OutlinedButton(
          onPressed: () => pick(true),
          child: Text(
            start == null ? 'Choose start date & time' : 'Starts: $start',
          ),
        ),
        OutlinedButton(
          onPressed: () => pick(false),
          child: Text(end == null ? 'Choose end date & time' : 'Ends: $end'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: capacity,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Session capacity (blank = unlimited)',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: registration,
          decoration: const InputDecoration(labelText: 'Reservations'),
          items: [
            for (final value in ['open', 'full', 'closed'])
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (v) => setState(() => registration = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Session status'),
          items: [
            for (final value in ['published', 'cancelled'])
              DropdownMenuItem(value: value, child: Text(value)),
          ],
          onChanged: (v) => setState(() => status = v!),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notes,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Session notes'),
        ),
        const SizedBox(height: 12),
        if (error != null) Panel(color: pink, child: Text(error!)),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(
            busy
                ? 'Saving…'
                : status == 'cancelled'
                ? 'Cancel session'
                : 'Save session',
          ),
        ),
      ],
    ),
  );
}

class SessionManagementPanel extends StatefulWidget {
  const SessionManagementPanel({super.key, required this.repository});
  final ParticipantRepository repository;
  @override
  State<SessionManagementPanel> createState() => _SessionManagementPanelState();
}

class _SessionManagementPanelState extends State<SessionManagementPanel> {
  List<Record> programs = [], sessions = [];
  String? selected, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await Future.wait([
        widget.repository.call('listPrograms', {}),
        widget.repository.call('listStaffSessions', {}),
      ]);
      if (mounted) {
        setState(() {
          programs = (result[0]['programs'] as List)
              .map((p) => Map<String, dynamic>.from(p as Map))
              .toList();
          sessions = (result[1]['events'] as List)
              .map((p) => Map<String, dynamic>.from(p as Map))
              .toList();
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(Record program, [Record? session]) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionEditor(
          repository: widget.repository,
          program: program,
          session: session,
        ),
      ),
    );
    await load();
  }

  Future<void> cancel(Record session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel session?'),
        content: Text(
          'Cancel ${session['name']}? Attendance history will be retained.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel session'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.repository.call('cancelSession', {
        'eventId': session['id'],
        'revision': session['revision'],
      });
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.repository.canAdmin) {
      return const Text('Admin access required.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Sessions', style: Theme.of(context).textTheme.headlineMedium),
        const Text(
          'Create dated sessions from published programs. Historical attendance stays intact.',
        ),
        DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Published program'),
          items: [
            for (final p in programs.where((p) => p['status'] == 'active'))
              DropdownMenuItem(
                value: p['id'] as String,
                child: Text('${p['name']}'),
              ),
          ],
          onChanged: (v) => setState(() => selected = v),
        ),
        FilledButton(
          onPressed: busy || selected == null
              ? null
              : () => edit(programs.firstWhere((p) => p['id'] == selected)),
          child: const Text('Create session from program'),
        ),
        TextButton(
          onPressed: busy ? null : load,
          child: const Text('Refresh sessions'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Panel(color: pink, child: Text(error!)),
        for (final session in sessions)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${session['name']}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  Text(
                    '${dateOf(session['startsAt']).toLocal()} · ${session['status']}',
                  ),
                  Text(
                    '${session['venue']['name']} · Capacity: ${session['capacity'] ?? 'unlimited'}',
                  ),
                  Text(
                    'Coaches: ${(session['coachNames'] as List? ?? session['coachUids'] as List? ?? []).join(', ')}',
                  ),
                  if (session['status'] != 'cancelled' &&
                      dateOf(session['endsAt'])
                          .isAfter(widget.repository.now()))
                    TextButton(
                      onPressed: busy ? null : () => cancel(session),
                      child: const Text('Cancel session'),
                    ),
                  if (programs.any((p) => p['id'] == session['programId']))
                    TextButton(
                      onPressed: () => edit(
                        programs.firstWhere(
                          (p) => p['id'] == session['programId'],
                        ),
                        session,
                      ),
                      child: const Text('Edit / cancel / assign coaches'),
                    )
                  else
                    TextButton(
                      onPressed: () => edit({...session, 'id': null}, session),
                      child: const Text(
                        'Edit / assign coaches (legacy session)',
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (!busy && sessions.isEmpty) const Text('No dated sessions yet.'),
      ],
    );
  }
}
