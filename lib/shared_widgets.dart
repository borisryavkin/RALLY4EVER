import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

const red = Color(0xffff4b4c),
    navy = Color(0xff001751),
    beige = Color(0xfff2eeeb),
    ink = Color(0xff10255c);

const playAreaCoordinates = <String, LatLng>{
  'Bondi 2026': LatLng(-33.8915, 151.2767),
  'Bondi Junction 2022': LatLng(-33.8926, 151.2511),
  'Coogee 2034': LatLng(-33.9209, 151.2552),
  'Surry Hills 2010': LatLng(-33.8834, 151.2129),
  'Parramatta 2150': LatLng(-33.8150, 151.0011),
  'Newcastle 2300': LatLng(-32.9283, 151.7817),
};

double distanceKm(LatLng a, RallyProgram b) {
  if (b.latitude == null || b.longitude == null) return double.infinity;
  const earthRadiusKm = 6371.0;
  final dLat = (b.latitude! - a.latitude) * math.pi / 180;
  final dLon = (b.longitude! - a.longitude) * math.pi / 180;
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(a.latitude * math.pi / 180) *
          math.cos(b.latitude! * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return 2 * earthRadiusKm * math.asin(math.sqrt(h));
}

class RallyProgram {
  const RallyProgram({
    required this.name,
    required this.sport,
    required this.venue,
    required this.suburb,
    required this.postcode,
    required this.schedule,
    required this.time,
    required this.latitude,
    required this.longitude,
  });
  final String name, sport, venue, suburb, postcode, schedule, time;
  final double? latitude, longitude;

  static Future<List<RallyProgram>> load() async {
    final sources = await Future.wait(
      [
        'assets/nsw_programs.json',
        'assets/rally4ever_programs.json',
      ].map(rootBundle.loadString),
    );
    final records = sources
        .expand(
          (source) =>
              ((jsonDecode(source) as Map<String, dynamic>)['programs']
                  as List<dynamic>),
        )
        .whereType<Map>()
        .map((raw) => Map<String, dynamic>.from(raw))
        .where((item) => item['status'] == 'active');
    final merged = <String, RallyProgram>{};
    for (final item in records) {
      final suburb = item['suburb'] as String? ?? '';
      final fallback = _fallbackCoordinate(suburb);
      final program = RallyProgram(
        name: item['name'] as String? ?? 'RALLY4EVER program',
        sport: item['sport'] as String? ?? 'tennis',
        venue:
            (item['venueName'] as String?) ??
            (suburb.isNotEmpty ? suburb : 'Venue to be confirmed'),
        suburb: suburb,
        postcode: item['postcode'] as String? ?? '',
        schedule: item['scheduleText'] as String? ?? 'Schedule to be confirmed',
        time: item['timeText'] as String? ?? '',
        latitude: (item['latitude'] as num?)?.toDouble() ?? fallback?.latitude,
        longitude:
            (item['longitude'] as num?)?.toDouble() ?? fallback?.longitude,
      );
      merged.putIfAbsent('${program.sport}|${program.name}', () => program);
    }
    return merged.values.toList();
  }
}

LatLng? _fallbackCoordinate(String suburb) => switch (suburb.toLowerCase()) {
  'ultimo' => const LatLng(-33.8815, 151.1972),
  'richmond' => const LatLng(-33.5999, 150.7511),
  'grafton' => const LatLng(-29.6917, 152.9333),
  'wodonga' => const LatLng(-36.1241, 146.8818),
  'st kilda' => const LatLng(-37.8676, 144.9800),
  'carrara' => const LatLng(-28.0200, 153.3640),
  _ => null,
};

class Welcome extends StatefulWidget {
  const Welcome({super.key, required this.next});
  final VoidCallback next;
  @override
  State<Welcome> createState() => _WelcomeState();
}

class _WelcomeState extends State<Welcome> {
  final pc = PageController();
  int i = 0;
  final data = [
    (
      'Find your\nprogram',
      'Free, accessible tennis and pickleball in 50+ places across Australia.',
      red,
    ),
    (
      'Find your\npeople',
      'No experience needed. Rackets and balls are provided. Just come along and have a hit.',
      navy,
    ),
    (
      'Play. Connect.\nFeel better.',
      'A regular, low-pressure way to get moving and meet people near you.',
      const Color(0xffffb1b5),
    ),
  ];
  @override
  Widget build(BuildContext c) {
    final d = data[i];
    final dark = d.$3 == navy;
    return Scaffold(
      backgroundColor: d.$3,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                children: [
                  Logo(light: !dark && i < 2),
                  const Spacer(),
                  TextButton(
                    onPressed: widget.next,
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        color: dark || i == 0 ? Colors.white : navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: PageView.builder(
                  controller: pc,
                  itemCount: 3,
                  onPageChanged: (v) => setState(() => i = v),
                  itemBuilder: (_, x) {
                    final e = data[x];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Spacer(),
                        OnboardingImage(
                          assetPath: [
                            'assets/candid_photo.jpg.webp',
                            'assets/group.jpg.webp',
                            'assets/lmfo.jpg.webp',
                          ][x],
                        ),
                        const SizedBox(height: 30),
                        Text(
                          e.$1,
                          style: Theme.of(c).textTheme.headlineLarge!.copyWith(
                            color: x == 2 ? navy : Colors.white,
                            fontSize: 38,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          e.$2,
                          style: TextStyle(
                            color: x == 2 ? navy : Colors.white,
                            fontSize: 15,
                            height: 1.4,
                          ),
                        ),
                        const Spacer(),
                      ],
                    );
                  },
                ),
              ),
              Row(
                children: List.generate(
                  3,
                  (x) => Container(
                    width: x == i ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Button(
                label: i == 2 ? 'Get started' : 'Continue',
                dark: dark,
                onTap: () => i == 2
                    ? widget.next()
                    : pc.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    required this.currentLocation,
    required this.back,
    required this.select,
  });
  final String currentLocation;
  final VoidCallback back;
  final ValueChanged<String> select;
  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  final _search = TextEditingController();
  final _locations = const [
    'Bondi 2026',
    'Bondi Junction 2022',
    'Coogee 2034',
    'Surry Hills 2010',
    'Parramatta 2150',
    'Newcastle 2300',
  ];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.toLowerCase();
    final matches = _locations
        .where((item) => item.toLowerCase().contains(query))
        .toList();
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  BackButton(onPressed: widget.back),
                  const SizedBox(width: 6),
                  Text(
                    'Choose your play area',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter a suburb or postcode to find programs near the area you choose.',
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _search,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search suburb or postcode',
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Suggested areas',
                style: TextStyle(fontWeight: FontWeight.w900, color: navy),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.separated(
                  itemCount: matches.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final location = matches[index];
                    final selected = location == widget.currentLocation;
                    return InkWell(
                      onTap: () => widget.select(location),
                      borderRadius: BorderRadius.circular(18),
                      child: CardBox(
                        child: Row(
                          children: [
                            const Icon(Icons.location_on_outlined, color: red),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                location,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            if (selected)
                              const Icon(Icons.check_circle, color: red),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_search.text.trim().isNotEmpty && matches.isEmpty)
                Button(
                  label: 'Use “${_search.text.trim()}”',
                  onTap: () => widget.select(_search.text.trim()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class Logo extends StatelessWidget {
  const Logo({super.key, this.light = false});
  final bool light;
  @override
  Widget build(BuildContext c) =>
      Image.asset('assets/icon/icon.png', width: 38, height: 38);
}

class Button extends StatelessWidget {
  const Button({super.key, required this.label, this.onTap, this.dark = false});
  final String label;
  final VoidCallback? onTap;
  final bool dark;
  @override
  Widget build(BuildContext c) => SizedBox(
    width: double.infinity,
    height: 52,
    child: FilledButton(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: dark ? navy : red,
        shape: const StadiumBorder(),
      ),
      child: Text(label),
    ),
  );
}

class CardBox extends StatelessWidget {
  const CardBox({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext c) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
    ),
    child: child,
  );
}

class Avatar extends StatelessWidget {
  const Avatar(this.text, {super.key, this.size = 38});
  final String text;
  final double size;
  @override
  Widget build(BuildContext c) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: const BoxDecoration(shape: BoxShape.circle, color: navy),
    child: Text(
      text,
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: size * .35,
      ),
    ),
  );
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext c) => Text(
    text,
    style: const TextStyle(
      color: Color(0xff267447),
      fontSize: 11,
      fontWeight: FontWeight.w800,
    ),
  );
}

class SessionCard extends StatelessWidget {
  const SessionCard(
    this.title,
    this.place,
    this.detail,
    this.tag,
    this.onTap, {
    super.key,
  });
  final String title, place, detail, tag;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext c) => InkWell(
    onTap: onTap,
    child: CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tag(tag),
          Text(
            title,
            style: const TextStyle(color: navy, fontWeight: FontWeight.w800),
          ),
          Text(place),
          Text(detail),
        ],
      ),
    ),
  );
}

class Info extends StatelessWidget {
  const Info(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, color: red, size: 17),
        const SizedBox(width: 8),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class Question extends StatelessWidget {
  const Question(this.title, this.options, {super.key});
  final String title;
  final List<String> options;
  @override
  Widget build(BuildContext c) => CardBox(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, color: navy),
        ),
        Wrap(
          spacing: 6,
          children: options
              .map(
                (x) => ChoiceChip(
                  label: Text(
                    x,
                    style: TextStyle(
                      color: x == options.last ? Colors.white : navy,
                    ),
                  ),
                  selected: x == options.last,
                  onSelected: (_) {},
                  selectedColor: navy,
                ).build(c),
              )
              .toList(),
        ),
      ],
    ),
  );
}

class SetRow extends StatelessWidget {
  const SetRow(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.all(9),
    child: Row(
      children: [
        Icon(icon, color: navy),
        const SizedBox(width: 10),
        Text(text),
        const Spacer(),
        const Icon(Icons.chevron_right),
      ],
    ),
  );
}

class Support extends StatelessWidget {
  const Support(this.name, this.phone, {super.key});
  final String name, phone;
  Future<void> _call(BuildContext context) async {
    final number = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final opened = await launchUrl(
      Uri(scheme: 'tel', path: number),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to call $phone on this device.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Call $name on $phone',
    child: Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _call(context),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(name),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.call, color: red, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    phone,
                    style: const TextStyle(
                      color: navy,
                      fontWeight: FontWeight.w800,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class Mini extends StatelessWidget {
  const Mini(this.icon, this.text, {super.key});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext c) => SizedBox(
    width: 155,
    child: CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: navy),
          Text(text),
        ],
      ),
    ),
  );
}

class OnboardingImage extends StatelessWidget {
  const OnboardingImage({super.key, required this.assetPath});

  final String assetPath;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(26),
    child: Image.asset(
      assetPath,
      height: 325,
      width: double.infinity,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
    ),
  );
}

class CourtArt extends StatelessWidget {
  const CourtArt({super.key, required this.dark});
  final bool dark;
  @override
  Widget build(BuildContext c) => Container(
    height: 190,
    decoration: BoxDecoration(
      color: dark ? const Color(0xff79a66f) : Colors.white24,
      borderRadius: BorderRadius.circular(26),
    ),
  );
}

class MapPaint extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    c.drawColor(const Color(0xffedf4ef), BlendMode.srcOver);
    for (final p in [Offset(s.width * .28, 260), Offset(s.width * .62, 340)]) {
      c.drawCircle(p, 16, Paint()..color = navy);
    }
    c.drawCircle(Offset(s.width * .3, 220), 18, Paint()..color = red);
  }

  @override
  bool shouldRepaint(MapPaint old) => false;
}
