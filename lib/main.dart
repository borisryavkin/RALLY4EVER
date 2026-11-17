import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import 'session_feedback_notifications.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const RallyApp());

  // Reminder setup is non-critical and can block on an Android platform call
  // on older devices. Never hold the first Flutter frame behind it.
  unawaited(
    SessionFeedbackNotifications.initialize().catchError((Object error) {
      debugPrint('Unable to initialise session feedback notifications: $error');
    }),
  );
}

const red = Color(0xffff4b4d),
    navy = Color(0xff001751),
    beige = Color(0xfff5f1ee),
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

class MemberData {
  String firstName = '';
  String postcode = '';
  String email = '';
  String ageRange = '25–34';
  String gender = 'Woman';
  String accessNeed = 'No';
  String currentActivity = 'Studying';
  String referral = 'Uni / campus';
  String referralOther = '';
  String loneliness = 'Sometimes';
  String satisfaction = '6';
  String culturalBackground = 'Born outside Australia';
  bool useInReports = true;
  bool wellbeingCheckIns = true;
  bool showInWhosGoing = true;
  bool marketingEmails = false;
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

class RallyApp extends StatefulWidget {
  const RallyApp({super.key});
  @override
  State<RallyApp> createState() => _RallyAppState();
}

class MyApp extends RallyApp {
  const MyApp({super.key});
}

class _RallyAppState extends State<RallyApp> {
  String route = 'welcome';
  int tab = 0;
  final navigatorKey = GlobalKey<NavigatorState>();
  Position? position;
  String playLocation = 'Bondi 2026';
  final member = MemberData();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requestLocation());
  }

  Future<void> _requestLocation() async {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.location_on, color: red),
        title: const Text('Find events near you'),
        content: const Text(
          'Rally4ever uses your location to find nearby Rally4ever events.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Allow location'),
          ),
        ],
      ),
    );
    if (accepted != true || !await Geolocator.isLocationServiceEnabled()) {
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always) {
      final value = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => position = value);
    }
  }

  void go(String value) => setState(() => route = value);
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey,
    title: 'Rally4ever',
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: beige,
      colorScheme: const ColorScheme.light(
        primary: red,
        secondary: navy,
        surface: Colors.white,
        onSurface: ink,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w900,
          height: 1,
          color: navy,
        ),
        headlineMedium: TextStyle(
          fontSize: 25,
          fontWeight: FontWeight.w900,
          height: 1.05,
          color: navy,
        ),
        titleLarge: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: navy,
        ),
        bodyMedium: TextStyle(color: ink, height: 1.4),
        bodySmall: TextStyle(color: Color(0xff71809e)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        indicatorColor: navy,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : const Color(0xff71809e),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? Colors.white
                : const Color(0xff71809e),
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    ),
    home: AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: switch (route) {
        'welcome' => Welcome(
          key: const ValueKey('welcome'),
          next: () => go('account'),
        ),
        'account' => Account(
          key: const ValueKey('account'),
          onContinue: (email) => setState(() {
            member.email = email.trim();
            route = member.email.toLowerCase() == 'coach@rally4ever.org'
                ? 'coachToday'
                : 'aboutYou';
          }),
        ),
        'aboutYou' => AboutYou(
          key: const ValueKey('aboutYou'),
          member: member,
          done: () => go('home'),
        ),
        'coachToday' => CoachToday(
          key: const ValueKey('coachToday'),
          back: () => go('account'),
          roster: () => go('roster'),
        ),
        'roster' => Roster(
          key: const ValueKey('roster'),
          back: () => go('coachToday'),
        ),
        'session' => Session(
          key: const ValueKey('session'),
          back: () => go('home'),
          checkIn: () => go('checkin'),
        ),
        'checkin' => CheckIn(
          key: const ValueKey('checkin'),
          next: () => go('waiver'),
        ),
        'qrCheckin' => QrCheckIn(
          key: const ValueKey('qrCheckin'),
          back: () => go('home'),
          checkedIn: () => go('waiver'),
        ),
        'waiver' => Waiver(
          key: const ValueKey('waiver'),
          next: () => go('post'),
        ),
        'post' => Post(key: const ValueKey('post'), next: () => go('home')),
        'locationPicker' => LocationPicker(
          key: const ValueKey('locationPicker'),
          currentLocation: playLocation,
          back: () => go('home'),
          select: (location) => setState(() {
            playLocation = location;
            route = 'home';
          }),
        ),
        _ => Home(
          key: const ValueKey('home'),
          tab: tab,
          position: position,
          onTab: (v) => setState(() => tab = v),
          quickCheckIn: () => go('qrCheckin'),
          session: () => go('session'),
          playLocation: playLocation,
          changeLocation: () => go('locationPicker'),
          member: member,
          editMember: () => go('aboutYou'),
        ),
      },
    ),
  );
}

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

class Account extends StatefulWidget {
  const Account({super.key, required this.onContinue});
  final ValueChanged<String> onContinue;
  @override
  State<Account> createState() => _AccountState();
}

class _AccountState extends State<Account> {
  final _email = TextEditingController();

  void _continue() {
    FocusManager.instance.primaryFocus?.unfocus();
    widget.onContinue(_email.text);
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 25),
            const Logo(),
            const Spacer(),
            Text(
              'Join the\ncommunity',
              style: Theme.of(c).textTheme.headlineLarge,
            ),
            const SizedBox(height: 12),
            const Text("It's free and takes about two minutes."),
            const SizedBox(height: 22),
            const Text(
              'Email',
              style: TextStyle(fontWeight: FontWeight.w700, color: navy),
            ),
            const SizedBox(height: 6),
            TextField(
              key: Key('emailField'),
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _continue(),
              decoration: InputDecoration(hintText: 'you@example.com'),
            ),
            const SizedBox(height: 14),
            Button(label: 'Continue', onTap: _continue),
            const Divider(height: 28),
            OutlinedButton.icon(
              onPressed: () => widget.onContinue(''),
              icon: const Icon(Icons.g_mobiledata),
              label: const Text('Continue with Google'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: navy,
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => widget.onContinue(''),
              icon: const Icon(Icons.apple),
              label: const Text('Continue with Apple'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                foregroundColor: navy,
              ),
            ),
            const Spacer(),
            const Center(
              child: Text(
                'Already a member? Sign in',
                style: TextStyle(color: navy, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class AboutYou extends StatefulWidget {
  const AboutYou({super.key, required this.member, required this.done});
  final MemberData member;
  final VoidCallback done;
  @override
  State<AboutYou> createState() => _AboutYouState();
}

class _AboutYouState extends State<AboutYou> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == 4) {
      widget.done();
    } else {
      _pages.nextPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'About you',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.done,
                  child: const Text(
                    'Skip',
                    style: TextStyle(color: navy, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              'Step ${_page + 1} ${_page == 0 ? 'required' : 'of 4 · optional'}',
              style: const TextStyle(fontSize: 12, color: Color(0xff71809e)),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: (_page + 1) / 5,
              minHeight: 5,
              color: red,
              backgroundColor: const Color(0xffe8dfda),
              borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: PageView(
                controller: _pages,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (value) => setState(() => _page = value),
                children: [
                  AboutBasics(
                    member: widget.member,
                    refresh: () => setState(() {}),
                  ),
                  AboutResearch(
                    member: widget.member,
                    refresh: () => setState(() {}),
                  ),
                  AboutAccess(
                    member: widget.member,
                    refresh: () => setState(() {}),
                  ),
                  AboutWellbeing(
                    member: widget.member,
                    refresh: () => setState(() {}),
                  ),
                  AboutConsent(
                    member: widget.member,
                    refresh: () => setState(() {}),
                  ),
                ],
              ),
            ),
            Button(
              label: _page == 4 ? 'Save and find a program' : 'Next',
              onTap: _next,
            ),
          ],
        ),
      ),
    ),
  );
}

class AboutBasics extends StatelessWidget {
  const AboutBasics({super.key, required this.member, required this.refresh});
  final MemberData member;
  final VoidCallback refresh;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Text(
        'Tell us a little about you',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 22),
      const Text('First name', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      TextFormField(
        key: const Key('firstNameField'),
        initialValue: member.firstName,
        textCapitalization: TextCapitalization.words,
        onChanged: (value) => member.firstName = value.trim(),
        decoration: const InputDecoration(hintText: 'Your first name'),
      ),
      const SizedBox(height: 16),
      const Text('Postcode', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      TextFormField(
        key: const Key('postcodeField'),
        initialValue: member.postcode,
        keyboardType: TextInputType.number,
        onChanged: (value) => member.postcode = value.trim(),
        decoration: const InputDecoration(hintText: 'Your postcode'),
      ),
      const SizedBox(height: 18),
      const Text('Age range', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      ChoiceChips(
        labels: const ['Under 18', '18–24', '25–34', '35–49', '50–64', '65+'],
        selectedLabel: member.ageRange,
        onSelected: (value) {
          member.ageRange = value;
          refresh();
        },
      ),
      const SizedBox(height: 20),
      const CardBox(
        child: Text(
          'ⓘ  We use your postcode to show programs nearby. It’s never shown to other members.',
          style: TextStyle(fontSize: 12),
        ),
      ),
    ],
  );
}

class AboutResearch extends StatelessWidget {
  const AboutResearch({super.key, required this.member, required this.refresh});
  final MemberData member;
  final VoidCallback refresh;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const CardBox(
        child: Text(
          'Optional: help us help more people\n\nYour answers are grouped with others so we can show funders who we reach. Skip anything you like.',
        ),
      ),
      const SizedBox(height: 18),
      const Text('Gender', style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      ChoiceChips(
        labels: const [
          'Woman',
          'Man',
          'Non-binary',
          'I use another term',
          'Prefer not to say',
        ],
        selectedLabel: member.gender,
        onSelected: (value) {
          member.gender = value;
          refresh();
        },
      ),
      const SizedBox(height: 18),
      const Text(
        'Language spoken at home',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      const TextField(
        decoration: InputDecoration(hintText: 'English, Russian'),
      ),
      const SizedBox(height: 18),
      const Text(
        'Cultural background',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      CardBox(
        child: Column(
          children: [
            CheckboxListTile(
              value:
                  member.culturalBackground ==
                  'Aboriginal and/or Torres Strait Islander',
              activeColor: red,
              onChanged: (value) {
                if (value == true) {
                  member.culturalBackground =
                      'Aboriginal and/or Torres Strait Islander';
                  refresh();
                }
              },
              title: const Text('Aboriginal and/or Torres Strait Islander'),
            ),
            CheckboxListTile(
              value: member.culturalBackground == 'Born outside Australia',
              activeColor: red,
              onChanged: (value) {
                if (value == true) {
                  member.culturalBackground = 'Born outside Australia';
                  refresh();
                }
              },
              title: const Text('Born outside Australia'),
            ),
            CheckboxListTile(
              value: member.culturalBackground == 'Prefer not to say',
              activeColor: red,
              onChanged: (value) {
                if (value == true) {
                  member.culturalBackground = 'Prefer not to say';
                  refresh();
                }
              },
              title: const Text('Prefer not to say'),
            ),
          ],
        ),
      ),
    ],
  );
}

class AboutAccess extends StatelessWidget {
  const AboutAccess({super.key, required this.member, required this.refresh});
  final MemberData member;
  final VoidCallback refresh;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      const Text(
        'Do you have a disability or access need?',
        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
      ),
      const SizedBox(height: 6),
      const Text('This helps coaches set up sessions so everyone can join in.'),
      const SizedBox(height: 10),
      ChoiceChips(
        labels: const ['Yes', 'No', 'Prefer not to say'],
        selectedLabel: member.accessNeed,
        onSelected: (value) {
          member.accessNeed = value;
          refresh();
        },
      ),
      const SizedBox(height: 20),
      const Text(
        'Right now, are you…',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      CardBox(
        child: RadioGroup<String>(
          groupValue: member.currentActivity,
          onChanged: (value) {
            if (value != null) {
              member.currentActivity = value;
              refresh();
            }
          },
          child: Column(
            children: ['Working', 'Studying', 'Looking for work', 'Retired']
                .map(
                  (value) => RadioListTile<String>(
                    value: value,
                    activeColor: red,
                    title: Text(value),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'How did you hear about us?',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 8),
      ChoiceChips(
        labels: const [
          'Friend',
          'Uni / campus',
          'Social media',
          'GP or health worker',
          'Local club',
          'Other',
        ],
        selectedLabel: member.referral,
        onSelected: (value) {
          member.referral = value;
          refresh();
        },
      ),
      if (member.referral == 'Other') ...[
        const SizedBox(height: 14),
        const Text(
          'Where did you hear about RALLY4EVER?',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        TextField(
          key: const Key('otherReferralField'),
          controller: TextEditingController.fromValue(
            TextEditingValue(
              text: member.referralOther,
              selection: TextSelection.collapsed(
                offset: member.referralOther.length,
              ),
            ),
          ),
          onChanged: (value) => member.referralOther = value,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            hintText: 'Tell us where you heard about us',
          ),
        ),
      ],
    ],
  );
}

class AboutWellbeing extends StatelessWidget {
  const AboutWellbeing({
    super.key,
    required this.member,
    required this.refresh,
  });
  final MemberData member;
  final VoidCallback refresh;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Text(
        'How have you been feeling lately?',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'We’ll ask again every few months so we can see if the programs are helping.',
      ),
      const SizedBox(height: 18),
      CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How often do you feel lonely?',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ChoiceChips(
              labels: const ['Never', 'Rarely', 'Sometimes', 'Often', 'Always'],
              selectedLabel: member.loneliness,
              onSelected: (value) {
                member.loneliness = value;
                refresh();
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      CardBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Overall, how satisfied are you with your life?',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ChoiceChips(
              labels: const [
                '0',
                '1',
                '2',
                '3',
                '4',
                '5',
                '6',
                '7',
                '8',
                '9',
                '10',
              ],
              selectedLabel: member.satisfaction,
              onSelected: (value) {
                member.satisfaction = value;
                refresh();
              },
            ),
          ],
        ),
      ),
    ],
  );
}

class AboutConsent extends StatelessWidget {
  const AboutConsent({super.key, required this.member, required this.refresh});
  final MemberData member;
  final VoidCallback refresh;
  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Text(
        'Your info, your call',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 18),
      const Text(
        '♧  We never sell your data or share anything that identifies you.\n\n◷  Reports only ever use grouped numbers, like “60% of members are students”.\n\n⌕  Change these or delete your data any time in Profile.',
      ),
      const SizedBox(height: 20),
      CardBox(
        child: Column(
          children: [
            SwitchListTile(
              value: member.useInReports,
              activeThumbColor: red,
              onChanged: (value) {
                member.useInReports = value;
                refresh();
              },
              title: const Text('Use my answers in reports'),
              subtitle: const Text('De-identified, grouped only'),
            ),
            const Divider(),
            SwitchListTile(
              value: member.wellbeingCheckIns,
              activeThumbColor: red,
              onChanged: (value) {
                member.wellbeingCheckIns = value;
                refresh();
              },
              title: const Text('Wellbeing check-ins'),
              subtitle: const Text('A 20-second question after sessions'),
            ),
            const Divider(),
            SwitchListTile(
              value: member.showInWhosGoing,
              activeThumbColor: red,
              onChanged: (value) {
                member.showInWhosGoing = value;
                refresh();
              },
              title: const Text('Show me in “Who’s going”'),
              subtitle: const Text('First name and photo only'),
            ),
            const Divider(),
            SwitchListTile(
              value: member.marketingEmails,
              activeThumbColor: red,
              onChanged: (value) {
                member.marketingEmails = value;
                refresh();
              },
              title: const Text('News and fundraising emails'),
            ),
          ],
        ),
      ),
    ],
  );
}

class ChoiceChips extends StatelessWidget {
  const ChoiceChips({
    super.key,
    required this.labels,
    required this.selectedLabel,
    required this.onSelected,
  });
  final List<String> labels;
  final String selectedLabel;
  final ValueChanged<String> onSelected;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 7,
    runSpacing: 7,
    children: labels
        .map(
          (label) => ChoiceChip(
            label: Text(label),
            selected: selectedLabel == label,
            selectedColor: navy,
            labelStyle: TextStyle(
              color: selectedLabel == label ? Colors.white : navy,
              fontSize: 12,
            ),
            onSelected: (_) => onSelected(label),
          ),
        )
        .toList(),
  );
}

class CoachToday extends StatelessWidget {
  const CoachToday({super.key, required this.back, required this.roster});
  final VoidCallback back;
  final VoidCallback roster;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BackButton(onPressed: back),
                const Spacer(),
                const Logo(),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Today, Wed 6:30pm',
              style: TextStyle(color: Color(0xff71809e)),
            ),
            Text(
              'Weeknight Rally',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const Text(
              'Waverley Park · Coach Dan',
              style: TextStyle(color: Color(0xff71809e)),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 22),
              decoration: BoxDecoration(
                color: navy,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Column(
                children: [
                  Text(
                    'Members scan this to check in',
                    style: TextStyle(
                      color: Color(0xffffb1b5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 14),
                  CoachQr(),
                  SizedBox(height: 10),
                  Text(
                    'Refreshes automatically every session',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Row(
              children: [
                Expanded(
                  child: CoachStat(number: '7', label: 'checked in'),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: CoachStat(number: '9', label: 'booked'),
                ),
              ],
            ),
            const Spacer(),
            Button(label: 'View roster', onTap: roster),
          ],
        ),
      ),
    ),
  );
}

class CoachQr extends StatelessWidget {
  const CoachQr({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: 130,
    height: 130,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
    ),
    child: GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 81,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 9,
      ),
      itemBuilder: (_, index) {
        final row = index ~/ 9;
        final col = index % 9;
        final finder =
            (row < 3 && col < 3) ||
            (row < 3 && col > 5) ||
            (row > 5 && col < 3);
        final filled = finder || ((row * 7 + col * 11 + row * col) % 5 < 2);
        return ColoredBox(color: filled ? navy : Colors.white);
      },
    ),
  );
}

class CoachStat extends StatelessWidget {
  const CoachStat({super.key, required this.number, required this.label});
  final String number, label;
  @override
  Widget build(BuildContext context) => CardBox(
    child: Column(
      children: [
        Text(number, style: const TextStyle(color: red, fontSize: 21)),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xff71809e)),
        ),
      ],
    ),
  );
}

class Roster extends StatelessWidget {
  const Roster({super.key, required this.back});
  final VoidCallback back;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                BackButton(onPressed: back),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Roster',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Text(
                      'Weeknight Rally · 9 booked',
                      style: TextStyle(fontSize: 11, color: Color(0xff71809e)),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const CardBox(
              child: Column(
                children: [
                  RosterRow(
                    initials: 'LP',
                    name: 'Louise',
                    detail: 'Waiver signed',
                    status: 'Checked in',
                    color: Color(0xffdff3e6),
                  ),
                  Divider(),
                  RosterRow(
                    initials: 'ML',
                    name: 'Mei',
                    detail: 'Waiver signed',
                    status: 'Checked in',
                    color: Color(0xffdff3e6),
                  ),
                  Divider(),
                  RosterRow(
                    initials: 'TB',
                    name: 'Tom',
                    detail: 'First session · waiver pending',
                    status: 'Arriving',
                    color: Color(0xffffefcf),
                  ),
                  Divider(),
                  RosterRow(
                    initials: 'AK',
                    name: 'Aisha',
                    detail: 'Waiver signed',
                    status: 'Not arrived',
                    color: Color(0xfff4f4f4),
                  ),
                ],
              ),
            ),
            const Spacer(),
            const Button(label: 'End session', dark: true),
          ],
        ),
      ),
    ),
  );
}

class RosterRow extends StatelessWidget {
  const RosterRow({
    super.key,
    required this.initials,
    required this.name,
    required this.detail,
    required this.status,
    required this.color,
  });
  final String initials, name, detail, status;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        Avatar(initials, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(
                detail,
                style: const TextStyle(fontSize: 10, color: Color(0xff71809e)),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            status,
            style: const TextStyle(
              fontSize: 10,
              color: navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class Home extends StatelessWidget {
  const Home({
    super.key,
    required this.tab,
    required this.onTab,
    required this.quickCheckIn,
    required this.session,
    required this.playLocation,
    required this.changeLocation,
    required this.member,
    required this.editMember,
    this.position,
  });
  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback quickCheckIn;
  final VoidCallback session;
  final String playLocation;
  final VoidCallback changeLocation;
  final MemberData member;
  final VoidCallback editMember;
  final Position? position;
  @override
  Widget build(BuildContext c) {
    final pages = [
      Play(
        session: session,
        location: playLocation,
        changeLocation: changeLocation,
        name: member.firstName,
        position: position,
      ),
      MapPage(session: session, position: position),
      Profile(member: member, edit: editMember),
      const Help(),
    ];
    return Scaffold(
      body: SafeArea(child: pages[tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab < 2 ? tab : tab + 1,
        onDestinationSelected: (index) {
          if (index == 2) {
            quickCheckIn();
            return;
          }
          onTab(index < 2 ? index : index - 1);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Play'),
          NavigationDestination(icon: Icon(Icons.map_outlined), label: 'Map'),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner_outlined),
            selectedIcon: Icon(Icons.qr_code_scanner),
            label: 'Check in',
          ),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Me'),
          NavigationDestination(
            icon: Icon(Icons.favorite_border),
            label: 'Help',
          ),
        ],
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

class Play extends StatefulWidget {
  const Play({
    super.key,
    required this.session,
    required this.location,
    required this.changeLocation,
    required this.name,
    this.position,
  });
  final VoidCallback session;
  final String location;
  final VoidCallback changeLocation;
  final String name;
  final Position? position;
  @override
  State<Play> createState() => _PlayState();
}

class _PlayState extends State<Play> {
  String sport = 'Tennis';
  late final Future<List<RallyProgram>> programs;

  @override
  void initState() {
    super.initState();
    programs = RallyProgram.load();
  }

  @override
  Widget build(BuildContext c) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Hi ${widget.name.isEmpty ? 'there' : widget.name}'),
              Text(
                'Play near you',
                style: Theme.of(c).textTheme.headlineMedium,
              ),
            ],
          ),
          const Spacer(),
          const Avatar('PS'),
        ],
      ),
      const SizedBox(height: 16),
      InkWell(
        onTap: widget.changeLocation,
        borderRadius: BorderRadius.circular(18),
        child: CardBox(
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined, color: red),
              const SizedBox(width: 8),
              Expanded(child: Text('Near ${widget.location}')),
              const Text(
                'Change',
                style: TextStyle(color: navy, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Container(
        height: 42,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: ['Tennis', 'Pickleball']
              .map(
                (choice) => Expanded(
                  child: InkWell(
                    onTap: () => setState(() => sport = choice),
                    borderRadius: BorderRadius.circular(21),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: sport == choice ? navy : Colors.transparent,
                        borderRadius: BorderRadius.circular(21),
                      ),
                      child: Text(
                        choice,
                        style: TextStyle(
                          color: sport == choice ? Colors.white : navy,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
      const SizedBox(height: 16),
      FutureBuilder<List<RallyProgram>>(
        future: programs,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator(color: red)),
            );
          }
          // The manually selected play area is the search origin. This keeps
          // “Near Bondi” results anchored to Bondi even if an emulator or a
          // stale device location reports somewhere else.
          final origin =
              playAreaCoordinates[widget.location] ??
              const LatLng(-33.8688, 151.2093);
          final matching =
              (snapshot.data ?? [])
                  .where(
                    (program) =>
                        program.sport.toLowerCase() == sport.toLowerCase(),
                  )
                  .map(
                    (program) => (
                      program: program,
                      distance: distanceKm(origin, program),
                    ),
                  )
                  .where((item) => item.distance <= 80)
                  .toList()
                ..sort((a, b) => a.distance.compareTo(b.distance));
          if (matching.isEmpty) {
            return CardBox(
              child: Text(
                'No active $sport programs are currently listed within 80 km of ${widget.location}.',
              ),
            );
          }
          return Column(
            children: matching
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SessionCard(
                      item.program.name,
                      '${item.distance.toStringAsFixed(1)} km · ${item.program.venue}',
                      '${item.program.schedule} ${item.program.time}'.trim(),
                      'Spots available',
                      widget.session,
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
      /*if (sport == 'Tennis') Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: navy,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "YOU'RE BOOKED IN",
              style: TextStyle(
                color: Color(0xffffb1b5),
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Sat Social',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            Text(
              'Sat 9:00am · Bondi Beach Courts',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SessionCard(sport == 'Tennis' ? 'Weeknight Rally' : 'Bondi Pickleball Social', sport == 'Tennis' ? 'Waverley Park · 1.8 km' : 'Bondi Beach Courts · 0.6 km', sport == 'Tennis' ? 'Wed 6:30pm · Rackets provided' : 'Tue 6:00pm · Paddles provided', sport == 'Tennis' ? 'Almost full' : 'Spots available', widget.session),
      const SizedBox(height: 12),
      SessionCard(sport == 'Tennis' ? 'Coogee Community Tennis' : 'Coogee Pickleball', sport == 'Tennis' ? 'Coogee Oval Courts · 3.2 km' : 'Coogee Oval Courts · 3.2 km', sport == 'Tennis' ? 'Sun 10:00am · All welcome' : 'Thu 10:00am · All welcome', 'Spots available', widget.session),*/
    ],
  );
}

class MapPage extends StatefulWidget {
  const MapPage({super.key, required this.session, this.position});
  final VoidCallback session;
  final Position? position;
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late final Future<List<RallyProgram>> programs;
  @override
  void initState() {
    super.initState();
    programs = RallyProgram.load();
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<List<RallyProgram>>(
    future: programs,
    builder: (context, snapshot) {
      final list = snapshot.data ?? const <RallyProgram>[];
      final mappable = list
          .where(
            (program) => program.latitude != null && program.longitude != null,
          )
          .toList();
      final centre = widget.position == null
          ? const LatLng(-27.8, 153.0)
          : LatLng(widget.position!.latitude, widget.position!.longitude);
      return Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: centre,
                initialZoom: widget.position == null ? 5.8 : 11,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'org.rally4ever.app',
                ),
                MarkerLayer(
                  markers: mappable
                      .map(
                        (program) => Marker(
                          point: LatLng(program.latitude!, program.longitude!),
                          width: 44,
                          height: 50,
                          child: Tooltip(
                            message: '${program.name}\n${program.venue}',
                            child: const Icon(
                              Icons.location_on,
                              color: red,
                              size: 42,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
          Positioned(
            top: 16,
            left: 18,
            right: 18,
            child: Material(
              color: Colors.white,
              elevation: 3,
              shadowColor: navy.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(28),
              child: TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: ink),
                  hintText: 'Search suburb or postcode',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(vertical: 15),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Material(
              color: beige,
              elevation: 14,
              shadowColor: navy.withValues(alpha: 0.22),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 9, 20, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xffd9d2cd),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          '${mappable.length} NSW programs',
                          style: Theme.of(c).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {},
                          child: const Text(
                            'List view',
                            style: TextStyle(
                              color: navy,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (snapshot.connectionState != ConnectionState.done)
                      const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(color: red),
                      )
                    else if (list.isEmpty)
                      const Text('No active NSW programs are available.')
                    else
                      SessionCard(
                        list.first.name,
                        '${list.first.venue} · ${list.first.suburb}',
                        '${list.first.schedule} ${list.first.time}'.trim(),
                        'Spots available',
                        widget.session,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class Session extends StatelessWidget {
  const Session({super.key, required this.back, required this.checkIn});
  final VoidCallback back, checkIn;
  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    BackButton(onPressed: back),
                    const Spacer(),
                    const Logo(),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Image.asset(
                    'assets/wavley.jpg',
                    height: 190,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),
                const Tag('Spots available'),
                const SizedBox(height: 10),
                Text(
                  'Weeknight Rally',
                  style: Theme.of(c).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Info(
                  Icons.calendar_today_outlined,
                  'Wednesday 1 Oct · 6:30–8:00pm',
                ),
                const Info(
                  Icons.location_on_outlined,
                  'Waverley Park, Bondi Junction',
                ),
                const Info(Icons.person_outline, 'Coach Dan'),
                const SizedBox(height: 14),
                const CardBox(
                  child: Text(
                    'Just bring yourself\n\nRackets and balls provided. Wear comfy clothes and joggers. Come as you are.',
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Avatar('P'),
                    Avatar('M'),
                    Avatar('T'),
                    SizedBox(width: 8),
                    Text(
                      '9 people are going',
                      style: TextStyle(
                        color: navy,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Button(
              label: 'Count me in',
              onTap: () async {
                await SessionFeedbackNotifications.scheduleForWeeknightRally();
                checkIn();
              },
            ),
          ),
        ],
      ),
    ),
  );
}

class CheckIn extends StatelessWidget {
  const CheckIn({super.key, required this.next});
  final VoidCallback next;
  @override
  Widget build(BuildContext c) => Scaffold(
    backgroundColor: navy,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Spacer(),
            const Text(
              'Weeknight Rally · 6:30pm',
              style: TextStyle(
                color: Color(0xffffb1b5),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Made it? Tap to\ncheck in',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 30,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: next,
              child: Container(
                width: 190,
                height: 190,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: red,
                  border: Border.all(color: const Color(0xff613057), width: 15),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.pan_tool_outlined,
                      color: Colors.white,
                      size: 44,
                    ),
                    Text(
                      "I'm here",
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            const Text(
              'Checking in lets your coach know you’ve arrived and helps us count who comes along.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xffc2cce7)),
            ),
            const SizedBox(height: 22),
            TextButton(
              onPressed: next,
              child: const Text(
                "Or scan the coach's QR code",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class QrCheckIn extends StatefulWidget {
  const QrCheckIn({super.key, required this.back, required this.checkedIn});
  final VoidCallback back;
  final VoidCallback checkedIn;

  @override
  State<QrCheckIn> createState() => _QrCheckInState();
}

class _QrCheckInState extends State<QrCheckIn> {
  final _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned || capture.barcodes.isEmpty) return;
    if (capture.barcodes.first.rawValue == null) return;
    setState(() => _hasScanned = true);
    _controller.stop();
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (mounted) widget.checkedIn();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: navy,
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 20, 12),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.back,
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close scanner',
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Quick check-in',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Scan your coach’s QR code',
                        style: TextStyle(color: Color(0xffffb1b5)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _controller.toggleTorch,
                  icon: const Icon(
                    Icons.flash_on_outlined,
                    color: Colors.white,
                  ),
                  tooltip: 'Toggle torch',
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onDetect,
                      errorBuilder: (context, error) => ColoredBox(
                        color: const Color(0xff172b60),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.no_photography_outlined,
                                  color: Color(0xffffb1b5),
                                  size: 42,
                                ),
                                const SizedBox(height: 14),
                                const Text(
                                  'Camera access is needed to scan a check-in code.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.white),
                                ),
                                const SizedBox(height: 14),
                                TextButton(
                                  onPressed: widget.back,
                                  child: const Text('Go back'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const IgnorePointer(child: _ScannerFrame()),
                    if (_hasScanned)
                      const ColoredBox(
                        color: Color(0xB3001751),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 58,
                              ),
                              SizedBox(height: 10),
                              Text(
                                'You’re checked in',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(30, 18, 30, 28),
            child: Text(
              'Hold the code inside the frame. Your check-in is confirmed as soon as it’s recognised.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xffc2cce7), height: 1.35),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ScannerFrame extends StatelessWidget {
  const _ScannerFrame();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 230,
      height: 230,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xffffb1b5), width: 3),
        borderRadius: BorderRadius.circular(24),
      ),
      child: const Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.only(bottom: 14),
          child: Icon(Icons.qr_code_2, color: Colors.white, size: 30),
        ),
      ),
    ),
  );
}

class Waiver extends StatefulWidget {
  const Waiver({super.key, required this.next});
  final VoidCallback next;
  @override
  State<Waiver> createState() => _WaiverState();
}

class _WaiverState extends State<Waiver> {
  bool yes = false;
  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Before you play',
              style: Theme.of(c).textTheme.headlineMedium,
            ),
            const SizedBox(height: 14),
            const Text(
              "You're checked in for Weeknight Rally. Since this is your first session, please read and accept this quick waiver.",
            ),
            const SizedBox(height: 14),
            const Expanded(
              child: CardBox(
                child: SingleChildScrollView(
                  child: Text(
                    'Participation and health acknowledgement\n\nI confirm that I am voluntarily taking part in a RALLY4EVER social session. I believe I am physically able to take part in reasonable, non-competitive play. If I have any injury, condition or concern that could affect my safety, I have told the session coach before playing.\n\nI understand there is a risk of injury, and I take part at my own risk.',
                    style: TextStyle(height: 1.55),
                  ),
                ),
              ),
            ),
            CheckboxListTile(
              value: yes,
              onChanged: (v) => setState(() => yes = v ?? false),
              activeColor: red,
              title: const Text("I've read this and I'm good to play."),
            ),
            Button(
              label: 'Agree and start playing',
              onTap: yes ? widget.next : null,
            ),
          ],
        ),
      ),
    ),
  );
}

class Post extends StatelessWidget {
  const Post({super.key, required this.next});
  final VoidCallback next;
  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '20-second check-in',
              style: TextStyle(color: ink, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            Text(
              'Thanks for coming\ntonight, Louise',
              style: Theme.of(c).textTheme.headlineMedium,
            ),
            const SizedBox(height: 18),
            const Question('How do you feel compared to before?', [
              'Worse',
              'The same',
              'Better',
            ]),
            const SizedBox(height: 14),
            const Question('Did you chat with someone new?', [
              'Yes',
              'Not this time',
            ]),
            const SizedBox(height: 14),
            const CardBox(
              child: TextField(
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: "Anything you'd like the coach to know?",
                  hintText: 'Optional',
                ),
              ),
            ),
            const Spacer(),
            Button(label: 'Send', onTap: next),
          ],
        ),
      ),
    ),
  );
}

class Profile extends StatelessWidget {
  const Profile({super.key, required this.member, required this.edit});
  final MemberData member;
  final VoidCallback edit;
  @override
  Widget build(BuildContext c) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 28),
      const Center(child: Avatar('PS', size: 74)),
      const SizedBox(height: 10),
      Center(
        child: Text(
          member.firstName.isEmpty ? 'Member' : member.firstName,
          style: TextStyle(
            color: navy,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      Center(
        child: Text(
          member.postcode.isEmpty
              ? 'Member since March 2026'
              : 'Postcode ${member.postcode} · Member since March 2026',
        ),
      ),
      const SizedBox(height: 20),
      CardBox(
        child: Text(
          '12 sessions · 7 people met\n${member.ageRange} · ${member.currentActivity}',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: red,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(height: 16),
      CardBox(
        child: Column(
          children: [
            InkWell(
              onTap: edit,
              child: const SetRow(Icons.edit_outlined, 'Edit my details'),
            ),
            const SetRow(Icons.shield_outlined, 'My data & privacy'),
            const SetRow(Icons.notifications_none, 'Session reminders'),
          ],
        ),
      ),
    ],
  );
}

class Help extends StatelessWidget {
  const Help({super.key});
  @override
  Widget build(BuildContext c) => ListView(
    padding: const EdgeInsets.all(22),
    children: [
      Text('Help', style: Theme.of(c).textTheme.headlineMedium),
      const SizedBox(height: 15),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: red,
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Need to talk to someone now?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Free, confidential support, 24 hours a day.',
              style: TextStyle(color: Colors.white),
            ),
            SizedBox(height: 14),
            Support('Lifeline', '13 11 14'),
            SizedBox(height: 8),
            Support('Beyond Blue', '1300 22 4636'),
          ],
        ),
      ),
      const SizedBox(height: 15),
      const Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          Mini(Icons.question_mark, 'FAQs'),
          Mini(Icons.accessibility_new, 'Access needs'),
          Mini(Icons.manage_accounts_outlined, 'My account'),
          Mini(Icons.shield_outlined, 'Privacy'),
        ],
      ),
      const SizedBox(height: 20),
      const Button(label: 'Message the RALLY4EVER team', dark: true),
    ],
  );
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
        Text(text),
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
                  label: Text(x),
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
          child: Row(
            children: [
              Text(name),
              const Spacer(),
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
