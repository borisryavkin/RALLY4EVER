import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import 'repository.dart';
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
  bool archived = false;
  @override
  Widget build(BuildContext context) {
    final repo = widget.repository;
    final rows =
        repo.programs
            .where(
              (p) => matchesProgram(
                p,
                search: search,
                sport: sport,
                state: state,
                archived: archived,
              ),
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
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Archived programs'),
          value: archived,
          onChanged: (v) => setState(() => archived = v),
        ),
        if (repo.catalogueReady && repo.catalogueError == null && rows.isEmpty)
          Panel(
            child: Text(
              archived ? 'No archived programs match your search.' : 'No published programs match your search. Try another suburb or state.',
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

class CataloguePhoto extends StatelessWidget {
  const CataloguePhoto({super.key, required this.record});
  final Record record;
  @override
  Widget build(BuildContext context) {
    final url = record['photoUrl'] as String? ?? '';
    final placeholder = ColoredBox(
      color: pink.withValues(alpha: .35),
      child: const Center(
        child: Icon(Icons.sports_tennis, size: 48, color: navy),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: 180,
        width: double.infinity,
        child: url.isEmpty
            ? placeholder
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
