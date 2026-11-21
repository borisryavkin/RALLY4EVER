import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'repository.dart';
import '../shared/logo.dart';
import 'theme.dart';

LatLng? venuePoint(Record record) {
  final venue = record['venue'];
  if (venue is! Map || venue['lat'] is! num || venue['lng'] is! num) {
    return null;
  }
  final lat = (venue['lat'] as num).toDouble(),
      lng = (venue['lng'] as num).toDouble();
  if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
    return null;
  }
  return LatLng(lat, lng);
}

String availability(Record record) {
  if (record['status'] == 'archived') return 'Archived';
  if (record['status'] == 'cancelled') return 'Cancelled';
  if (record['registrationStatus'] == 'closed') return 'Bookings closed';
  final capacity = record['capacity'] as num?;
  final booked = (record['bookedCount'] as num?) ?? 0;
  if (record['registrationStatus'] == 'full' ||
      (capacity != null && booked >= capacity)) {
    return 'Full';
  }
  if (record['scheduleText'] != null && record['startsAt'] == null) {
    return 'See session availability';
  }
  if (capacity == null) return 'Spots available';
  final remaining = (capacity - booked).clamp(0, capacity).toInt();
  return '$remaining ${remaining == 1 ? 'spot' : 'spots'} available';
}

bool acceptsReservations(Record record) => ![
  'Cancelled',
  'Archived',
  'Full',
  'Bookings closed',
].contains(availability(record));

/// Groups a distance-sorted session list by program (a session with no
/// `programId` is its own one-session group), keeping each group at the
/// position of its first-seen (i.e. nearest) session. Within a group,
/// reservable sessions sort before full/closed/cancelled ones, then by
/// start date -- so a heavily-booked-out program's closed dates sink below
/// its open ones instead of flooding the top of the list.
List<List<Record>> groupSessionsByProgram(
  List<Record> sessions,
  bool Function(Record) reservable,
) {
  final order = <String>[];
  final groups = <String, List<Record>>{};
  for (final e in sessions) {
    final key = (e['programId'] as String?) ?? 'standalone:${e['id'] ?? e['eventId']}';
    final group = groups.putIfAbsent(key, () {
      order.add(key);
      return [];
    });
    group.add(e);
  }
  for (final group in groups.values) {
    group.sort((a, b) {
      final ar = reservable(a) ? 0 : 1, br = reservable(b) ? 0 : 1;
      if (ar != br) return ar.compareTo(br);
      return dateOf(a['startsAt']).compareTo(dateOf(b['startsAt']));
    });
  }
  return [for (final key in order) groups[key]!];
}

bool matchesProgram(
  Record program, {
  String search = '',
  String sport = 'All',
  String state = 'All',
  bool archived = false,
}) {
  if (program['status'] != (archived ? 'archived' : 'active')) return false;
  if (sport != 'All' &&
      '${program['sport']}'.toLowerCase() != sport.toLowerCase()) {
    return false;
  }
  final venue = program['venue'] as Map? ?? {};
  if (state != 'All' && venue['state'] != state) return false;
  final haystack =
      '${program['name']} ${venue['name']} ${venue['suburb']} ${venue['postcode']} ${venue['state']}'
          .toLowerCase();
  return haystack.contains(search.trim().toLowerCase());
}

class ProgramCard extends StatelessWidget {
  const ProgramCard({super.key, required this.program, required this.onTap});
  final Record program;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final venue = program['venue'] as Map? ?? {};
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Panel(
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${program['name']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Icon(
                    program['sport'] == 'pickleball'
                        ? Icons.sports
                        : Icons.sports_tennis,
                    color: coral,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${venue['suburb'] ?? ''}, ${venue['state'] ?? ''} · ${program['sport']}',
              ),
              Text(
                '${program['scheduleText'] ?? ''}',
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 10),
              Text(
                availability(program),
                style: const TextStyle(
                  color: navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Row(
                children: [
                  Text('View program & dates', style: TextStyle(color: coral)),
                  Spacer(),
                  Icon(Icons.arrow_forward, color: coral, size: 18),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProgramBrowser extends StatefulWidget {
  const ProgramBrowser({
    super.key,
    required this.repository,
    required this.onSelect,
    this.onSavedDirectory,
  });
  final ParticipantRepository repository;
  final ValueChanged<Record> onSelect;
  final VoidCallback? onSavedDirectory;
  @override
  State<ProgramBrowser> createState() => _ProgramBrowserState();
}

class _ProgramBrowserState extends State<ProgramBrowser> {
  String search = '', sport = 'All', state = 'All';
  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    final rows =
        repo.programs
            .where(
              (p) =>
                  matchesProgram(p, search: search, sport: sport, state: state),
            )
            .toList()
          ..sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Find your people, wherever you play.',
          style: TextStyle(color: slate),
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('program-search'),
          decoration: const InputDecoration(
            labelText: 'Suburb, postcode or program',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => search = v),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final value in ['All', 'Tennis', 'Pickleball'])
              ChoiceChip(
                label: Text(
                  value,
                  style: TextStyle(color: sport == value ? Colors.white : navy),
                ),
                selectedColor: navy,
                checkmarkColor: Colors.white,
                selected: sport == value,
                onSelected: (_) => setState(() => sport = value),
              ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: state,
          decoration: const InputDecoration(labelText: 'State or territory'),
          items: [
            for (final s in [
              'All',
              'ACT',
              'NSW',
              'NT',
              'QLD',
              'SA',
              'TAS',
              'VIC',
              'WA',
            ])
              DropdownMenuItem(
                value: s,
                child: Text(s == 'All' ? 'All Australia' : s),
              ),
          ],
          onChanged: (v) => setState(() => state = v!),
        ),
        const SizedBox(height: 12),
        if (repo.catalogueReady && repo.catalogueError == null && rows.isEmpty)
          Panel(
            child: Text(
              'No published programs match your search. Try another suburb or state.',
            ),
          ),
        if (!repo.catalogueReady && repo.catalogueError == null) ...[
          const SizedBox(height: 16),
          const Panel(
            color: cream,
            child: SizedBox(
              height: 72,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Loading programs…'),
              ),
            ),
          ),
        ],
        if (repo.catalogueError != null)
          Panel(
            color: pink,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Programs could not load. Please try again.'),
                TextButton(
                  onPressed: repo.refreshCatalogue,
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        for (final program in rows)
          ProgramCard(program: program, onTap: () => widget.onSelect(program)),
        if (widget.onSavedDirectory != null)
          TextButton(
            onPressed: widget.onSavedDirectory,
            child: const Text('Browse saved directory'),
          ),
      ],
    );
  }
}

String? cataloguePhotoUrl(Record record, [Iterable<Record> venues = const []]) {
  if (record['photoMode'] == 'none') return null;
  final own = record['photoUrl'] as String? ?? '';
  if (own.isNotEmpty && record['photoMode'] != 'venue') return own;
  final venue = record['venue'] is Map
      ? Map<String, dynamic>.from(record['venue'] as Map)
      : <String, dynamic>{};
  final id = record['venueId'] ?? venue['id'];
  final canonical = venues
      .where(
        (v) => id != null
            ? v['id'] == id
            : v['name'] == venue['name'] &&
                  v['lat'] == venue['lat'] &&
                  v['lng'] == venue['lng'],
      )
      .firstOrNull;
  final url = (canonical?['photoUrl'] ?? venue['photoUrl']) as String?;
  return url == null || url.isEmpty ? null : url;
}

class CataloguePhoto extends StatelessWidget {
  const CataloguePhoto({super.key, required this.record, this.repository});
  final ParticipantRepository? repository;
  final Record record;
  @override
  Widget build(BuildContext context) {
    final url = cataloguePhotoUrl(record, repository?.venues ?? []) ?? '';
    final placeholder = ColoredBox(
      color: cream,
      child: const Center(child: Logo(height: 55)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 180,
        width: double.infinity,
        child: url.isEmpty
            ? placeholder
            : url.startsWith('gs://')
            ? FutureBuilder<Uint8List?>(
                future: repository?.venuePhotoBytes(url),
                builder: (context, snapshot) => snapshot.hasData
                    ? Image.memory(
                        snapshot.data!,
                        fit: BoxFit.cover,
                        semanticLabel: '${record['name']} venue',
                      )
                    : placeholder,
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                semanticLabel: '${record['name']} venue',
                errorBuilder: (_, _, _) => placeholder,
              ),
      ),
    );
  }
}

const nearbyRadiusKm = 50.0;
List<Record> nearbySessionRecords(
  Iterable<Record> events, {
  required DateTime now,
  LatLng? centre,
  String sport = 'All',
  double radiusKm = nearbyRadiusKm,
  Iterable<Record> programs = const [],
}) {
  final published = {for (final p in programs) p['id']: p['status']};
  final distance = const Distance();
  final rows = events
      .where(
        (e) =>
            e['status'] == 'published' &&
            dateOf(e['endsAt']).isAfter(now) &&
            venuePoint(e) != null &&
            (e['programId'] == null || published[e['programId']] == 'active') &&
            (sport == 'All' ||
                '${e['sport']}'.toLowerCase() == sport.toLowerCase()) &&
            (centre == null ||
                distance.as(LengthUnit.Kilometer, centre, venuePoint(e)!) <=
                    radiusKm),
      )
      .toList();
  rows.sort((a, b) {
    final d = centre == null
        ? 0
        : distance(
            centre,
            venuePoint(a)!,
          ).compareTo(distance(centre, venuePoint(b)!));
    return d != 0 ? d : dateOf(a['startsAt']).compareTo(dateOf(b['startsAt']));
  });
  return rows;
}

String sessionDistanceLabel(Record e, LatLng centre) =>
    '${const Distance().as(LengthUnit.Kilometer, centre, venuePoint(e)!).toStringAsFixed(1)} km';
