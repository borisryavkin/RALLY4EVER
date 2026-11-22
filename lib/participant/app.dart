import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:timezone/timezone.dart' as tz;

import '../shared/logo.dart';
import '../shared_widgets.dart' as shared;
import 'forms.dart';
import 'legal_text.dart';
import 'form_groups.dart';
import 'access.dart';
import 'catalogue.dart';
import 'catalogue_admin.dart';
import 'catalogue_photos.dart';
import 'coach_console.dart';
import 'repository.dart';
import 'theme.dart';
import 'user_avatar.dart';
import 'profile_summary.dart';

class ParticipantApp extends StatefulWidget {
  const ParticipantApp({
    super.key,
    this.repository,
    this.startupError,
    this.initialPage,
    this.initialEventId,
    this.cameraEnabled = true,
    this.mapTilesEnabled = true,
    this.lanTesting = const bool.fromEnvironment('LAN_TESTING'),
    this.lanHost = const String.fromEnvironment('LAN_HOST'),
  });
  final ParticipantRepository? repository;
  final String? startupError, initialPage, initialEventId;
  final bool cameraEnabled, mapTilesEnabled;
  final bool lanTesting;
  final String lanHost;
  @override
  State<ParticipantApp> createState() => _ParticipantAppState();
}

class _ParticipantAppState extends State<ParticipantApp>
    with WidgetsBindingObserver {
  String? pendingQrLink;
  late final ParticipantRepository repo =
      widget.repository ?? DisabledParticipantRepository();
  late String page =
      widget.initialPage ?? (repo.uid == null ? 'signin' : 'home');
  String? selectedId, selectedProgramId, error;
  Future<void> Function()? _lastFailedAction;
  String locationSearch = '';
  bool areaChosen = false;
  bool allAustralia = false;
  bool _locationRequestedThisSession = false;
  DateTime? _lastLocationFetch;
  bool busy = false, agreed = false, pendingSubmission = false;
  int get tab => switch (page) {
    'map' => 1,
    'profile' ||
    'account' ||
    'role' ||
    'adminAccess' ||
    'adminVenues' ||
    'adminSessions' ||
    'adminCatalogue' ||
    'coachTools' => 3,
    'help' => 4,
    'checkin' || 'scan' || 'waiting' || 'confirmed' => 2,
    'details' || 'agreements' => detailsReturn == 'profile' ? 3 : 2,
    _ => page.startsWith('profile') ? 3 : 0,
  };
  String detailsReturn = 'scan';
  bool editingProfile = false;
  final mapController = MapController();
  final verificationPanelKey = GlobalKey();
  final _expandedProgramGroups = <String>{};
  String _groupKey(List<Record> group) => eid(group.first);
  CheckInLink? scanned;
  Record? scanLocation;
  Record? people;
  double? previewDistance;
  String? locationError;
  final qrInput = TextEditingController();
  Timer? timer;
  MobileScannerController? scanner;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final initialLink =
        WidgetsBinding.instance.platformDispatcher.defaultRouteName;
    if (initialLink != '/') {
      _queueAppLink(initialLink);
      WidgetsBinding.instance.addPostFrameCallback((_) => changed());
    }
    selectedId = widget.initialEventId;
    error = widget.startupError;
    repo.addListener(changed);
    if (page == 'people' && event != null) {
      unawaited(
        repo.countedPeople(eid(event!)).then((value) {
          if (mounted) setState(() => people = value);
        }),
      );
    }

    timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  void _queueAppLink(String raw) {
    final candidate = raw.startsWith('/c/')
        ? 'https://rally4ever.org$raw'
        : raw;
    try {
      CheckInLink.parse(candidate);
      pendingQrLink = candidate;
    } on FormatException {
      // Ignore unrelated links; the same strict QR parser guards the scan flow.
    }
  }

  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async {
    _queueAppLink(routeInformation.uri.toString());
    changed();
    return true;
  }

  // Keeps role/claim access current without the user ever pressing
  // anything: a newly granted coach (or revoked one) picks it up the next
  // time they bring the app to the foreground, not just at sign-in.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      repo.stopBrowseLocation();
      return;
    }
    if (repo.uid != null) unawaited(repo.refreshAccess());
    // Coming back from the verification email's browser tab: silently
    // reload the Auth user and continue the moment it's picked up, no tap
    // required. A no-op once verified (or signed out) since repo.email is
    // only set while this device is on the account screen's "check your
    // inbox" state.
    if (repo.email != null && !repo.verified) {
      unawaited(repo.refreshVerification());
    }
    // "Returns to the app after a while": a single fresh fix on resume,
    // never a continuous stream -- this is the one place browse location
    // refreshes outside the first-open trigger in home()/map(). Also
    // retries right away (ignoring staleness) whenever the last attempt
    // didn't end up granted, so coming back from Settings after allowing
    // location picks it up immediately rather than waiting ten minutes.
    if (!areaChosen) {
      final stale =
          _lastLocationFetch == null ||
          DateTime.now().difference(_lastLocationFetch!) >
              const Duration(minutes: 10);
      if (stale || repo.locationStatus != 'granted' || repo.uid != null) {
        _requestBrowseLocation();
      }
    }
  }

  // One-shot per trigger (first open of Play/Map, or a stale resume) --
  // never called on every rebuild or every GPS tick. Reused by the list,
  // the map and distance sorting via selectedMapPoint below.
  void _requestBrowseLocation() {
    _lastLocationFetch = DateTime.now();
    unawaited(repo.requestBrowseLocation());
  }

  void changed() {
    if (!mounted) return;
    setState(() {
      if (repo.uid == null) {
        areaChosen = false;
        editingProfile = false;
        sport = 'All';
        detailsReturn = 'scan';
      }
      if (repo.uid != null &&
          repo.ready &&
          [
            'entry',
            'signin',
            'signup',
            'welcome1',
            'welcome2',
            'welcome3',
          ].contains(page)) {
        page =
            (repo.profile['firstName'] as String? ?? '').isEmpty ||
                (repo.profile['postcode'] as String? ?? '').isEmpty
            ? 'profile1'
            : 'home';
      }
      if (pendingQrLink != null && repo.uid != null && repo.ready) {
        qrInput.text = pendingQrLink!;
        pendingQrLink = null;
        page = 'scan';
      }
      if (page == 'role' && !repo.canCoach && !repo.canAdmin) {
        page = 'home';
        error =
            'Coach access was revoked. You can keep using participant tools.';
      }
      if (repo.uid == null &&
          ![
            'entry',
            'signin',
            'signup',
            'welcome1',
            'welcome2',
            'welcome3',
            'noapp',
            'forgot-password',
          ].contains(page)) {
        page = 'signin';
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    repo.removeListener(changed);
    if (widget.repository == null) repo.dispose();
    mapController.dispose();
    qrInput.dispose();
    unawaited(scanner?.dispose() ?? Future<void>.value());
    super.dispose();
  }

  Record? get event =>
      repo.events.where((e) => eid(e) == selectedId).firstOrNull ??
      repo.events
          .where(
            (e) =>
                dateOf(e['endsAt']).isAfter(repo.now()) &&
                (e['status'] != 'cancelled' || repo.countedIn(eid(e))) &&
                (sport == 'All' ||
                    (e['sport'] as String? ?? '').toLowerCase() ==
                        sport.toLowerCase()),
          )
          .firstOrNull ??
      repo.events.firstOrNull;
  String eid(Record e) => e['id'] as String? ?? e['eventId'] as String;
  void go(String next) {
    setState(() {
      page = next;
      if (next == 'home' || next == 'profile') {
        scanned = null;
        scanLocation = null;
        pendingSubmission = false;
      }
      error = null;
      agreed = false;
    });
  }

  Future<void> action(Future<void> Function() work) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await work();
      _lastFailedAction = null;
      // Just landed in "check your inbox" (signed up, or still unverified
      // after a stale "I've verified" tap): bring the panel into view and
      // get the keyboard out of the way, every time, not just once.
      if (repo.email != null && !repo.verified) {
        FocusManager.instance.primaryFocus?.unfocus();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final context = verificationPanelKey.currentContext;
          if (context != null) {
            unawaited(
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 200),
              ),
            );
          }
        });
      }
    } catch (e) {
      _lastFailedAction = work;
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (pendingSubmission) {
          pendingSubmission = false;
          unawaited(submitScan());
        }
      }
    }
  }

  void retryLastAction() {
    final work = _lastFailedAction;
    if (work != null) unawaited(action(work));
  }

  void select(Record e, String next) {
    selectedId = eid(e);
    previewDistance = null;
    locationError = null;
    go(next);
  }

  bool detailsComplete() =>
      [
        'firstName',
        'mobile',
      ].every((k) => (repo.profile[k] as String? ?? '').trim().isNotEmpty) &&
      ((repo.profile['emergencyContact'] as Map?)?['name'] as String? ?? '')
          .trim()
          .isNotEmpty &&
      ((repo.profile['emergencyContact'] as Map?)?['mobile'] as String? ?? '')
          .trim()
          .isNotEmpty;
  void nextAfterScan() {
    if (!mounted) return;
    detailsReturn = 'scan';
    if (!detailsComplete()) {
      detailsReturn = 'scan';
      go('details');
      return;
    }
    if (event != null &&
        (repo.missingForms(event!).isNotEmpty ||
            repo.unavailableForms(event!).isNotEmpty)) {
      go('agreements');
      return;
    }
    if (busy) {
      pendingSubmission = true;
    } else {
      unawaited(submitScan());
    }
  }

  Future<void> acceptQr(String raw) async {
    final link = CheckInLink.parse(raw);
    final target = repo.events
        .where((e) => e['code'] == link.eventCode)
        .firstOrNull;
    if (target == null) {
      throw const FormatException(
        'This event is not available. Ask your coach to refresh the QR.',
      );
    }
    // Location is advisory only -- the coach always confirms attendance
    // in person. A scan never fails just because location services are
    // off, permission was denied, or a fix couldn't be found in time;
    // the check-in still goes through, with distance left unknown.
    Record? position;
    try {
      position = await repo.location();
    } catch (_) {
      position = null;
    }
    if (!mounted) return;
    scanned = link;
    scanLocation = position;
    selectedId = eid(target);
    nextAfterScan();
  }

  Future<void> submitScan() async {
    if (scanned == null) {
      go('scan');
      return;
    }
    await action(() async {
      try {
        await repo.call('checkIn', {
          'eventCode': scanned!.eventCode,
          'secret': scanned!.secret,
          ...?scanLocation,
          'method': 'app',
        });
        go('waiting');
      } catch (e) {
        if (e.toString().contains('already checked in')) {
          go('waiting');
        } else {
          rethrow;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    initialRoute: '/',
    debugShowCheckedModeBanner: false,
    title: 'RALLY4EVER',
    theme: rallyTheme(),
    routes: {'/': (_) => rootView()},
    onGenerateInitialRoutes: (_) => [
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/'),
        builder: (_) => rootView(),
      ),
    ],
  );

  Widget rootView() => AnimatedBuilder(
    animation: repo,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) => ColoredBox(
        color: const Color(0xffe7e2de),
        child: Center(
          child: SizedBox(
            width: constraints.maxWidth,
            child: Column(
              // Without this, a Column's default cross-axis alignment
              // lets each child size itself to its own preferred width --
              // on a wide tablet, the page below (a Scaffold whose own
              // backgroundColor is meant to fill the whole screen, e.g.
              // onboarding's red) could end up narrower than the
              // viewport, exposing this background colour as bars down
              // either side instead. Stretching forces every page to
              // take the full width; each page's own content still
              // centres itself with a sensible max width (see frame()'s
              // maxWidth / intro()'s introViewport).
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.lanTesting)
                  Material(
                    key: const Key('lan-testing-banner'),
                    color: pink,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'LAN TESTING — DEVELOPMENT ONLY\n${widget.lanHost} · Emulators exposed to Wi-Fi. Demo data only.',
                          style: const TextStyle(
                            color: navy,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: AbsorbPointer(
                    absorbing: busy,
                    child: buildPage(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  Widget brand({bool light = false}) => Wordmark(
    height: 28,
    color: light ? Colors.white : navy,
    textStyle: TextStyle(
      fontFamily: 'Jellee',
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
      color: light ? Colors.white : navy,
    ),
  );
  // Below this width: phone layout (full-width bottom bar, content fills the
  // screen). At or above it: a side NavigationRail replaces the bottom bar,
  // and single-column content is centred with a readable max width instead
  // of stretching edge-to-edge across a tablet.
  static const wideBreakpoint = 840.0;
  static const wideContentMaxWidth = 720.0;
  bool isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= wideBreakpoint;

  Widget frame(
    BuildContext context, {
    String? title,
    required List<Widget> children,
    Widget? bottom,
    bool dark = false,
    bool navigation = false,
    VoidCallback? back,
    bool showTitleIcon = true,
    bool showAppBar = true,
    // A single-column form or onboarding-style screen reads better at a
    // narrower width than a list/map screen on a wide tablet; pass 560
    // for those (onboarding, sign-in, create account, About you, check-in).
    // Lists/maps/the main tabs keep the wider default.
    double? maxWidth,
  }) {
    final wide = isWide(context);
    final contentMaxWidth = maxWidth ?? wideContentMaxWidth;
    final content = SafeArea(
      top: !showAppBar,
      child: Column(
        children: [
          if (busy) const LinearProgressIndicator(minHeight: 3),
          Expanded(
            key: const Key('frame-content'),
            // The error banner lives inside this scrollable, rather than as
            // a fixed sibling, so a long message (or a short keyboard-
            // shrunk viewport) scrolls into view instead of overflowing.
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: wide ? contentMaxWidth : double.infinity,
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                  children: [
                    if (error != null || repo.streamError != null)
                      Container(
                        key: const Key('error-banner'),
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: error == googleSignInFailedMessage
                              ? cream
                              : pink,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              error ?? repo.streamError!,
                              style: const TextStyle(color: navy),
                            ),
                            if (error == googleSignInFailedMessage)
                              Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  spacing: 8,
                                  children: [
                                    TextButton(
                                      key: const Key('google-signin-use-email'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: navy,
                                      ),
                                      onPressed: busy
                                          ? null
                                          : () => go(
                                              repo.hasSignedInBefore
                                                  ? 'signin'
                                                  : 'signup',
                                            ),
                                      child: const Text('Use email instead'),
                                    ),
                                    TextButton(
                                      key: const Key('google-signin-retry'),
                                      style: TextButton.styleFrom(
                                        foregroundColor: navy,
                                      ),
                                      onPressed: busy ? null : retryLastAction,
                                      child: const Text('Try again'),
                                    ),
                                  ],
                                ),
                              )
                            else if (error != null && _lastFailedAction != null)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  key: const Key('retry-action'),
                                  onPressed: busy ? null : retryLastAction,
                                  child: const Text('Retry'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ...children,
                  ],
                ),
              ),
            ),
          ),
          if (bottom != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: bottom,
            ),
        ],
      ),
    );
    return Scaffold(
      backgroundColor: dark ? navy : cream,
      appBar: showAppBar
          ? AppBar(
              backgroundColor: dark ? navy : cream,
              foregroundColor: dark ? Colors.white : navy,
              leading: back != null ? BackButton(onPressed: back) : null,
              automaticallyImplyLeading: false,
              title: title != null
                  ? Text(
                      title,
                      style: TextStyle(color: dark ? Colors.white : navy),
                    )
                  : brand(light: dark),
              actions: [
                if (title != null && showTitleIcon)
                  Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: Icon(
                      Icons.sports_tennis,
                      color: dark ? pink : coral,
                      size: 19,
                    ),
                  ),
              ],
            )
          : null,
      body: navigation && wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                navRail(),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: navigation && !wide ? bottomNav() : null,
    );
  }

  static const _navLabels = ['Play', 'Map', 'Check in', 'Me', 'Help'];
  static const _navIcons = [
    Icons.sports_tennis,
    Icons.map_outlined,
    Icons.qr_code_scanner,
    Icons.person_outline,
    Icons.favorite_border,
  ];
  void _navigateTo(int i) {
    go(['home', 'map', 'checkin', 'profile', 'help'][i]);
  }

  Widget bottomNav() => NavigationBar(
    selectedIndex: tab,
    onDestinationSelected: _navigateTo,
    destinations: [
      for (var i = 0; i < _navLabels.length; i++)
        NavigationDestination(icon: Icon(_navIcons[i]), label: _navLabels[i]),
    ],
  );
  Widget navRail() => NavigationRail(
    selectedIndex: tab,
    labelType: NavigationRailLabelType.all,
    onDestinationSelected: _navigateTo,
    destinations: [
      for (var i = 0; i < _navLabels.length; i++)
        NavigationRailDestination(
          icon: Icon(_navIcons[i]),
          label: Text(_navLabels[i]),
        ),
    ],
  );

  Widget buildPage(BuildContext context) {
    if (page.startsWith('welcome')) {
      return intro(
        context,
        int.tryParse(page.replaceFirst('welcome', '')) ?? 1,
      );
    }
    if (page == 'entry') {
      return frame(
        context,
        maxWidth: 560,
        back: () => go('welcome1'),
        children: [
          EntryScreen(
            repository: repo,
            onAction: action,
            busy: busy,
            onUseEmail: () => go('signup'),
            onCheckInWithoutAccount: () => go('noapp'),
            onSignIn: () => go('signin'),
          ),
        ],
      );
    }
    if (page == 'signin') {
      return frame(
        context,
        maxWidth: 560,
        back: () => go('entry'),
        children: [
          SignInScreen(
            key: const Key('sign-in-screen'),
            repository: repo,
            onAction: action,
            busy: busy,
            onForgotPassword: () => go('forgot-password'),
            onCreateAccount: () => go('entry'),
            onCheckInWithoutAccount: () => go('noapp'),
          ),
        ],
      );
    }
    if (page == 'signup') {
      return frame(
        context,
        maxWidth: 560,
        back: () => go('entry'),
        children: [
          AccountForm(
            key: const Key('account-form'),
            verificationPanelKey: verificationPanelKey,
            repository: repo,
            onAction: action,
            busy: busy,
          ),
        ],
      );
    }
    if (page == 'forgot-password') {
      return frame(
        context,
        maxWidth: 560,
        title: 'Reset password',
        back: () => go('signin'),
        children: [ForgotPasswordForm(repository: repo)],
      );
    }
    if (page == 'noapp') {
      return frame(
        context,
        maxWidth: 560,
        title: 'Scan the code',
        showTitleIcon: false,
        back: () => go(repo.hasSignedInBefore ? 'signin' : 'entry'),
        children: [
          NoAppCheckInForm(
            repository: repo,
            cameraEnabled: widget.cameraEnabled,
            onCreateAccount: () => go('entry'),
          ),
        ],
      );
    }
    if (page == 'onboarded') {
      return frame(
        context,
        maxWidth: 560,
        children: [
          const SizedBox(height: 40),
          StepBar(steps: signupSteps, current: 4),
          const SizedBox(height: 32),
          const Icon(Icons.check_circle_outline, color: coral, size: 56),
          const SizedBox(height: 16),
          Text("You're in", style: Theme.of(context).textTheme.headlineLarge),
          const SizedBox(height: 12),
          const Text(
            'No expectations. No judgement. Come as you are. Your next session is waiting.',
            style: TextStyle(color: slate, height: 1.5),
          ),
          const SizedBox(height: 28),
          FilledButton(
            key: const Key('continue-to-play'),
            onPressed: () => go('home'),
            child: const Text('Continue'),
          ),
        ],
      );
    }
    if (repo.uid == null) {
      return frame(
        context,
        children: [
          const Text('Sign in to join a session.'),
          FilledButton(
            onPressed: () => go(repo.hasSignedInBefore ? 'signin' : 'entry'),
            child: const Text('Sign in'),
          ),
        ],
      );
    }
    if (!repo.ready) {
      return frame(
        context,
        children: [
          Text(
            'Finding your next rally…',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Panel(
                color: Colors.white.withValues(alpha: .6),
                child: const SizedBox(height: 70),
              ),
            ),
        ],
      );
    }
    if (page.startsWith('profile') && page != 'profile') {
      final step = int.tryParse(page.replaceFirst('profile', '')) ?? 1;
      // Only the first-time signup path is part of the 4-step journey --
      // an existing member updating their details later (editingProfile)
      // isn't "about to be in", they already are.
      final finish = editingProfile ? 'profile' : 'onboarded';
      return frame(
        context,
        maxWidth: 560,
        title: 'About you',
        showTitleIcon: false,
        back: () => go('profile'),
        children: [
          if (!editingProfile) ...[
            StepBar(steps: signupSteps, current: 3),
            const SizedBox(height: 24),
          ],
          ProfileStep(
            key: ValueKey(page),
            step: step,
            onHelp: () => go('help'),
            profile: repo.profile,
            contact: repo.contact,
            onSave: (changes) => action(() async {
              if (step == 6) {
                await repo.saveContact(changes);
              } else if (step == 7) {
                if (changes['photoSkip'] != true) {
                  await repo.savePhoto(changes['photoBytes'] as List<int>?);
                }
              } else {
                await repo.saveProfile(changes);
              }
              go(step == 7 ? finish : 'profile${step + 1}');
            }),
            onSkip: () => go(step == 7 ? finish : 'profile${step + 1}'),
          ),
        ],
      );
    }
    return switch (page) {
      'home' => home(context),
      'map' => map(context),
      'location' when repo.programs.isNotEmpty => catalogueLocation(context),
      'location' => shared.LocationPicker(
        currentLocation: area,
        back: () => go('home'),
        select: (value) {
          setState(() {
            area = value;
            areaChosen = true;
          });
          go('home');
        },
      ),
      'programs' => programs(context),
      'programDetail' => programDetail(context),
      'savedPrograms' => savedPrograms(context),
      'adminCatalogue' => frame(
        context,
        title: 'Admin · programs',
        back: () => go('role'),
        children: [
          if (repo.canAdmin)
            CatalogueAdminPanel(repository: repo)
          else
            const Text('Admin access required.'),
        ],
      ),
      'coachTools' => frame(
        context,
        title: 'Coach tools',
        back: () => go('profile'),
        children: [
          if (repo.canAdmin || repo.canCoach)
            StaffSessionsPanel(repository: repo)
          else
            const Text('Staff access required.'),
        ],
      ),
      'adminVenues' => frame(
        context,
        title: 'Admin · venues',
        back: () => go('role'),
        children: [
          if (repo.canAdmin)
            VenueManagementPanel(repository: repo)
          else
            const Text('Admin access required.'),
        ],
      ),
      'adminSessions' => frame(
        context,
        title: 'Admin · sessions',
        back: () => go('role'),
        children: [
          if (repo.canAdmin)
            SessionManagementPanel(repository: repo)
          else
            const Text('Admin access required.'),
        ],
      ),
      'session' => session(context),
      'people' => who(context),
      'checkin' => checkInState(context),
      'scan' => scan(context),
      'details' => frame(
        context,
        title: 'Before you play',
        back: () => go(detailsReturn),
        children: [
          DetailsForm(
            profile: repo.profile,
            onSave: (changes) => action(() async {
              await repo.saveProfile(changes);
              if (detailsReturn == 'profile') {
                go('profile');
                return;
              }
              if (event != null && repo.missingForms(event!).isNotEmpty) {
                go('agreements');
              } else {
                go('scan');
                nextAfterScan();
              }
            }),
          ),
        ],
      ),
      'agreements' => agreements(context),
      'waiting' || 'confirmed' => attendance(context),
      'feedbackReminder' => feedbackReminder(context),
      'feedback' => feedback(context),
      'profile' => profile(context),
      'account' => frame(
        context,
        title: 'Account',
        back: () => go('profile'),
        children: [SignInMethodsPanel(repository: repo)],
      ),
      'help' => help(context),
      'role' => roleScreen(context),
      'adminAccess' => frame(
        context,
        title: 'Admin · people & access',
        back: () => go('role'),
        children: [
          if (repo.canAdmin)
            AdminAccessPanel(repository: repo)
          else
            const Text('Admin access required.'),
        ],
      ),
      _ => home(context),
    };
  }

  String area = 'Bondi Junction 2022';
  String sport = 'All';
  Widget intro(BuildContext context, int step) {
    final colors = [coral, navy, pink],
        titles = [
          'Find your\nprogram',
          'Find your\npeople',
          'Play. Connect.\nFeel better.',
        ];
    final light = step < 3;
    return Scaffold(
      backgroundColor: colors[step - 1],
      body: SafeArea(
        child: introViewport(
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: brand(light: light)),
                    TextButton(
                      onPressed: () => go('entry'),
                      child: Text(
                        'Skip',
                        style: TextStyle(color: light ? Colors.white : navy),
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Image.asset(
                    [
                      'assets/candid_photo.jpg.webp',
                      'assets/group.jpg.webp',
                      'assets/lmfo.jpg.webp',
                    ][step - 1],
                    height: 230,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  titles[step - 1],
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: light ? Colors.white : navy,
                    fontSize: 38,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  [
                    'Free social tennis and pickleball in 50+ places across Australia.',
                    'No experience needed. Racquets and balls are provided. Just come along and have a hit.',
                    'A regular, low-pressure way to get moving and meet people near you.',
                  ][step - 1],
                  style: TextStyle(
                    color: light ? Colors.white : navy,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: List.generate(
                    3,
                    (i) => Container(
                      width: i == step - 1 ? 22 : 6,
                      height: 5,
                      margin: const EdgeInsets.only(right: 5),
                      decoration: BoxDecoration(
                        color: (light ? Colors.white : navy).withValues(
                          alpha: i == step - 1 ? 1 : .35,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: step == 2 ? coral : navy,
                  ),
                  onPressed: () =>
                      go(step == 3 ? 'entry' : 'welcome${step + 1}'),
                  child: Text(step == 3 ? 'Get started' : 'Continue'),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget introViewport(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: !widget.lanTesting
          ? child
          : LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(child: child),
                ),
              ),
            ),
    ),
  );

  String sessionAvailability(Record e) {
    if (e['status'] == 'cancelled') return 'Cancelled';
    if (dateOf(e['endsAt']).isBefore(repo.now())) return 'Session ended';
    if (e['programId'] != null) {
      final p = repo.programs
          .where((p) => p['id'] == e['programId'])
          .firstOrNull;
      if (p == null ||
          p['status'] != 'active' ||
          p['registrationStatus'] == 'closed') {
        return 'Bookings closed';
      }
      if (p['registrationStatus'] == 'full') return 'Full';
    }
    return availability(e);
  }

  bool canReserve(Record e) => ![
    'Full',
    'Cancelled',
    'Bookings closed',
    'Session ended',
    'Archived',
  ].contains(sessionAvailability(e));

  String stateFor(Record e) {
    if (e['status'] == 'cancelled') return 'Cancelled';
    final scan = repo.checkin(eid(e));
    if (scan != null) {
      return switch (scan['status']) {
        'confirmed' => 'Confirmed',
        'pending' => 'Checked in · waiting for coach',
        'rejected' => 'Check-in needs review',
        _ => 'Checked in',
      };
    }
    return repo.countedIn(eid(e)) ? 'Counted in' : sessionAvailability(e);
  }

  // Full and bookings-closed sessions stay tappable (to view details) but
  // never offer a quick "Count me in" and read as visibly lower-priority:
  // a muted card/title instead of the usual white/navy.
  bool _closedForDisplay(Record e) =>
      const {'Full', 'Bookings closed'}.contains(sessionAvailability(e));

  Widget eventCard(BuildContext context, Record e, {bool highlight = false}) {
    final closed = _closedForDisplay(e);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: InkWell(
        key: Key('event-${eid(e)}'),
        onTap: () => select(e, 'session'),
        borderRadius: BorderRadius.circular(18),
        child: Panel(
          color: closed
              ? const Color(0xffe9e5e1)
              : highlight
              ? navy
              : Colors.white,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusPill(stateFor(e), muted: closed),
              const SizedBox(height: 10),
              Text(
                e['name'] as String,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: closed ? slate : (highlight ? Colors.white : navy),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${eventDate(e)} · ${timeOf(e['startsAt'], e)}',
                style: TextStyle(
                  fontSize: 12,
                  color: highlight ? Colors.white : slate,
                ),
              ),
              Text(
                e['venue']['name'] as String,
                style: TextStyle(
                  fontSize: 12,
                  color: highlight ? Colors.white70 : slate,
                ),
              ),
              if (selectedMapPoint != null && venuePoint(e) != null)
                Text(
                  sessionDistanceLabel(e, selectedMapPoint!),
                  key: Key('distance-${eid(e)}'),
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    repo.checkin(eid(e))?['status'] == 'confirmed'
                        ? Icons.check_circle_outline
                        : Icons.arrow_forward,
                    size: 16,
                    color: highlight ? pink : coral,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    repo.checkin(eid(e))?['status'] == 'confirmed'
                        ? 'Attendance confirmed'
                        : 'View session',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: highlight ? Colors.white : coral,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Record> get nearbySessions => nearbySessionRecords(
    repo.events,
    now: repo.now(),
    centre: selectedMapPoint,
    sport: sport,
    programs: repo.programs,
    radiusKm: allAustralia ? double.infinity : nearbyRadiusKm,
  );
  List<Record> get undatedPrograms => undatedProgramRecords(
    repo.programs,
    repo.events,
    now: repo.now(),
    centre: selectedMapPoint,
    sport: sport,
    radiusKm: allAustralia ? double.infinity : nearbyRadiusKm,
  );
  bool nearSelectedArea(Record record) {
    if (allAustralia) return true;
    final point = selectedMapPoint, target = venuePoint(record);
    if (point != null && target != null) {
      return const Distance().as(LengthUnit.Kilometer, point, target) <= 50;
    }
    final v = record['venue'] as Map? ?? {};
    return '${v['suburb']} ${v['postcode']}' == area;
  }

  List<Record> get nearbyPrograms {
    final distance = const Distance();
    final rows = repo.programs
        .where((p) => matchesProgram(p, sport: sport) && nearSelectedArea(p))
        .toList();
    if (selectedMapPoint != null) {
      rows.sort(
        (a, b) =>
            (venuePoint(a) == null
                    ? double.infinity
                    : distance(mapCenter, venuePoint(a)!))
                .compareTo(
                  venuePoint(b) == null
                      ? double.infinity
                      : distance(mapCenter, venuePoint(b)!),
                ),
      );
    }
    return rows;
  }

  // Available dates sort before full/closed ones within each program, and
  // only the next few show by default -- a heavily booked-out program
  // (e.g. every upcoming Ultimo date full) otherwise floods the list
  // above programs that still have room.
  List<Widget> _sessionCards(List<Record> active) {
    final widgets = <Widget>[];
    for (final group in groupSessionsByProgram(active, canReserve)) {
      final expanded = _expandedProgramGroups.contains(_groupKey(group));
      final visible = expanded ? group : group.take(3).toList();
      for (final e in visible) {
        widgets.add(
          eventCard(
            context,
            e,
            highlight: repo.countedIn(eid(e)) || repo.checkin(eid(e)) != null,
          ),
        );
      }
      if (!expanded && group.length > 3) {
        final key = _groupKey(group);
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: TextButton(
              key: Key('more-dates-$key'),
              onPressed: () => setState(() => _expandedProgramGroups.add(key)),
              child: Text('${group.length - 3} more dates'),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  Widget home(BuildContext context) {
    _ensureBrowseLocationRequested();
    final active = nearbySessions;
    final countedElsewhere = repo.events.where(
      (e) =>
          repo.countedIn(eid(e)) &&
          !active.any((n) => eid(n) == eid(e)) &&
          dateOf(e['endsAt']).isAfter(repo.now()),
    );
    return frame(
      context,
      navigation: true,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hi ${repo.profile['firstName'] ?? 'there'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Text(
                    'Play near you',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            ),
            UserAvatar(repository: repo),
          ],
        ),
        const SizedBox(height: 20),
        Panel(
          padding: 12,
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined, color: coral, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(areaLabel, style: const TextStyle(fontSize: 12)),
              ),
              locationBarActions(),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          children: ['All', 'Tennis', 'Pickleball']
              .map(
                (value) => ChoiceChip(
                  label: Text(
                    value,
                    style: TextStyle(
                      color: sport == value ? Colors.white : navy,
                    ),
                  ),
                  selectedColor: navy,
                  selected: sport == value,
                  onSelected: (_) => setState(() => sport = value),
                  showCheckmark: false,
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 16),
        // Admin access lives only under Me -> Admin now, never on Play;
        // a coach's quick view stays here, unaffected.
        if (repo.role == 'coach') ...[
          OutlinedButton(
            onPressed: () => go('role'),
            child: const Text('Coach view'),
          ),
          const SizedBox(height: 16),
        ],
        if (active.isEmpty)
          const Panel(
            child: Text(
              'No upcoming sessions yet. Explore programs or check back soon.',
            ),
          ),
        ..._sessionCards(active),
        if (countedElsewhere.isNotEmpty) ...[
          const Text('Your other counted-in sessions'),
          for (final e in countedElsewhere)
            eventCard(context, e, highlight: true),
        ],
        if (nearbyPrograms.isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            'Find a regular program',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          for (final p in nearbyPrograms.take(5))
            ProgramCard(program: p, onTap: () => selectProgram(p)),
        ],
        TextButton(
          onPressed: () => go('programs'),
          child: const Text('Explore all programs'),
        ),
        if (repo.checkins.any(
          (c) =>
              c['status'] == 'confirmed' &&
              !repo.feedbackRecords.any((f) => f['eventId'] == c['eventId']) &&
              repo.events.any(
                (e) =>
                    eid(e) == c['eventId'] &&
                    dateOf(e['endsAt']).isBefore(repo.now()),
              ),
        ))
          OutlinedButton(
            onPressed: () {
              selectedId =
                  repo.checkins.firstWhere(
                        (c) => c['status'] == 'confirmed',
                      )['eventId']
                      as String;
              go('feedbackReminder');
            },
            child: const Text('How was your last session?'),
          ),
        const SizedBox(height: 12),
        const Text(
          'Turn up as you are. Equipment and friendly faces provided.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  DateTime zoned(dynamic value, Record e) {
    try {
      return tz.TZDateTime.from(
        dateOf(value),
        tz.getLocation(e['timezone'] as String? ?? 'Australia/Sydney'),
      );
    } catch (_) {
      return dateOf(value).toLocal();
    }
  }

  String timeOf(dynamic value, Record e) {
    final t = zoned(value, e);
    return '${t.hour % 12 == 0 ? 12 : t.hour % 12}:${t.minute.toString().padLeft(2, '0')}${t.hour >= 12 ? 'pm' : 'am'}';
  }

  String eventDate(Record e) {
    final d = zoned(e['startsAt'], e);
    return '${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]} ${d.day} ${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';
  }

  Widget session(BuildContext context) {
    final e = event;
    if (e == null) {
      return frame(
        context,
        title: 'Session',
        back: () => go('home'),
        children: [const Text('This session is unavailable.')],
      );
    }
    final scanned = repo.checkin(eid(e));
    return frame(
      context,
      title: 'Come as you are',
      back: () => go('home'),
      children: [
        CataloguePhoto(record: e, repository: repo),
        const SizedBox(height: 18),
        StatusPill(stateFor(e)),
        const SizedBox(height: 12),
        Text(
          e['name'] as String,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 16),
        shared.Info(
          Icons.calendar_today_outlined,
          '${eventDate(e)} · ${timeOf(e['startsAt'], e)}–${timeOf(e['endsAt'], e)}',
        ),
        shared.Info(Icons.location_on_outlined, e['venue']['name'] as String),
        shared.Info(Icons.sports_tennis, (e['sport'] as String? ?? 'Tennis')),
        if (e['catalogueManaged'] == true || e['capacity'] != null) ...[
          shared.Info(Icons.event_seat_outlined, sessionAvailability(e)),
          if ((e['coachNames'] as List? ?? []).isNotEmpty)
            shared.Info(
              Icons.person_outline,
              (e['coachNames'] as List).join(', '),
            ),
          if ((e['notes'] as String? ?? '').isNotEmpty)
            Panel(child: Text(e['notes'] as String)),
        ],
        const SizedBox(height: 18),
        const Panel(
          child: Text(
            'Just bring yourself\n\nRackets and balls provided. Wear comfy clothes and joggers. New player? Perfect.',
          ),
        ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () => action(() async {
            people = await repo.countedPeople(eid(e));
            go('people');
          }),
          child: const Text("Who's counted in"),
        ),
        if (repo.countedIn(eid(e)))
          TextButton(
            onPressed: () => action(() => repo.countMeIn(eid(e), cancel: true)),
            child: const Text('Cancel my intent'),
          ),
        const Text(
          '“Count me in” tells us you plan to come. Check in at the court when you arrive.',
          style: TextStyle(fontSize: 12),
        ),
      ],
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!repo.countedIn(eid(e)))
            FilledButton(
              key: const Key('count-me-in'),
              onPressed: canReserve(e)
                  ? () => action(() => repo.countMeIn(eid(e)))
                  : null,
              child: Text(
                canReserve(e) ? 'Count me in' : sessionAvailability(e),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text(
                'You’re counted in',
                style: TextStyle(fontWeight: FontWeight.w700, color: navy),
              ),
            ),
          if (repo.countedIn(eid(e)) || scanned != null) ...[
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('open-checkin'),
              style: FilledButton.styleFrom(backgroundColor: navy),
              onPressed: e['status'] == 'cancelled' && scanned == null
                  ? null
                  : () => go(scanned != null ? 'waiting' : 'checkin'),
              child: Text(
                scanned != null ? 'View attendance' : 'Check in at the court',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget who(BuildContext context) => frame(
    context,
    title: "Who's counted in",
    back: () => go('session'),
    children: [
      Text(
        event?['name'] as String? ?? 'Your session',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 18),
      const Panel(
        color: pink,
        child: Text(
          'Counted in means planning to come. Your coach confirms who actually turns up.',
        ),
      ),
      const SizedBox(height: 16),
      for (final person in people?['people'] as List? ?? [])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Panel(
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: navy,
                  foregroundColor: Colors.white,
                  child: Text(person['initials'] as String),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    person['label'] as String,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                StatusPill(person['isYou'] == true ? 'You' : 'Say hi'),
              ],
            ),
          ),
        ),
      Text(
        '${people?['count'] ?? repo.rsvps.where((r) => r['eventId'] == selectedId && r['cancelledAt'] == null).length} counted in. Only members who choose to share their first name are listed.',
        style: const TextStyle(fontSize: 12),
      ),
    ],
  );
  Widget checkInState(BuildContext context) {
    final e = event;
    if (e == null) {
      return frame(
        context,
        title: 'Check in',
        showTitleIcon: false,
        children: [const Text('Choose an upcoming session from Play.')],
        navigation: true,
      );
    }
    final scan = repo.checkin(eid(e));
    if (scan != null) return attendance(context);
    final opens = dateOf(e['startsAt']).subtract(const Duration(minutes: 10)),
        open = !repo.now().isBefore(opens),
        closed = repo.now().isAfter(dateOf(e['endsAt']));
    final venueLat = e['venue']['lat'] as num?,
        venueLng = e['venue']['lng'] as num?;
    // Treat exactly 0,0 ("null island") the same as missing -- it's never
    // a real venue location, only ever a placeholder for one that hasn't
    // been set yet.
    final venueKnown =
        venueLat != null &&
        venueLng != null &&
        !(venueLat == 0 && venueLng == 0);
    return frame(
      context,
      maxWidth: 560,
      dark: true,
      title: 'At the court',
      showTitleIcon: false,
      back: () => go('home'),
      children: [
        const SizedBox(height: 34),
        Text(
          e['name'] as String,
          style: const TextStyle(color: pink, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        Text(
          closed
              ? 'Check-in has\nclosed'
              : open
              ? 'Ready to play?\nScan to check in'
              : 'Check-in opens\nat ${timeOf(opens, e)}',
          style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 32),
        Center(
          child: Semantics(
            button: open && !closed,
            label: 'Scan QR code',
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                key: const Key('scan-circle'),
                customBorder: const CircleBorder(),
                onTap: open && !closed ? () => go('scan') : null,
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .08),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(
                    Icons.qr_code_scanner,
                    color: pink,
                    size: 78,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          venueKnown
              ? 'Check in from 10 minutes before the session starts. Stay within ${e['geofenceRadiusM'] ?? 150} m of ${e['venue']['name']}.'
              : 'Check in from 10 minutes before the session starts. We don’t have an exact location for ${e['venue']['name']} yet, so you can scan from anywhere -- your coach confirms everyone in person.',
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 18),
        if (venueKnown)
          OutlinedButton(
            key: const Key('preview-distance'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
            onPressed: () => action(() async {
              Record position;
              try {
                position = await repo.location();
              } catch (error) {
                if (mounted) {
                  setState(() {
                    previewDistance = null;
                    locationError = friendlyError(error);
                  });
                }
                return;
              }
              final distance = const Distance().as(
                LengthUnit.Meter,
                LatLng(
                  (position['lat'] as num).toDouble(),
                  (position['lng'] as num).toDouble(),
                ),
                LatLng(venueLat.toDouble(), venueLng.toDouble()),
              );
              if (mounted) {
                setState(() {
                  previewDistance = distance;
                  locationError = null;
                });
              }
            }),
            child: const Text('Check my distance'),
          ),
        if (previewDistance != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Panel(
              color: pink,
              child: Text(
                'You are ${previewDistance!.round()} m from the venue. ${previewDistance! > (e['geofenceRadiusM'] as num? ?? 150) ? "Move closer, or scan anyway -- your coach confirms everyone in person." : "Your coach will still confirm you in person."}',
              ),
            ),
          ),
        if (locationError != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Panel(
              color: pink,
              child: Text(
                "We couldn't find your location. $locationError You can still scan to check in -- your coach confirms everyone in person.",
              ),
            ),
          ),
        const Text(
          'Your location and scan time go to the coach. Attendance stays pending until the coach confirms.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
      bottom: FilledButton(
        key: const Key('start-scan'),
        onPressed: open && !closed ? () => go('scan') : null,
        child: Text(
          open && !closed
              ? 'Scan the coach’s QR'
              : 'Opens at ${timeOf(opens, e)}',
        ),
      ),
    );
  }

  Widget scan(BuildContext context) {
    if (widget.cameraEnabled) scanner ??= MobileScannerController();
    return frame(
      context,
      maxWidth: 560,
      dark: true,
      title: 'Scan the coach’s QR',
      showTitleIcon: false,
      back: () => go('checkin'),
      children: [
        const Text(
          'Only the current Rally4Ever session code will work.',
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: SizedBox(
            height: 270,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.cameraEnabled)
                  MobileScanner(
                    controller: scanner!,
                    onDetect: (capture) {
                      if (busy) return;
                      final value = capture.barcodes.firstOrNull?.rawValue;
                      if (value != null) {
                        unawaited(
                          action(() async {
                            await scanner!.stop();
                            try {
                              await acceptQr(value);
                            } finally {
                              if (mounted && page == 'scan') {
                                await scanner!.start();
                              }
                            }
                          }),
                        );
                      }
                    },
                    errorBuilder: (context, error) => const ColoredBox(
                      color: Color(0xff15295e),
                      child: Center(
                        child: Text(
                          'Allow camera access, or paste the QR link below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  )
                else
                  const ColoredBox(color: Color(0xff15295e)),
                Center(
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      border: Border.all(color: coral, width: 3),
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextField(
          key: const Key('qr-link'),
          controller: qrInput,
          decoration: const InputDecoration(
            labelText: 'Or paste the QR link',
            hintText: 'https://rally4ever.org/c/…',
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('use-qr'),
          onPressed: () => action(() => acceptQr(qrInput.text)),
          child: const Text('Use this session code'),
        ),
        const SizedBox(height: 14),
        const Text(
          'We check the event, time window, code, forms and distance on the server.',
          style: TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget agreements(BuildContext context) {
    final target = scanned == null
        ? <String, dynamic>{'requiredFormIds': <String>[]}
        : event ?? <String, dynamic>{'requiredFormIds': <String>[]};
    if (repo.unavailableForms(target).isNotEmpty) {
      return frame(
        context,
        title: 'Sign forms',
        back: () => go('profile'),
        children: [
          const Panel(
            color: pink,
            child: Text(
              'A required agreement is missing or unpublished. Signing and check-in are blocked. Please ask your coach for help.',
            ),
          ),
        ],
      );
    }
    final sources = repo.forms
        .where((f) => requiredAgreementIds.contains(f['id']))
        .toList();
    final groups = agreementGroups(sources);
    final missing = sources.where((f) => !repo.signed(f)).toList();
    return frame(
      context,
      title: 'Sign forms',
      back: () => go(detailsReturn == 'profile' ? 'profile' : 'details'),
      children: [
        Text(
          'Three required forms',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const Text(
          'Read Code of Conduct (including Waive and Release), Data Collection and Photo Release. All three are required.',
        ),
        if (missing.isEmpty)
          const Panel(
            child: Text(
              'All 3 forms are signed. We only ask again when a form changes.',
            ),
          ),
        const SizedBox(height: 20),
        for (final form in groups) ...[
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        form['title'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    StatusPill(
                      formSources(form).every(repo.signed)
                          ? 'Signed'
                          : 'Required',
                      dark: true,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Version ${form['version']}',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 12),
                LegalFormText(formText(form)),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (missing.isNotEmpty)
          CheckboxListTile(
            key: const Key('accept-forms'),
            contentPadding: EdgeInsets.zero,
            value: agreed,
            onChanged: busy ? null : (v) => setState(() => agreed = v ?? false),
            title: const Text('I have read and agree to all 3 forms.'),
          ),
      ],
      bottom: FilledButton(
        key: const Key('sign-and-checkin'),
        onPressed: busy || (missing.isNotEmpty && !agreed)
            ? null
            : () => action(() async {
                await repo.signForms(missing);
                if (scanned != null) {
                  go('scan');
                  nextAfterScan();
                } else {
                  go('profile');
                }
              }),
        child: Text(missing.isEmpty ? 'Done' : 'Sign all 3 forms'),
      ),
    );
  }

  Widget attendance(BuildContext context) {
    final e = event;
    final scan = e == null ? null : repo.checkin(eid(e));
    final status = scan?['status'] as String? ?? 'pending',
        confirmed = status == 'confirmed',
        rejected = status == 'rejected';
    return frame(
      context,
      title: 'Your attendance',
      back: () => go('home'),
      children: [
        const SizedBox(height: 40),
        Center(
          child: CircleAvatar(
            radius: 40,
            backgroundColor: confirmed
                ? const Color(0xffdff2e6)
                : rejected
                ? pink
                : const Color(0xffffefcf),
            child: Icon(
              confirmed
                  ? Icons.check
                  : rejected
                  ? Icons.info_outline
                  : Icons.schedule,
              color: navy,
              size: 36,
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          confirmed
              ? "You’re in,\n${repo.profile['firstName'] ?? 'friend'}"
              : rejected
              ? 'Let’s check\nwith your coach'
              : 'Checked in.\nWaiting for your coach',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 14),
        Text(
          confirmed
              ? 'Your attendance is confirmed. Enjoy the session.'
              : rejected
              ? 'The coach has marked this check-in for review. Speak to them at the court.'
              : 'Your scan is saved. Your coach will confirm you when you arrive.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StatusPill(
                confirmed
                    ? 'Confirmed'
                    : rejected
                    ? 'Needs review'
                    : 'Pending confirmation',
              ),
              const SizedBox(height: 12),
              Text(
                e?['name'] as String? ?? 'Your session',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(e?['venue']['name'] as String? ?? 'At the court'),
              if (scan != null && e != null) ...[
                const Divider(height: 28),
                Text(
                  'Scan time  ${timeOf(scan['scannedAt'], e)}',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  scan['distanceM'] == null
                      ? 'Manual check-in'
                      : 'Distance  ${(scan['distanceM'] as num).round()} m from venue',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Panel(
          color: pink,
          child: Text(
            'We keep the original scan. Only your assigned coach or an admin can correct attendance, with a recorded reason.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
      bottom: FilledButton(
        onPressed: () => go('home'),
        child: Text(confirmed ? 'Done' : 'Back to Play'),
      ),
    );
  }

  Widget feedbackReminder(BuildContext context) => frame(
    context,
    dark: true,
    back: () => go('home'),
    children: [
      const SizedBox(height: 70),
      const Icon(Icons.favorite_border, color: pink, size: 50),
      const SizedBox(height: 22),
      Text(
        'A little reflection.\nA better next rally.',
        style: Theme.of(context).textTheme.headlineLarge
            ?.copyWith(color: Colors.white),
      ),
      const SizedBox(height: 26),
      Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How was your session?',
              style: TextStyle(fontWeight: FontWeight.w700, color: navy),
            ),
            const SizedBox(height: 8),
            Text(event?['name'] as String? ?? 'Your last rally'),
            const Text(
              'It takes about 20 seconds. Your feedback helps us improve.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    ],
    bottom: FilledButton(
      onPressed: () => go('feedback'),
      child: const Text('Share feedback'),
    ),
  );
  Widget feedback(BuildContext context) {
    final e = event;
    final eligible =
        e != null &&
        repo.checkin(eid(e))?['status'] == 'confirmed' &&
        !dateOf(e['endsAt']).isAfter(repo.now());
    return frame(
      context,
      title: 'Your feedback',
      back: () => go('home'),
      children: [
        if (!eligible)
          const Panel(
            child: Text(
              'Feedback opens after the session for confirmed attendees.',
            ),
          )
        else
          FeedbackForm(
            eventName: e['name'] as String,
            onSend: (rating, tags, comment) => action(() async {
              await repo.feedback(eid(e), rating, tags, comment);
              go('home');
            }),
          ),
      ],
    );
  }

  Future<void> _editMePhoto(BuildContext context) async {
    final hasPhoto = repo.profile['photoUpdatedAt'] != null;
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from library'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: coral),
                title: const Text('Remove photo'),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'remove') {
      await action(() => repo.savePhoto(null));
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
    );
    if (picked == null) return;
    try {
      final bytes = processPhotoBytes(await picked.readAsBytes());
      await action(() => repo.savePhoto(bytes));
    } on PhotoTooLarge {
      setState(() => error = 'Choose a photo under 5 MB.');
    } on PhotoUnreadable {
      setState(() => error = 'That file could not be read as an image.');
    }
  }

  Widget profile(BuildContext context) => frame(
    context,
    title: 'Profile & preferences',
    showAppBar: false,
    navigation: true,
    children: [
      if (repo.canAdmin) ...[
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => go('role'),
          icon: const Icon(Icons.admin_panel_settings),
          label: const Text('Admin'),
        ),
      ],
      if (repo.canAdmin || repo.canCoach)
        OutlinedButton.icon(
          onPressed: () => go('coachTools'),
          icon: const Icon(Icons.qr_code),
          label: const Text('Coach tools'),
        ),
      ProfileSummary(
        repo: repo,
        sessionDate: eventDate,
        onEdit: () {
          editingProfile = true;
          go('profile1');
        },
        onPhoto: () => _editMePhoto(context),
        onSignForms: () {
          detailsReturn = 'profile';
          go('agreements');
        },
        onSession: (id) {
          selectedId = id;
          go('waiting');
        },
      ),
      const SizedBox(height: 18),
      const Text(
        'PREFERENCES',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: slate,
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: () {
          detailsReturn = 'profile';
          go('details');
        },
        child: const Text('Update safety details'),
      ),
      const SizedBox(height: 20),
      const Text(
        'Sign-in methods',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: navy,
        ),
      ),
      const SizedBox(height: 8),
      SignInMethodsPanel(repository: repo),
      TextButton(
        onPressed: () => action(repo.refreshAccess),
        child: const Text('Refresh roles & access'),
      ),
      TextButton(
        onPressed: () => action(() async {
          await repo.signOut();
          go('signin');
        }),
        child: const Text('Sign out'),
      ),
    ],
  );
  Widget help(BuildContext context) => frame(
    context,
    title: 'Help',
    navigation: true,
    children: [
      Text(
        'A little help\ngoes a long way.',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 22),
      for (final item in [
        (
          'What does “Count me in” do?',
          'It records your plan to come. A check-in records arrival, and your coach confirms attendance.',
        ),
        (
          'How do I check in at the court?',
          'Scan the current QR shown by your coach. Allow location, complete your details and sign any updated forms.',
        ),
        (
          'My coach added me. Where is my event?',
          'Sign in using the email you gave your coach. Your intent and attendance are linked to the same profile.',
        ),
        (
          'I’m new. Can I play?',
          'Yes. Bring yourself, comfortable shoes and water. Equipment and a warm welcome are provided.',
        ),
        (
          'Can I change my privacy choices?',
          'Open Me, then Edit details. The optional profile steps include your privacy preferences.',
        ),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Panel(
            padding: 4,
            child: ExpansionTile(
              title: Text(
                item.$1,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              childrenPadding: const EdgeInsets.all(16),
              children: [Text(item.$2)],
            ),
          ),
        ),
      const SizedBox(height: 18),
      const Panel(
        color: pink,
        child: Text(
          'At the court? Ask your coach for help with a code, your forms or a check-in.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      const SizedBox(height: 18),
      const Panel(
        color: coral,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Need to talk to someone now?',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            SizedBox(height: 10),
            shared.Support('Lifeline', '13 11 14'),
            SizedBox(height: 8),
            shared.Support('Beyond Blue', '1300 22 4636'),
          ],
        ),
      ),
    ],
  );
  Widget roleScreen(BuildContext context) => frame(
    context,
    title: repo.canAdmin ? 'Admin' : 'Coach tools',
    back: () => go('profile'),
    children: [
      OutlinedButton(
        onPressed: () => go('home'),
        child: const Text('Switch to participant view'),
      ),
      if (repo.canAdmin) ...[
        FilledButton(
          onPressed: () => go('adminCatalogue'),
          child: const Text('Programs'),
        ),
        FilledButton(
          onPressed: () => go('adminSessions'),
          child: const Text('Sessions'),
        ),
        FilledButton(
          onPressed: () => go('adminVenues'),
          child: const Text('Venues & photos'),
        ),
        FilledButton(
          onPressed: () => go('adminAccess'),
          child: const Text('Users & coach assignment'),
        ),
        OutlinedButton(
          onPressed: () => go('coachTools'),
          child: const Text('Coach tools'),
        ),
      ] else if (repo.canCoach)
        StaffSessionsPanel(repository: repo)
      else
        const Text('Staff access required.'),
    ],
  );
  void selectProgram(Record program) {
    selectedProgramId = program['id'] as String;
    go('programDetail');
  }

  Widget programs(BuildContext context) => frame(
    context,
    title: 'Explore programs',
    back: () => go('home'),
    children: [
      AnimatedBuilder(
        animation: repo,
        builder: (_, _) => ProgramBrowser(
          repository: repo,
          onSelect: selectProgram,
          onSavedDirectory: () => go('savedPrograms'),
        ),
      ),
    ],
  );
  Widget savedPrograms(BuildContext context) => frame(
    context,
    title: 'Saved program directory',
    back: () => go('programs'),
    children: [
      const Panel(
        color: pink,
        child: Text(
          'Saved directory from the existing app. Schedules may have changed. Use the live program calendar for confirmed dates and availability.',
        ),
      ),
      const SizedBox(height: 16),
      FutureBuilder<List<shared.RallyProgram>>(
        future: shared.RallyProgram.load(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Text('Loading programs…');
          return Column(
            children: snapshot.data!
                .map(
                  (p) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text('${p.venue} · ${p.suburb}'),
                          Text(
                            '${p.schedule} ${p.time}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          TextButton(
                            onPressed: () => go('home'),
                            child: const Text('Find an upcoming session'),
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
  Widget programDetail(BuildContext context) {
    final p = repo.programs
        .where((p) => p['id'] == selectedProgramId)
        .firstOrNull;
    if (p == null || p['status'] != 'active') {
      return frame(
        context,
        title: 'Program',
        back: () => go('programs'),
        children: [const Text('This program is unavailable.')],
      );
    }
    final v = p['venue'] as Map;
    final sessions = repo.events
        .where(
          (e) =>
              e['programId'] == p['id'] &&
              dateOf(e['endsAt']).isAfter(repo.now()),
        )
        .toList();
    return frame(
      context,
      title: 'Your regular rally',
      back: () => go('programs'),
      children: [
        CataloguePhoto(record: p, repository: repo),
        const SizedBox(height: 18),
        StatusPill(availability(p)),
        const SizedBox(height: 12),
        Text(
          p['name'] as String,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        shared.Info(
          Icons.place_outlined,
          '${v['name']}\n${v['address']} · ${v['suburb']} ${v['state']} ${v['postcode']}',
        ),
        shared.Info(
          Icons.calendar_month_outlined,
          '${p['scheduleText']}\n${p['timezone']}',
        ),
        if ((p['coachNames'] as List? ?? []).isNotEmpty)
          shared.Info(
            Icons.person_outline,
            (p['coachNames'] as List).join(', '),
          ),
        if ((p['notes'] as String? ?? '').isNotEmpty)
          Panel(child: Text(p['notes'] as String)),
        if (venuePoint(p) == null)
          const Text('Map location is awaiting verification.'),
        const SizedBox(height: 24),
        Text('Session calendar', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        if (p['status'] == 'archived')
          const Panel(
            child: Text(
              'This program is archived. Its history is kept; new bookings are closed.',
            ),
          )
        else if (sessions.isEmpty)
          const Panel(
            child: Text(
              'No dated sessions have been published yet. Check the regular schedule above and return for confirmed dates.',
            ),
          )
        else
          for (final e in sessions) eventCard(context, e),
      ],
    );
  }

  void _chooseArea(String label) {
    repo.recordLocationSearch(label);
    setState(() {
      area = label;
      areaChosen = true;
      allAustralia = false;
    });
    go('home');
  }

  Widget catalogueLocation(BuildContext context) {
    final query = locationSearch.trim().toLowerCase();
    // One row per distinct suburb/postcode, not one per program -- several
    // programs commonly share a venue's suburb.
    final seenLabels = <String>{};
    final suburbs = <Record>[];
    for (final p in repo.programs.where((p) => p['status'] == 'active')) {
      final v = p['venue'] as Map? ?? {};
      if (seenLabels.add('${v['suburb']} ${v['postcode']}')) suburbs.add(p);
    }
    final filtered = query.isEmpty
        ? suburbs
        : suburbs.where((p) {
            final v = p['venue'] as Map? ?? {};
            return '${v['suburb']}'.toLowerCase().contains(query) ||
                '${v['postcode']}'.toLowerCase().contains(query);
          }).toList();
    return frame(
      context,
      title: 'Choose location',
      back: () => go('home'),
      children: [
        TextField(
          key: const Key('location-search'),
          decoration: const InputDecoration(
            labelText: 'Search suburb or postcode',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => locationSearch = v),
        ),
        const SizedBox(height: 16),
        // Current location and recent history are search-box-empty-only
        // shortcuts -- they never replace the full suburb list below,
        // which always stays visible.
        if (query.isEmpty) ...[
          OutlinedButton.icon(
            key: const Key('use-my-location'),
            icon: const Icon(Icons.my_location),
            label: const Text('Use my current location'),
            onPressed: () {
              setState(() => areaChosen = false);
              _requestBrowseLocation();
              go('home');
            },
          ),
          if (repo.recentLocationSearches.isNotEmpty) ...[
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent',
                  style: TextStyle(fontWeight: FontWeight.w800, color: navy),
                ),
                TextButton(
                  key: const Key('clear-recent-locations'),
                  onPressed: () => repo.clearRecentLocationSearches(),
                  child: const Text('Clear'),
                ),
              ],
            ),
            for (final recent in repo.recentLocationSearches)
              ListTile(
                key: Key('recent-$recent'),
                leading: const Icon(Icons.history),
                title: Text(recent),
                onTap: () => _chooseArea(recent),
              ),
          ],
          const SizedBox(height: 20),
        ],
        const Text(
          'All locations',
          style: TextStyle(fontWeight: FontWeight.w800, color: navy),
        ),
        if (filtered.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('No locations match that search.'),
          ),
        for (final p in filtered)
          ListTile(
            title: Text('${p['venue']['suburb']} ${p['venue']['postcode']}'),
            subtitle: Text('${p['venue']['state']} · ${p['name']}'),
            onTap: () => _chooseArea(
              '${p['venue']['suburb']} ${p['venue']['postcode']}',
            ),
          ),
      ],
    );
  }

  LatLng? get selectedMapPoint {
    // The device's current position is the default search centre; a
    // manually chosen place (areaChosen) always overrides it.
    if (!areaChosen) {
      final here = repo.deviceLocation;
      if (repo.locationStatus == 'granted' && here != null) {
        return LatLng(
          (here['lat'] as num).toDouble(),
          (here['lng'] as num).toDouble(),
        );
      }
      // Only once GPS is denied/off/timed out: fall back to a known
      // program sharing the member's own home postcode, never a silent
      // default -- see areaLabel for the "(your home postcode)" label that
      // accompanies this.
      const fallbackStatuses = {
        'denied',
        'deniedForever',
        'servicesOff',
        'timeout',
      };
      if (fallbackStatuses.contains(repo.locationStatus)) {
        final postcode = '${repo.profile['postcode'] ?? ''}';
        if (postcode.isNotEmpty) {
          final match = repo.programs
              .where(
                (p) =>
                    p['status'] == 'active' &&
                    p['venue']['postcode'] == postcode,
              )
              .firstOrNull;
          if (match != null && venuePoint(match) != null) {
            return venuePoint(match)!;
          }
        }
      }
    }
    for (final p in repo.programs) {
      if ('${p['venue']['suburb']} ${p['venue']['postcode']}' == area &&
          venuePoint(p) != null) {
        return venuePoint(p)!;
      }
    }
    return shared.playAreaCoordinates[area];
  }

  LatLng get mapCenter => selectedMapPoint ?? const LatLng(-25, 133);

  // What the "Near ..." bar on Play/Map shows, and whether it's GPS, a
  // manual choice, or the home-postcode fallback (only ever surfaced once
  // location is denied/off/timed out -- never silently preferred over GPS).
  String get areaLabel {
    if (allAustralia) return 'All Australia';
    if (areaChosen) return 'Near $area';
    if (repo.locationStatus == 'granted') {
      return 'Near ${repo.nearbyLabel ?? 'you'}';
    }
    if (repo.locationStatus == 'requesting' || repo.locationStatus == 'idle') {
      return 'Finding your location…';
    }
    final postcode = '${repo.profile['postcode'] ?? ''}';
    if (postcode.isNotEmpty) return 'Near $postcode (your home postcode)';
    return 'Near you';
  }

  // first-open trigger for Play/Map; a no-op after the first call this
  // session (the lifecycle observer handles the "returned after a while"
  // refresh separately). Call at the top of home()/map()'s build.
  void _ensureBrowseLocationRequested() {
    if (_locationRequestedThisSession || areaChosen) return;
    _locationRequestedThisSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _requestBrowseLocation();
    });
  }

  // Shared by the Play and Map location bars: "Use my location" to return
  // to GPS from a manual choice or retry after a denial/timeout, "Open
  // settings" specifically once permission is permanently denied, and
  // "Change" to search a place or postcode manually -- see go('location').
  Widget locationBarActions() => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (allAustralia)
        TextButton(
          onPressed: () => setState(() => allAustralia = false),
          child: const Text('Nearby'),
        ),
      if (areaChosen ||
          repo.locationStatus == 'denied' ||
          repo.locationStatus == 'servicesOff' ||
          repo.locationStatus == 'timeout')
        TextButton(
          onPressed: () {
            setState(() => areaChosen = false);
            _requestBrowseLocation();
          },
          child: const Text(
            'Use my location',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        )
      else if (!areaChosen && repo.locationStatus == 'deniedForever')
        TextButton(
          onPressed: Geolocator.openAppSettings,
          child: const Text(
            'Open settings',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
      TextButton(
        onPressed: () => go('location'),
        child: const Text(
          'Change',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    ],
  );

  Widget map(BuildContext context) {
    _ensureBrowseLocationRequested();
    return Scaffold(
      // The map itself stays full-bleed on a tablet (unlike text content, a
      // map benefits from the extra width) -- only the nav chrome adapts.
      bottomNavigationBar: isWide(context) ? null : bottomNav(),
      appBar: AppBar(
        title: const Text('Play near you'),
        leading: BackButton(onPressed: () => go('home')),
      ),
      body: isWide(context)
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                navRail(),
                const VerticalDivider(width: 1),
                Expanded(child: _mapBody(context)),
              ],
            )
          : _mapBody(context),
    );
  }

  Widget _mapBody(BuildContext context) => Stack(
    children: [
      Positioned.fill(
        child: FlutterMap(
          key: ValueKey(
            '$area|$allAustralia|${nearbySessions.length}|${undatedPrograms.length}|${selectedMapPoint?.latitude}|${selectedMapPoint?.longitude}',
          ),
          mapController: mapController,
          options: MapOptions(
            minZoom: 3,
            onMapReady: () => WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || page != 'map') return;
              final points = [
                mapCenter,
                ...nearbySessions.map((e) => venuePoint(e)!),
                ...undatedPrograms.map((p) => venuePoint(p)!),
              ];
              if (points.length > 1) {
                mapController.fitCamera(
                  CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints(points),
                    padding: EdgeInsets.fromLTRB(
                      40,
                      min(180, MediaQuery.sizeOf(context).height * .18),
                      40,
                      min(300, MediaQuery.sizeOf(context).height * .25),
                    ),
                    maxZoom: 14,
                  ),
                );
              }
            }),
            initialCenter: mapCenter,
            initialCameraFit: nearbySessions.isEmpty && undatedPrograms.isEmpty
                ? null
                : CameraFit.bounds(
                    bounds: LatLngBounds.fromPoints([
                      mapCenter,
                      ...nearbySessions.map((e) => venuePoint(e)!),
                      ...undatedPrograms.map((p) => venuePoint(p)!),
                    ]),
                    padding: EdgeInsets.fromLTRB(
                      40,
                      min(180, MediaQuery.sizeOf(context).height * .18),
                      40,
                      min(300, MediaQuery.sizeOf(context).height * .25),
                    ),
                    maxZoom: 14,
                  ),
            initialZoom: selectedMapPoint == null ? 4 : 12,
          ),
          children: [
            if (widget.mapTilesEnabled)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'org.rally4ever.app',
              ),
            MarkerLayer(
              markers: [
                for (final e in nearbySessions)
                  Marker(
                    point: venuePoint(e)!,
                    width: 50,
                    height: 50,
                    child: IconButton(
                      key: Key('session-marker-${eid(e)}'),
                      onPressed: () => select(e, 'session'),
                      tooltip: e['name'] as String,
                      icon: Icon(
                        Icons.location_on,
                        color: _closedForDisplay(e) ? slate : coral,
                        size: 38,
                      ),
                    ),
                  ),
                for (final p in undatedPrograms)
                  Marker(
                    point: venuePoint(p)!,
                    width: 50,
                    height: 50,
                    child: IconButton(
                      key: Key('program-marker-${p['id']}'),
                      tooltip: '${p['name']} — dates coming soon',
                      onPressed: () => selectProgram(p),
                      icon: const Icon(
                        Icons.location_on_outlined,
                        color: navy,
                        size: 38,
                      ),
                    ),
                  ),
                if (repo.locationStatus == 'granted' &&
                    repo.deviceLocation != null)
                  Marker(
                    point: LatLng(
                      (repo.deviceLocation!['lat'] as num).toDouble(),
                      (repo.deviceLocation!['lng'] as num).toDouble(),
                    ),
                    width: 24,
                    height: 24,
                    child: Container(
                      key: const Key('user-location-dot'),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                    ),
                  ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
              ],
            ),
          ],
        ),
      ),
      Positioned(
        left: 20,
        right: 20,
        top: 20,
        child: Panel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.search, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(areaLabel)),
                  IconButton(
                    key: const Key('centre-on-me'),
                    tooltip: 'Centre on me',
                    icon: const Icon(Icons.my_location),
                    onPressed: () async {
                      await repo.requestBrowseLocation();
                      if (mounted && repo.deviceLocation != null) {
                        setState(() {
                          areaChosen = false;
                          allAustralia = false;
                        });
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && page == 'map') {
                            mapController.move(mapCenter, 14);
                          }
                        });
                      }
                    },
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: locationBarActions(),
              ),
            ],
          ),
        ),
      ),
      Positioned(
        left: 20,
        right: 20,
        bottom: 24,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .38,
          ),
          child: SingleChildScrollView(
            child: Panel(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${nearbySessions.length} sessions ${allAustralia ? 'across Australia' : 'nearby'}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    allAustralia
                        ? 'Showing published locations across Australia.'
                        : 'Within 50 km of the search centre.',
                  ),
                  if (undatedPrograms.isNotEmpty)
                    Text(
                      '${undatedPrograms.length} ${undatedPrograms.length == 1 ? 'program awaiting dates' : 'programs awaiting dates'}. Outlined markers show programs, not bookable sessions.',
                    ),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: () => go('home'),
                        child: const Text('List view'),
                      ),
                      TextButton(
                        key: const Key('map-browse-scope'),
                        onPressed: () =>
                            setState(() => allAustralia = !allAustralia),
                        child: Text(
                          allAustralia ? 'Show nearby' : 'All Australia',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
