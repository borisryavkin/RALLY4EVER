import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;
import 'package:url_launcher/url_launcher.dart';

import 'repository.dart';
import 'about_icons.dart';
import 'legal_text.dart';
import 'form_groups.dart';
import 'theme.dart';

/// Shown once on a device that's never signed in: the logo, a calm
/// reassurance line, and three big, clearly-ordered actions -- Google
/// first (fastest, no typing), email second, and a quieter way to just
/// check in without creating anything at all. Never a dead end: the one
/// link down the bottom always reaches the returning-user Sign in screen.
class EntryScreen extends StatelessWidget {
  const EntryScreen({
    super.key,
    required this.repository,
    required this.onAction,
    required this.busy,
    required this.onUseEmail,
    required this.onCheckInWithoutAccount,
    required this.onSignIn,
  });
  final ParticipantRepository repository;
  final Future<void> Function(Future<void> Function()) onAction;
  final bool busy;
  final VoidCallback onUseEmail, onCheckInWithoutAccount, onSignIn;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 56),
      Text(
        'Join\nRALLY4EVER',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 12),
      const Text(
        'No expectations. No judgement. Come as you are.',
        style: TextStyle(color: slate, height: 1.5),
      ),
      const SizedBox(height: 40),
      FilledButton.icon(
        key: const Key('google-sign-in'),
        onPressed: busy || !repository.enabled
            ? null
            : () => onAction(repository.signInGoogle),
        icon: const Icon(Icons.account_circle_outlined),
        label: const Text('Continue with Google'),
      ),
      const SizedBox(height: 14),
      OutlinedButton.icon(
        key: const Key('use-my-email'),
        onPressed: busy ? null : onUseEmail,
        icon: const Icon(Icons.mail_outline),
        label: const Text('Use my email'),
      ),
      const SizedBox(height: 14),
      Center(
        child: TextButton(
          key: const Key('check-in-without-account'),
          onPressed: onCheckInWithoutAccount,
          child: const Text('Check in without an account'),
        ),
      ),
      const SizedBox(height: 28),
      if (!repository.enabled)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Panel(
            color: pink,
            child: Text(
              kDebugMode
                  ? 'Start the local emulators and run with USE_FIREBASE_EMULATORS=true to sign in.'
                  : 'Sign-in is unavailable. Please close and reopen the app, or contact RALLY4EVER.',
            ),
          ),
        ),
      Center(
        child: TextButton(
          key: const Key('go-to-signin'),
          onPressed: onSignIn,
          child: const Text('Already have an account? Sign in'),
        ),
      ),
    ],
  );
}

/// Shown on a device that's signed in before -- straight to the fields,
/// no re-pitching the community. Google and email sit together here (the
/// entry screen keeps them as separate big buttons instead), so this is
/// also where the "same account either way" reassurance lives.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.repository,
    required this.onAction,
    required this.busy,
    required this.onForgotPassword,
    required this.onCreateAccount,
    required this.onCheckInWithoutAccount,
  });
  final ParticipantRepository repository;
  final Future<void> Function(Future<void> Function()) onAction;
  final bool busy;
  final VoidCallback onForgotPassword, onCreateAccount, onCheckInWithoutAccount;
  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final email = TextEditingController(), password = TextEditingController();
  bool passwordVisible = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 56),
      Text('Welcome\nback', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 12),
      const Text(
        'One email, one profile. Find your people and your next session.',
        style: TextStyle(color: slate),
      ),
      const SizedBox(height: 28),
      OutlinedButton.icon(
        key: const Key('google-sign-in'),
        onPressed: widget.busy || !widget.repository.enabled
            ? null
            : () => widget.onAction(widget.repository.signInGoogle),
        icon: const Icon(Icons.account_circle_outlined),
        label: const Text('Continue with Google'),
      ),
      const SizedBox(height: 8),
      const Text(
        'Same email, same account. Use Google or email, whichever you like.',
        style: TextStyle(fontSize: 12, color: slate),
      ),
      const SizedBox(height: 20),
      _field('Email', email, 'email', keyboard: TextInputType.emailAddress),
      const SizedBox(height: 14),
      TextField(
        key: const Key('password'),
        controller: password,
        obscureText: !passwordVisible,
        autofillHints: const [AutofillHints.password],
        decoration: InputDecoration(
          labelText: 'Password',
          hintText: 'Your RALLY4EVER password',
          suffixIcon: IconButton(
            key: const Key('show-login-password'),
            tooltip: passwordVisible ? 'Hide password' : 'Show password',
            onPressed: () => setState(() => passwordVisible = !passwordVisible),
            icon: Icon(
              passwordVisible ? Icons.visibility_off : Icons.visibility,
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          key: const Key('forgot-password'),
          onPressed: widget.onForgotPassword,
          child: const Text('Forgot password?'),
        ),
      ),
      const SizedBox(height: 10),
      FilledButton(
        key: const Key('authenticate'),
        onPressed: widget.busy || !widget.repository.enabled
            ? null
            : () => widget.onAction(
                () => widget.repository.signIn(email.text, password.text),
              ),
        child: const Text('Sign in'),
      ),
      const SizedBox(height: 6),
      Center(
        child: TextButton(
          key: const Key('toggle-signup'),
          onPressed: widget.onCreateAccount,
          child: const Text('New here? Create an account'),
        ),
      ),
      Center(
        child: TextButton(
          key: const Key('check-in-without-account'),
          onPressed: widget.onCheckInWithoutAccount,
          child: const Text('Check in without an account'),
        ),
      ),
      if (!widget.repository.enabled)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Panel(
            color: pink,
            child: Text(
              kDebugMode
                  ? 'Start the local emulators and run with USE_FIREBASE_EMULATORS=true to sign in.'
                  : 'Sign-in is unavailable. Please close and reopen the app, or contact RALLY4EVER.',
            ),
          ),
        ),
      const SizedBox(height: 16),
    ],
  );
}

const signupSteps = [
  (Icons.mail_outline, 'Your email'),
  (Icons.inbox_outlined, 'Check your inbox'),
  (Icons.person_outline, 'About you'),
  (Icons.check_circle_outline, "You're in"),
];

/// The email path of signing up, always a brand-new account (returning
/// users sign in on [SignInScreen] instead) -- step 1 ("Your email") and,
/// once submitted, step 2 ("Check your inbox") replace the form entirely
/// with [_verificationPanel] rather than sitting above it, since there's
/// nothing left to do here until the link is opened.
class AccountForm extends StatefulWidget {
  const AccountForm({
    super.key,
    required this.repository,
    required this.onAction,
    required this.busy,
    required this.verificationPanelKey,
  });
  final ParticipantRepository repository;
  final Future<void> Function(Future<void> Function()) onAction;
  final bool busy;
  final GlobalKey verificationPanelKey;
  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final email = TextEditingController(), password = TextEditingController();
  bool passwordVisible = false;
  String? verifyHint;
  int resendCooldown = 0;
  Timer? _resendTicker;
  @override
  void dispose() {
    _resendTicker?.cancel();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  bool get awaitingVerification =>
      widget.repository.email != null && !widget.repository.verified;

  Future<void> _openEmailApp() async {
    final uri = Uri(scheme: 'mailto');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _resend() async {
    setState(() => resendCooldown = 30);
    _resendTicker?.cancel();
    _resendTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => resendCooldown -= 1);
      if (resendCooldown <= 0) timer.cancel();
    });
    await widget.onAction(widget.repository.resendVerificationEmail);
  }

  Future<void> _checkVerified() async {
    setState(() => verifyHint = null);
    await widget.onAction(widget.repository.refreshVerification);
    if (mounted && awaitingVerification) {
      setState(
        () => verifyHint =
            "We can't see it yet. Check your inbox and spam folder.",
      );
    }
  }

  Widget _verificationPanel() => Container(
    key: widget.verificationPanelKey,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: navy,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.mail_outline, color: Colors.white, size: 36),
        const SizedBox(height: 12),
        const Text(
          'Check your inbox',
          style: TextStyle(
            color: Colors.white,
            fontFamily: 'Jellee',
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'We sent a link to ${widget.repository.email}. Open it, then come back here.',
          style: const TextStyle(color: Colors.white),
        ),
        if (verifyHint != null) ...[
          const SizedBox(height: 14),
          Container(
            key: const Key('verify-hint'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              verifyHint!,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
        const SizedBox(height: 18),
        OutlinedButton(
          key: const Key('open-email-app'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white54),
          ),
          onPressed: _openEmailApp,
          child: const Text('Open email app'),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('resend-verification'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white54),
          ),
          onPressed: widget.busy || resendCooldown > 0 ? null : _resend,
          child: Text(
            resendCooldown > 0
                ? 'Resend in ${resendCooldown}s'
                : 'Resend email',
          ),
        ),
        const SizedBox(height: 14),
        FilledButton(
          key: const Key('verified-email'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: navy,
          ),
          onPressed: widget.busy ? null : _checkVerified,
          child: const Text("I've verified my email"),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 32),
      StepBar(steps: signupSteps, current: awaitingVerification ? 2 : 1),
      const SizedBox(height: 28),
      Text(
        awaitingVerification ? 'Almost there' : 'Your\nemail',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 12),
      Text(
        awaitingVerification
            ? 'Open the link we sent, then come back here.'
            : 'One email, one profile. Find your people and your next session.',
        style: const TextStyle(color: slate),
      ),
      const SizedBox(height: 24),
      // Once an account exists and is pending verification, that's the
      // only thing on this screen -- re-showing the form right below it
      // is confusing and has nothing left to do until the link is opened.
      if (awaitingVerification)
        _verificationPanel()
      else ...[
        _field('Email', email, 'email', keyboard: TextInputType.emailAddress),
        const SizedBox(height: 14),
        TextField(
          key: const Key('password'),
          controller: password,
          obscureText: !passwordVisible,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: 'At least 8 characters',
            suffixIcon: IconButton(
              key: const Key('show-login-password'),
              tooltip: passwordVisible ? 'Hide password' : 'Show password',
              onPressed: () =>
                  setState(() => passwordVisible = !passwordVisible),
              icon: Icon(
                passwordVisible ? Icons.visibility_off : Icons.visibility,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('authenticate'),
          onPressed: widget.busy || !widget.repository.enabled
              ? null
              : () => widget.onAction(
                  () => widget.repository.signUp(email.text, password.text),
                ),
          child: const Text('Create account'),
        ),
        if (!widget.repository.enabled)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Panel(
              color: pink,
              child: Text(
                kDebugMode
                    ? 'Start the local emulators and run with USE_FIREBASE_EMULATORS=true to sign in.'
                    : 'Sign-in is unavailable. Please close and reopen the app, or contact RALLY4EVER.',
              ),
            ),
          ),
      ],
      const SizedBox(height: 16),
    ],
  );
}

Widget _field(
  String label,
  TextEditingController controller,
  String name, {
  TextInputType? keyboard,
  ValueChanged<String>? onChanged,
  String? helperText,
  String? hint,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: navy,
        ),
      ),
      const SizedBox(height: 6),
      TextField(
        key: Key(name),
        controller: controller,
        keyboardType: keyboard,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint ?? label,
          helperText: helperText,
          helperMaxLines: 3,
        ),
      ),
    ],
  ),
);

class ForgotPasswordForm extends StatefulWidget {
  const ForgotPasswordForm({super.key, required this.repository});
  final ParticipantRepository repository;
  @override
  State<ForgotPasswordForm> createState() => _ForgotPasswordFormState();
}

class _ForgotPasswordFormState extends State<ForgotPasswordForm> {
  final email = TextEditingController();
  bool busy = false, sent = false;
  String? error;
  int cooldown = 0;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    email.dispose();
    super.dispose();
  }

  void _startCooldown() {
    setState(() => cooldown = 60);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => cooldown -= 1);
      if (cooldown <= 0) timer.cancel();
    });
  }

  Future<void> submit() async {
    if (email.text.trim().isEmpty) {
      setState(() => error = 'Enter your email address');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.repository.sendPasswordReset(email.text.trim());
      if (!mounted) return;
      setState(() => sent = true);
      _startCooldown();
    } on PasswordResetRateLimited {
      if (mounted) {
        setState(
          () => error = 'Too many attempts. Wait a few minutes and try again.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Reset your\npassword',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 12),
      const Text(
        "Enter the email you use to sign in and we'll send you a link to "
        'reset your password.',
      ),
      const SizedBox(height: 20),
      if (sent)
        Panel(
          key: const Key('reset-sent'),
          child: Text(
            "If an account exists for that email, we've sent a link to "
            'reset the password. Check your inbox and spam folder.',
          ),
        )
      else ...[
        _field(
          'Email',
          email,
          'reset-email',
          keyboard: TextInputType.emailAddress,
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          Text(error!, style: const TextStyle(color: coral)),
        ],
      ],
      const SizedBox(height: 16),
      FilledButton(
        key: const Key('send-reset'),
        onPressed: busy || cooldown > 0 ? null : submit,
        child: Text(
          cooldown > 0
              ? 'Resend in ${cooldown}s'
              : sent
              ? 'Resend link'
              : 'Send reset link',
        ),
      ),
      const SizedBox(height: 16),
      const Text(
        'First used Google? Sign in with Google, then open Me → Sign-in methods to add a password.',
        style: TextStyle(fontSize: 12, color: slate),
      ),
    ],
  );
}

// Option keys stored in Firestore; labels are display-only and can change
// freely without touching stored data. See firestore.rules' validAbout.
const occupationOptions = {
  'working': 'Working',
  'studying': 'Studying',
  'looking_for_work': 'Looking for work',
  'retired': 'Retired',
  'prefer_not_to_say': 'Prefer not to say',
};
const occupationExclusive = {'prefer_not_to_say'};
const heardAboutOptions = {
  'friend': 'Friend',
  'uni_campus': 'Uni / campus',
  'social_media': 'Social media',
  'local_club': 'Local club',
  'other': 'Other',
};
const culturalBackgroundOptions = {
  'aboriginal_torres_strait_islander':
      'Aboriginal and/or Torres Strait Islander',
  'born_outside_australia': 'Born outside Australia',
  'neither': 'Neither',
  'prefer_not_to_say': 'Prefer not to say',
};
const culturalBackgroundExclusive = {'neither', 'prefer_not_to_say'};

/// Converts a legacy single-value `about` map (currentActivity/referral as a
/// display-label string, culturalBackground as a single string) into the
/// current array-of-option-key shape. A map that's already current (or
/// empty) passes through unchanged. Pure and safe to call on every read, so
/// an old profile is migrated the moment it's next loaded for editing.
Record migrateAbout(Record raw) {
  final about = Map<String, dynamic>.from(raw);
  String? keyFor(Map<String, String> options, Object? label) => options.entries
      .firstWhere((e) => e.value == label, orElse: () => const MapEntry('', ''))
      .key
      .let((k) => k.isEmpty ? null : k);
  if (about['currentActivity'] is String) {
    final key = keyFor(occupationOptions, about.remove('currentActivity'));
    about['occupation'] = [?key];
  }
  if (about['referral'] is String) {
    final key = keyFor(heardAboutOptions, about.remove('referral'));
    about['heardAbout'] = [?key];
  }
  if (about.containsKey('referralOther') &&
      !about.containsKey('heardAboutOther')) {
    about['heardAboutOther'] = about.remove('referralOther');
  }
  if (about['culturalBackground'] is String) {
    final key = keyFor(
      culturalBackgroundOptions,
      about.remove('culturalBackground'),
    );
    about['culturalBackground'] = [?key];
  }
  about['occupation'] = List<String>.from(about['occupation'] as List? ?? []);
  about['heardAbout'] = List<String>.from(about['heardAbout'] as List? ?? []);
  about['heardAboutOther'] = (about['heardAboutOther'] as String?) ?? '';
  about['culturalBackground'] = List<String>.from(
    about['culturalBackground'] as List? ?? [],
  );
  return about;
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class ProfileStep extends StatefulWidget {
  const ProfileStep({
    super.key,
    required this.step,
    required this.profile,
    required this.contact,
    required this.onSave,
    required this.onSkip,
    this.onHelp,
  });
  final int step;
  final Record profile;
  final Record contact;
  final Future<void> Function(Record) onSave;
  final VoidCallback onSkip;
  final VoidCallback? onHelp;
  @override
  State<ProfileStep> createState() => _ProfileStepState();
}

class _ProfileStepState extends State<ProfileStep> {
  late final first = TextEditingController(
    text: widget.profile['firstName'] as String? ?? '',
  );
  late final postcode = TextEditingController(
    text: widget.profile['postcode'] as String? ?? '',
  );
  late final Record about = migrateAbout(
    Map<String, dynamic>.from(widget.profile['about'] as Map? ?? {}),
  );
  late final Record prefs = {
    'useInReports': false,
    'wellbeingCheckIns': false,
    'showInWhosGoing': false,
    'marketingEmails': false,
    ...Map<String, dynamic>.from(widget.profile['preferences'] as Map? ?? {}),
  };
  late final mobile = TextEditingController(
    text: (widget.contact['mobile'] as String?)?.isNotEmpty == true
        ? widget.contact['mobile'] as String
        : '+61 ',
  );
  late final emergencyName = TextEditingController(
    text:
        (widget.contact['emergencyContact'] as Map?)?['name'] as String? ?? '',
  );
  late final emergencyMobile = TextEditingController(
    text:
        (widget.contact['emergencyContact'] as Map?)?['mobile'] as String? ??
        '',
  );
  late final heardAboutOther = TextEditingController(
    text: about['heardAboutOther'] as String? ?? '',
  );
  List<int>? pickedPhotoBytes;
  bool removePhoto = false;
  String? photoError;
  String? error;
  @override
  void dispose() {
    first.dispose();
    postcode.dispose();
    mobile.dispose();
    emergencyName.dispose();
    emergencyMobile.dispose();
    heardAboutOther.dispose();
    super.dispose();
  }

  Widget choices(
    String label,
    String name,
    List<String> options, {
    String? why,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: navy,
                ),
              ),
            ),
            if (why != null) WhyWeAsk(title: label, body: why),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 4,
          children: options
              .map(
                (v) => ChoiceChip(
                  label: Text(v),
                  selected: about[name] == v,
                  onSelected: (_) => setState(() => about[name] = v),
                  selectedColor: navy,
                  labelStyle: TextStyle(
                    color: about[name] == v ? Colors.white : navy,
                    fontSize: 12,
                  ),
                  showCheckmark: false,
                ),
              )
              .toList(),
        ),
      ],
    ),
  );

  /// Multiple chips can be selected at once; any key in [exclusive] clears
  /// every other selection the moment it's chosen (and vice versa).
  Widget multiChoices(
    String label,
    String name,
    Map<String, String> options, {
    Set<String> exclusive = const {},
    String? why,
  }) {
    final selected = Set<String>.from(about[name] as List? ?? const []);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: navy,
                  ),
                ),
              ),
              if (why != null) WhyWeAsk(title: label, body: why),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 4,
            children: options.entries
                .map(
                  (entry) => ChoiceChip(
                    label: Text(
                      entry.value,
                      style: TextStyle(
                        color: selected.contains(entry.key)
                            ? Colors.white
                            : navy,
                        fontSize: 12,
                      ),
                    ),
                    selected: selected.contains(entry.key),
                    selectedColor: navy,
                    showCheckmark: false,
                    onSelected: (_) => setState(() {
                      final next = Set<String>.from(selected);
                      if (next.contains(entry.key)) {
                        next.remove(entry.key);
                      } else if (exclusive.contains(entry.key)) {
                        next
                          ..clear()
                          ..add(entry.key);
                      } else {
                        next
                          ..removeAll(exclusive)
                          ..add(entry.key);
                      }
                      about[name] = next.toList();
                      if (name == 'heardAbout' && !next.contains('other')) {
                        heardAboutOther.clear();
                        about['heardAboutOther'] = '';
                      }
                    }),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Future<void> pickPhoto(ImageSource source) async {
    setState(() => photoError = null);
    final picked = await ImagePicker().pickImage(source: source);
    if (picked == null) return;
    try {
      final processed = processPhotoBytes(await picked.readAsBytes());
      setState(() {
        pickedPhotoBytes = processed;
        removePhoto = false;
      });
    } on PhotoTooLarge {
      setState(() => photoError = 'Choose a photo under 5 MB.');
    } on PhotoUnreadable {
      setState(() => photoError = 'That file could not be read as an image.');
    }
  }

  Future<void> save() async {
    if (widget.step == 1 &&
        (first.text.trim().isEmpty ||
            !RegExp(r'^\d{4}$').hasMatch(postcode.text.trim()))) {
      setState(() => error = 'Enter your name and a four-digit postcode.');
      return;
    }
    if (widget.step == 3 &&
        heardAboutOther.text.trim().isEmpty &&
        (about['heardAbout'] as List).contains('other')) {
      setState(() => error = 'Tell us a little more, or remove "Other".');
      return;
    }
    // Trimmed only here, not on every keystroke, so typing a multi-word
    // answer isn't fought by trimming trailing spaces mid-sentence.
    about['heardAboutOther'] = heardAboutOther.text.trim();
    final Record? payload = switch (widget.step) {
      1 => {
        'firstName': first.text.trim(),
        'postcode': postcode.text.trim(),
        'about': about,
      },
      2 => {'about': about},
      3 => {'about': about},
      4 => {'about': about},
      5 => {'preferences': prefs},
      6 => {
        'mobile': mobile.text.trim().replaceAll(' ', '') == '+61'
            ? ''
            : normalizeAustralianMobile(mobile.text),
        'emergencyContact': {
          'name': emergencyName.text.trim(),
          'mobile': emergencyMobile.text.trim().isEmpty
              ? ''
              : normalizeAustralianMobile(emergencyMobile.text),
        },
      },
      7 => {
        'photoBytes': removePhoto ? null : pickedPhotoBytes,
        'photoSkip': pickedPhotoBytes == null && !removePhoto,
      },
      _ => _unknownProfileStep(),
    };
    if (payload != null) await widget.onSave(payload);
  }

  Record? _unknownProfileStep() {
    assert(() {
      throw StateError('Unknown step');
    }());
    return null; // Release: never write an unknown step as an about payload.
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            'Step ${widget.step} of 7',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: coral,
            ),
          ),
          const Spacer(),
          if (widget.step == 6)
            const Text('Optional', style: TextStyle(fontSize: 13, color: slate))
          else if (widget.step > 1)
            TextButton(
              onPressed: widget.onSkip,
              child: const Text('Skip this step'),
            ),
        ],
      ),
      LinearProgressIndicator(
        value: widget.step / 7,
        minHeight: 4,
        color: coral,
        backgroundColor: const Color(0xffe1dcda),
      ),
      const SizedBox(height: 24),
      Text(
        [
          'Tell us a little about\nyou',
          'Help us include\neveryone',
          'Help our research,\nwhen you’re ready',
          'How have you been\nfeeling lately?',
          'Your info, your call',
          'Someone we can call, just in case',
          'Add a photo\n(optional)',
        ][widget.step - 1],
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 10),
      if (widget.step != 6)
        Text(
          widget.step == 1
              ? 'Just the basics to get you started.'
              : widget.step == 4
              ? 'Optional. Answer only what feels okay. You can skip this step.'
              : 'Optional. Share what feels right for you.',
        ),
      const SizedBox(height: 24),
      if (widget.step == 4) ...[
        Semantics(
          button: widget.onHelp != null,
          child: InkWell(
            onTap: widget.onHelp,
            borderRadius: BorderRadius.circular(18),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: 48),
              child: const Panel(
                child: AboutNoteRow(
                  AboutIconKind.support,
                  'Doing it tough? Support is always in the Help tab.',
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
      if (widget.step == 1) ...[
        _field(
          'Preferred name',
          first,
          'firstName',
          helperText: 'What should we call you?',
        ),
        const SizedBox(height: 12),
        _field(
          'Postcode',
          postcode,
          'postcode',
          keyboard: TextInputType.number,
        ),
        choices('Age range', 'ageRange', [
          'Under 18',
          '18–24',
          '25–34',
          '35–49',
          '50–64',
          '65-79',
          '80-94',
          '95+',
          // Preserve the saved broad band on existing profiles without guessing
          // which narrower age range the person belongs to.
          if (about['ageRange'] == '65+') '65+',
        ]),
        const SizedBox(height: 16),
        Panel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 20, color: slate),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "We use your postcode to show programs nearby. It's "
                  'never shown to other members.',
                  style: const TextStyle(color: slate),
                ),
              ),
            ],
          ),
        ),
      ],
      if (widget.step == 2) ...[
        choices(
          'Gender',
          'gender',
          ['Woman', 'Man', 'Non-binary', 'Prefer not to say'],
          why:
              "It helps us see who we're reaching and make sure sessions "
              "feel welcoming for everyone. It's optional and used to improve programs and meet reporting obligations. Other participants can't see your answers. Identifying information isn't shared outside RALLY4EVER without your express permission.",
        ),
        multiChoices(
          'Cultural background',
          'culturalBackground',
          culturalBackgroundOptions,
          exclusive: culturalBackgroundExclusive,
          why:
              'It helps us make sure our programs are open to people from '
              'every community, and show funders who we reach. '
              "It's optional and used to improve programs and meet reporting obligations. Other participants can't see your answers. Identifying information isn't shared outside RALLY4EVER without your express permission.",
        ),
      ],
      if (widget.step == 3) ...[
        choices(
          'Do you have a disability or access need?',
          'accessNeed',
          ['Yes', 'No', 'Prefer not to say'],
          why:
              'It helps us plan sessions that work for everyone, for '
              "example step-free courts or a quieter start. It's "
              'optional, and we only use it to make sessions more '
              'welcoming.',
        ),
        multiChoices(
          'Right now, are you…',
          'occupation',
          occupationOptions,
          exclusive: occupationExclusive,
          why:
              'It helps us understand who our programs reach so we can '
              "keep them free and open. It's optional and grouped with "
              "other people's answers.",
        ),
        multiChoices(
          'How did you hear about us?',
          'heardAbout',
          heardAboutOptions,
          why:
              'It helps us see which posters, partners and events are '
              "working so we can reach more people. It's optional.",
        ),
        if ((about['heardAbout'] as List).contains('other')) ...[
          const SizedBox(height: 4),
          TextField(
            key: const Key('heardAboutOther'),
            controller: heardAboutOther,
            maxLength: 200,
            onChanged: (v) => setState(() => about['heardAboutOther'] = v),
            decoration: const InputDecoration(
              labelText: 'Tell us more',
              hintText: 'e.g. a poster at the library',
            ),
          ),
        ],
      ],
      if (widget.step == 4) ...[
        choices('How often do you feel lonely?', 'loneliness', [
          'Never',
          'Rarely',
          'Sometimes',
          'Often',
          'Always',
        ]),
        choices(
          'Overall, how satisfied are you with your life?',
          'satisfaction',
          List.generate(11, (i) => '$i'),
        ),
      ],
      if (widget.step == 5) ...[
        const AboutNoteRow(
          AboutIconKind.lock,
          'Your identifying information stays within RALLY4EVER unless you give express permission to share it.',
        ),
        const SizedBox(height: 12),
        const AboutNoteRow(
          AboutIconKind.clock,
          'Reports can use grouped numbers, like “60% of members are students”.',
        ),
        const SizedBox(height: 12),
        const AboutNoteRow(
          AboutIconKind.pencil,
          'Change these choices in Profile. Contact our team to request deletion of your data.',
        ),
        const SizedBox(height: 24),
        for (final item in [
          (
            'useInReports',
            'Use my answers in reports',
            'De-identified, grouped answers only.',
          ),
          (
            'wellbeingCheckIns',
            'Wellbeing check-ins',
            'A short check-in after some sessions.',
          ),
          (
            'showInWhosGoing',
            'Show me in “Who’s counted in”',
            'Your first name only; no contact details.',
          ),
          (
            'marketingEmails',
            'News and fundraising emails',
            'Choose whether to hear more from us.',
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  item.$2,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(item.$3, style: const TextStyle(fontSize: 11)),
                value: prefs[item.$1] == true,
                onChanged: (v) => setState(() => prefs[item.$1] = v),
              ),
            ),
          ),
      ],
      if (widget.step == 6) ...[
        const Text(
          'Most sessions are just a good time. If you ever feel unwell or get hurt, this tells your coach who to ring.',
          style: TextStyle(fontSize: 15, height: 1.5),
        ),
        const SizedBox(height: 16),
        const Panel(
          child: AboutNoteRow(
            AboutIconKind.lock,
            'Private. Only you, admins and coaches linked to your sessions can see it. Never other participants.',
          ),
        ),
        const SizedBox(height: 24),
        const Text(
          'YOUR EMERGENCY CONTACT',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: slate,
          ),
        ),
        const SizedBox(height: 12),
        _field(
          'Their name',
          emergencyName,
          'emergencyName',
          hint: 'e.g. Sam, my sister',
        ),
        const SizedBox(height: 12),
        _field(
          'Their mobile',
          emergencyMobile,
          'emergencyMobile',
          keyboard: TextInputType.phone,
        ),
        const Text(
          "A friend or family member you trust. It's kind to let them know.",
          style: TextStyle(fontSize: 13, color: slate, height: 1.5),
        ),
        const SizedBox(height: 24),
        const Text(
          'YOUR MOBILE',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: slate,
          ),
        ),
        const SizedBox(height: 12),
        _field(
          'Mobile number',
          mobile,
          'mobile',
          keyboard: TextInputType.phone,
        ),
      ],
      if (widget.step == 7) ...[
        Center(
          child: Column(
            children: [
              CircleAvatar(
                radius: 56,
                backgroundColor: navy,
                foregroundColor: Colors.white,
                backgroundImage: pickedPhotoBytes != null
                    ? MemoryImage(Uint8List.fromList(pickedPhotoBytes!))
                    : null,
                child: pickedPhotoBytes == null
                    ? Text(
                        (widget.profile['firstName'] as String? ?? '?').let(
                          (s) => s.isEmpty ? '?' : s[0].toUpperCase(),
                        ),
                        style: const TextStyle(fontSize: 36),
                      )
                    : null,
              ),
              const SizedBox(height: 16),
              if (photoError != null)
                Text(photoError!, style: const TextStyle(color: coral)),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => pickPhoto(ImageSource.camera),
                    child: const Text('Take a photo'),
                  ),
                  OutlinedButton(
                    onPressed: () => pickPhoto(ImageSource.gallery),
                    child: const Text('Choose from library'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
      if (error != null) Text(error!, style: const TextStyle(color: coral)),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('profile-next'),
        onPressed: save,
        child: Text(widget.step == 7 ? 'Save and find a program' : 'Next'),
      ),
      if (widget.step == 6)
        Center(
          child: TextButton(
            onPressed: widget.onSkip,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Skip for now'),
          ),
        ),
    ],
  );
}

/// A small "Why we ask" link next to an optional question's heading. Opens
/// a bottom sheet explaining the question in plain language rather than
/// cluttering the question itself with a paragraph of context.
class WhyWeAsk extends StatelessWidget {
  const WhyWeAsk({super.key, required this.title, required this.body});
  final String title;
  final String body;

  void _open(BuildContext context) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xfff2eeeb),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              Text(body, style: const TextStyle(fontSize: 16, height: 1.5)),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Got it'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Why we ask: $title',
    excludeSemantics: true,
    child: TextButton.icon(
      onPressed: () => _open(context),
      style: TextButton.styleFrom(
        foregroundColor: slate,
        minimumSize: const Size(48, 48),
      ),
      icon: const AboutIcon(AboutIconKind.question),
      label: const Text('Why we ask', style: TextStyle(fontSize: 13)),
    ),
  );
}

class PhotoTooLarge implements Exception {}

class PhotoUnreadable implements Exception {}

/// Shared by onboarding's photo step and the Me tab's quick photo action:
/// crop to a centred square, resize to 512px, re-encode as JPEG. Matches
/// storage.rules' 5MB cap and image/* contentType requirement.
List<int> processPhotoBytes(Uint8List rawBytes) {
  if (rawBytes.lengthInBytes > 5 * 1024 * 1024) throw PhotoTooLarge();
  final decoded = img.decodeImage(rawBytes);
  if (decoded == null) throw PhotoUnreadable();
  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final square = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );
  final resized = img.copyResize(square, width: 512, height: 512);
  return img.encodeJpg(resized, quality: 85);
}

/// `+61` default, normalised to E.164. Leaves an already-E.164-looking value
/// (`+` followed by digits) alone; treats a local `0...` number as domestic.
String normalizeAustralianMobile(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';
  final digits = trimmed.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.startsWith('+')) return digits;
  if (digits.startsWith('0')) return '+61${digits.substring(1)}';
  return '+61$digits';
}

class DetailsForm extends StatefulWidget {
  const DetailsForm({super.key, required this.profile, required this.onSave});
  final Record profile;
  final Future<void> Function(Record) onSave;
  @override
  State<DetailsForm> createState() => _DetailsFormState();
}

class _DetailsFormState extends State<DetailsForm> {
  late final controllers = {
    for (final field in ['firstName', 'lastName', 'mobile', 'injuries'])
      field: TextEditingController(
        text: widget.profile[field] as String? ?? '',
      ),
    'emergencyName': TextEditingController(
      text:
          (widget.profile['emergencyContact'] as Map?)?['name'] as String? ??
          '',
    ),
    'emergencyMobile': TextEditingController(
      text:
          (widget.profile['emergencyContact'] as Map?)?['mobile'] as String? ??
          '',
    ),
  };
  String? error;
  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Panel(
        color: pink,
        child: Text(
          'We ask once. Your details help the coach keep everyone safe.',
        ),
      ),
      const SizedBox(height: 20),
      for (final item in [
        ('firstName', 'First name'),
        ('lastName', 'Last name (optional)'),
        ('mobile', 'Mobile'),
        ('emergencyName', 'Emergency contact name'),
        ('emergencyMobile', 'Emergency contact mobile'),
        ('injuries', 'Injuries or anything we should know (optional)'),
      ]) ...[
        _field(
          item.$2,
          controllers[item.$1]!,
          item.$1,
          keyboard: item.$1.toLowerCase().contains('mobile')
              ? TextInputType.phone
              : null,
        ),
        const SizedBox(height: 8),
      ],
      if (error != null) Text(error!, style: const TextStyle(color: coral)),
      FilledButton(
        onPressed: () async {
          if ([
            'firstName',
            'mobile',
            'emergencyName',
            'emergencyMobile',
          ].any((k) => controllers[k]!.text.trim().isEmpty)) {
            setState(
              () => error = 'Complete your name, mobile and emergency contact.',
            );
            return;
          }
          await widget.onSave({
            'firstName': controllers['firstName']!.text.trim(),
            'lastName': controllers['lastName']!.text.trim(),
            'mobile': controllers['mobile']!.text.trim(),
            'injuries': controllers['injuries']!.text.trim(),
            'emergencyContact': {
              'name': controllers['emergencyName']!.text.trim(),
              'mobile': controllers['emergencyMobile']!.text.trim(),
            },
          });
        },
        child: const Text('Continue'),
      ),
    ],
  );
}

class FeedbackForm extends StatefulWidget {
  const FeedbackForm({
    super.key,
    required this.eventName,
    required this.onSend,
  });
  final String eventName;
  final Future<void> Function(int, List<String>, String) onSend;
  @override
  State<FeedbackForm> createState() => _FeedbackFormState();
}

class _FeedbackFormState extends State<FeedbackForm> {
  int rating = 0;
  final tags = <String>{};
  final comment = TextEditingController();
  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('How was it?', style: Theme.of(context).textTheme.headlineLarge),
      Text(
        widget.eventName,
        style: const TextStyle(color: coral, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      const Text('A little feedback helps us make play better for everyone.'),
      const SizedBox(height: 28),
      const Text('Overall', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(
          5,
          (i) => IconButton.filled(
            key: Key('rating-${i + 1}'),
            style: IconButton.styleFrom(
              backgroundColor: rating >= i + 1 ? coral : Colors.white,
              foregroundColor: rating >= i + 1 ? Colors.white : slate,
            ),
            onPressed: () => setState(() => rating = i + 1),
            icon: Icon(
              [
                Icons.sentiment_very_dissatisfied,
                Icons.sentiment_dissatisfied,
                Icons.sentiment_neutral,
                Icons.sentiment_satisfied,
                Icons.sentiment_very_satisfied,
              ][i],
            ),
          ),
        ),
      ),
      const SizedBox(height: 24),
      const Text(
        'What stood out?',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      Wrap(
        spacing: 8,
        children:
            [
                  'coaching',
                  'people',
                  'atmosphere',
                  'accessibility',
                  'timing',
                  'other',
                ]
                .map(
                  (v) => FilterChip(
                    label: Text(v),
                    selected: tags.contains(v),
                    onSelected: (yes) =>
                        setState(() => yes ? tags.add(v) : tags.remove(v)),
                  ),
                )
                .toList(),
      ),
      const SizedBox(height: 24),
      TextField(
        controller: comment,
        maxLines: 4,
        maxLength: 2000,
        decoration: const InputDecoration(
          labelText: 'Anything else? (optional)',
          hintText: 'One thing that would make next time better…',
        ),
      ),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('send-feedback'),
        onPressed: rating == 0
            ? null
            : () => widget.onSend(rating, tags.toList(), comment.text.trim()),
        child: const Text('Send feedback'),
      ),
    ],
  );
}

const _noAppSteps = [
  (Icons.person_outline, 'Your details'),
  (Icons.description_outlined, 'Agreements'),
  (Icons.check_circle_outline, 'Done'),
];

class NoAppCheckInForm extends StatefulWidget {
  const NoAppCheckInForm({
    super.key,
    required this.repository,
    this.cameraEnabled = true,
    this.onCreateAccount,
  });
  final ParticipantRepository repository;
  final bool cameraEnabled;
  final VoidCallback? onCreateAccount;
  @override
  State<NoAppCheckInForm> createState() => _NoAppCheckInFormState();
}

class _NoAppCheckInFormState extends State<NoAppCheckInForm> {
  final fields = {
    for (final k in [
      'email',
      'firstName',
      'mobile',
      'emergencyName',
      'emergencyMobile',
      'qr',
      'emailLink',
    ])
      k: TextEditingController(),
  };
  List<Record> forms = [];
  Record? position, sessionInfo;
  CheckInLink? link;
  String? requestId, error;
  // 0 scan, 1 confirm session, 2 your details, 3 agreements, 4 done.
  int stage = 0;
  int agreementIndex = 0;
  bool accepted = false, busy = false, pending = false, showPasteLink = false;
  bool countOnly = false;
  final Map<String, dynamic> signedVersions = {};
  MobileScannerController? scanner;
  @override
  void initState() {
    super.initState();
    // Prefill from a previous no-account check-in on this device, so a
    // returning participant doesn't have to retype everything.
    for (final entry in widget.repository.lastNoAppCheckIn.entries) {
      fields[entry.key]?.text = entry.value;
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    unawaited(scanner?.dispose());
    super.dispose();
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
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Shared by the camera's onDetect and the paste-a-link fallback: loads
  /// the session (for the "Is this your session?" confirmation) and its
  /// agreements from whatever QR/link text came in.
  Future<void> _scan(String raw) => run(() async {
    await scanner?.stop();
    try {
      final parsed = CheckInLink.parse(raw);
      Record pos;
      try {
        pos = await widget.repository.location();
      } catch (_) {
        // No fix (denied, GPS off, approximate-only): never block scanning
        // -- the coach confirms everyone in person regardless.
        pos = const {};
      }
      final info = await widget.repository.call('getNoAppForms', {
        'eventCode': parsed.eventCode,
        'secret': parsed.secret,
        ...pos,
      });
      if (mounted) {
        setState(() {
          link = parsed;
          position = pos;
          sessionInfo = info;
          forms = agreementGroups(
            (info['forms'] as List)
                .map((f) => Map<String, dynamic>.from(f as Map))
                .toList(),
          );
          stage = 1;
        });
      }
    } finally {
      if (mounted && link == null) await scanner?.start();
    }
  });

  void _scanAgain() => setState(() {
    link = null;
    sessionInfo = null;
    forms = [];
    agreementIndex = 0;
    accepted = false;
    countOnly = false;
    signedVersions.clear();
    error = null;
    stage = 0;
    unawaited(scanner?.start());
  });

  static const _detailFields = [
    ('email', 'Email'),
    ('firstName', 'First name'),
    ('mobile', 'Mobile'),
    ('emergencyName', 'Emergency contact name'),
    ('emergencyMobile', 'Emergency contact mobile'),
  ];
  List<String> get _missingDetails => [
    for (final field in _detailFields)
      if (fields[field.$1]!.text.trim().isEmpty) field.$2,
  ];

  @override
  Widget build(BuildContext context) {
    if (widget.cameraEnabled && stage == 0) {
      scanner ??= MobileScannerController();
    }
    if (pending) {
      return const Column(
        children: [
          SizedBox(height: 40),
          CircleAvatar(
            radius: 40,
            backgroundColor: pink,
            child: Icon(Icons.schedule, size: 36, color: navy),
          ),
          SizedBox(height: 22),
          Text(
            'Checked in. Waiting for your coach',
            style: TextStyle(
              fontFamily: 'Jellee',
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: navy,
            ),
          ),
          SizedBox(height: 16),
          Text(
            'Ask your coach to confirm you at the court. They can see your distance and scan time.',
          ),
        ],
      );
    }
    if (stage == 4) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepBar(steps: _noAppSteps, current: 3),
          const SizedBox(height: 32),
          const Center(
            child: Icon(Icons.check_circle_outline, color: coral, size: 56),
          ),
          const SizedBox(height: 16),
          Text(
            "You're checked in",
            style: Theme.of(context).textTheme.headlineLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          const Text(
            'Your coach will confirm you in person.',
            textAlign: TextAlign.center,
            style: TextStyle(color: slate),
          ),
          const SizedBox(height: 28),
          if (widget.onCreateAccount != null)
            Center(
              child: TextButton(
                key: const Key('soft-create-account'),
                onPressed: widget.onCreateAccount,
                child: const Text(
                  'Want to save your details for next time? Create an account',
                ),
              ),
            ),
        ],
      );
    }
    if (requestId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (error != null) Panel(color: pink, child: Text(error!)),
          if (busy) const LinearProgressIndicator(),
          const Panel(
            color: pink,
            child: Text(
              'Open the one-time sign-in link sent to your email, then paste it here. Your attendance has not been recorded yet.',
            ),
          ),
          _field(
            'Email sign-in link',
            fields['emailLink']!,
            'noapp-email-link',
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    final uri = Uri.parse(fields['emailLink']!.text);
                    final result = await widget.repository.call(
                      'completeNoAppCheckIn',
                      {
                        'requestId': requestId,
                        'oobCode': uri.queryParameters['oobCode'] ?? '',
                        'secret': link!.secret,
                      },
                    );
                    if (mounted) {
                      setState(() {
                        if (result['status'] == 'pending') pending = true;
                        stage = 4;
                      });
                    }
                  }),
            child: const Text('Verify and check in'),
          ),
        ],
      );
    }
    if (stage == 0) return _scanStage(context);
    if (stage == 1) return _confirmStage(context);
    if (stage == 2) return _detailsStage(context);
    return _agreementsStage(context);
  }

  Widget _scanStage(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        "Point your camera at the coach's QR code.",
        style: TextStyle(color: slate),
      ),
      const SizedBox(height: 16),
      if (error != null) ...[
        Panel(color: pink, child: Text(error!)),
        const SizedBox(height: 10),
        Center(
          child: OutlinedButton(
            key: const Key('scan-again'),
            onPressed: () => setState(() => error = null),
            child: const Text('Scan again'),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (busy) const LinearProgressIndicator(),
      ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: SizedBox(
          // As large as this themed (non full-bleed) page can sensibly
          // give it, so the camera reads as the main event on screen.
          height: (MediaQuery.sizeOf(context).height * 0.5).clamp(260, 480),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (widget.cameraEnabled)
                MobileScanner(
                  key: const Key('noapp-scanner'),
                  controller: scanner!,
                  onDetect: (capture) {
                    if (busy) return;
                    final value = capture.barcodes.firstOrNull?.rawValue;
                    if (value != null) unawaited(_scan(value));
                  },
                  errorBuilder: (context, error) => _cameraFallback(context),
                )
              else
                _cameraFallback(context),
              Center(
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    border: Border.all(color: coral, width: 3),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Center(
        child: TextButton(
          key: const Key('toggle-paste-link'),
          onPressed: () => setState(() => showPasteLink = !showPasteLink),
          child: const Text("Can't scan? Enter the code instead"),
        ),
      ),
      if (showPasteLink) ...[
        _field('Session link or code', fields['qr']!, 'noapp-qr'),
        const SizedBox(height: 8),
        OutlinedButton(
          key: const Key('noapp-use-code'),
          onPressed: busy ? null : () => _scan(fields['qr']!.text),
          child: const Text('Use this code'),
        ),
      ],
      const SizedBox(height: 16),
      const Text(
        'Your coach confirms every check-in in person. This does not sign you in to the member app.',
        style: TextStyle(fontSize: 12, color: slate),
      ),
    ],
  );

  Widget _cameraFallback(BuildContext context) => ColoredBox(
    color: const Color(0xffe4dfdd),
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt_outlined, color: slate, size: 32),
            const SizedBox(height: 12),
            const Text(
              "We can't reach the camera. Enter a code or link instead, or allow camera access in Settings.",
              textAlign: TextAlign.center,
              style: TextStyle(color: slate),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              key: const Key('open-camera-settings'),
              onPressed: () => unawaited(openAppSettings()),
              child: const Text('Open settings'),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _confirmStage(BuildContext context) {
    final info = sessionInfo!;
    final start = DateTime.tryParse(info['startsAt'] as String? ?? '');
    final venue = info['venue'] as Map? ?? {};
    final venueLabel = [
      venue['name'],
      venue['suburb'],
    ].where((v) => v != null && '$v'.isNotEmpty).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Text(
          "You're checking in",
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        Panel(
          key: const Key('confirm-session-card'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${info['name']}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.place_outlined, size: 18, color: slate),
                  const SizedBox(width: 8),
                  Expanded(child: Text(venueLabel)),
                ],
              ),
              if (start != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.schedule, size: 18, color: slate),
                    const SizedBox(width: 8),
                    Text(friendlyDateTime(start)),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('confirm-session'),
          onPressed: () => setState(() => stage = 2),
          child: const Text('Continue'),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            key: const Key('scan-again'),
            onPressed: _scanAgain,
            child: const Text('Scan again'),
          ),
        ),
      ],
    );
  }

  Widget _detailsStage(BuildContext context) {
    final missing = _missingDetails;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepBar(steps: _noAppSteps, current: 1),
        const SizedBox(height: 24),
        Text('Your details', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('noapp-count-only'),
          onPressed: busy
              ? null
              : () => setState(() {
                  countOnly = true;
                  signedVersions.clear();
                  agreementIndex = 0;
                  accepted = false;
                  stage = 3;
                }),
          child: const Text('Skip details — count me as +1'),
        ),
        const Text(
          'No name, email or account. Read the required agreements, then ask your coach to confirm your +1.',
          style: TextStyle(color: slate),
        ),
        const SizedBox(height: 20),
        if (error != null) Panel(color: pink, child: Text(error!)),
        _field(
          'Email',
          fields['email']!,
          'noapp-email',
          keyboard: TextInputType.emailAddress,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _field(
          'First name',
          fields['firstName']!,
          'noapp-firstName',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _field(
          'Mobile',
          fields['mobile']!,
          'noapp-mobile',
          keyboard: TextInputType.phone,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        const Text(
          'So we can reach someone if you’re hurt',
          style: TextStyle(fontSize: 12, color: slate),
        ),
        const SizedBox(height: 4),
        _field(
          'Emergency contact name',
          fields['emergencyName']!,
          'noapp-emergencyName',
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        _field(
          'Emergency contact mobile',
          fields['emergencyMobile']!,
          'noapp-emergencyMobile',
          keyboard: TextInputType.phone,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 20),
        if (missing.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Still needed: ${missing.join(', ')}',
              key: const Key('missing-details'),
              style: const TextStyle(color: slate, fontSize: 12),
            ),
          ),
        FilledButton(
          key: const Key('details-continue'),
          onPressed: missing.isNotEmpty
              ? null
              : () => setState(() {
                  countOnly = false;
                  signedVersions.clear();
                  accepted = false;
                  agreementIndex = 0;
                  stage = 3;
                }),
          child: const Text('Continue'),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => setState(() => stage = 1),
            child: const Text('Back'),
          ),
        ),
      ],
    );
  }

  Widget _agreementsStage(BuildContext context) {
    if (!requiredAgreementIds.every(
      (id) => forms.expand(formSources).any((f) => f['id'] == id),
    )) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          StepBar(steps: _noAppSteps, current: 2),
          const SizedBox(height: 24),
          const Panel(
            color: pink,
            child: Text(
              "This session needs a form that isn't available yet. Please see your coach.",
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () => setState(() => stage = 2),
              child: const Text('Back'),
            ),
          ),
        ],
      );
    }
    final f = forms[agreementIndex];
    final required = f['required'] == true;
    final last = agreementIndex == forms.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StepBar(steps: _noAppSteps, current: 2),
        const SizedBox(height: 10),
        Text(
          'Agreement ${agreementIndex + 1} of ${forms.length}',
          style: const TextStyle(
            color: slate,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 14),
        if (countOnly)
          const Panel(
            child: Text(
              'Anonymous +1. Your personal details will not be sent. Your coach must confirm attendance.',
            ),
          ),
        if (error != null) Panel(color: pink, child: Text(error!)),
        if (busy) const LinearProgressIndicator(),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${f['title']}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              LegalFormText(formText(f)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: Key('agree-${f['id']}'),
          value: accepted,
          onChanged: (v) => setState(() => accepted = v ?? false),
          title: const Text('I agree'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('agreement-continue'),
          onPressed: busy || (required && !accepted)
              ? null
              : () {
                  if (accepted) {
                    for (final source in formSources(f)) {
                      signedVersions['${source['id']}'] = source['version'];
                    }
                  } else {
                    for (final source in formSources(f)) {
                      signedVersions.remove('${source['id']}');
                    }
                  }
                  if (!last) {
                    setState(() {
                      agreementIndex++;
                      accepted = false;
                    });
                    return;
                  }
                  run(() async {
                    final result = await widget.repository.call(
                      'beginNoAppCheckIn',
                      {
                        if (countOnly) ...{
                          'countOnly': true,
                          'anonymousToken': widget.repository.anonymousTokenFor(
                            '${sessionInfo!['eventId'] ?? link!.eventCode}',
                          ),
                        } else ...{
                          'email': fields['email']!.text,
                          'firstName': fields['firstName']!.text,
                          'mobile': fields['mobile']!.text,
                          'emergencyContact': {
                            'name': fields['emergencyName']!.text,
                            'mobile': fields['emergencyMobile']!.text,
                          },
                        },
                        'eventCode': link!.eventCode,
                        'secret': link!.secret,
                        ...position!,
                        'signedVersions': Map<String, dynamic>.from(
                          signedVersions,
                        ),
                      },
                    );
                    if (!countOnly) {
                      widget.repository.saveNoAppCheckIn({
                        'email': fields['email']!.text.trim(),
                        'firstName': fields['firstName']!.text.trim(),
                        'mobile': fields['mobile']!.text.trim(),
                        'emergencyName': fields['emergencyName']!.text.trim(),
                        'emergencyMobile': fields['emergencyMobile']!.text
                            .trim(),
                      });
                    }
                    if (mounted) {
                      setState(() {
                        if (result['requestId'] != null) {
                          requestId = result['requestId'] as String?;
                        } else {
                          if (result['status'] == 'pending') pending = true;
                          stage = 4;
                        }
                      });
                    }
                  });
                },
          child: Text(last ? 'Check in' : 'Agree and continue'),
        ),
        const SizedBox(height: 10),
        Center(
          child: TextButton(
            onPressed: () => setState(
              () => agreementIndex == 0 ? stage = 2 : agreementIndex--,
            ),
            child: const Text('Back'),
          ),
        ),
      ],
    );
  }
}

class SignInMethodsPanel extends StatefulWidget {
  const SignInMethodsPanel({super.key, required this.repository});
  final ParticipantRepository repository;
  @override
  State<SignInMethodsPanel> createState() => _SignInMethodsPanelState();
}

class _SignInMethodsPanelState extends State<SignInMethodsPanel> {
  final password = TextEditingController(),
      confirmation = TextEditingController();
  bool busy = false, visible = false, needsVerification = false;
  String? error;
  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> connect() async {
    if (password.text.length < 8 || password.text != confirmation.text) {
      setState(
        () => error =
            'Use at least 8 characters and enter the same password twice.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (needsVerification) await widget.repository.reauthenticateGoogle();
      await widget.repository.addAppPassword(password.text);
      password.clear();
      confirmation.clear();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = friendlyError(e);
          if (e is RecentSignInRequired) needsVerification = true;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'One account, either sign-in method',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      Text(widget.repository.email ?? ''),
      const SizedBox(height: 16),
      const Text(
        'Your profile, role and attendance stay the same whichever method you use. Your Google password stays with Google; your RALLY4EVER password is set separately.',
      ),
      const SizedBox(height: 16),
      Text(
        widget.repository.googleUser ? 'Google sign-in: connected' : 'Google sign-in: use a Google account with this same email on the sign-in screen.',
      ),
      const SizedBox(height: 12),
      if (widget.repository.passwordUser)
        const Panel(
          child: Text(
            'Email/password sign-in: connected. Use Forgot password? on the sign-in screen to reset it.',
          ),
        )
      else ...[
        const Text('Add a password so you can also sign in with email'),
        const SizedBox(height: 12),
        TextField(
          key: const Key('link-password'),
          controller: password,
          obscureText: !visible,
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'New password',
            suffixIcon: IconButton(
              onPressed: () => setState(() => visible = !visible),
              icon: Icon(visible ? Icons.visibility_off : Icons.visibility),
              tooltip: visible ? 'Hide password' : 'Show password',
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const Key('link-password-confirm'),
          controller: confirmation,
          obscureText: !visible,
          decoration: const InputDecoration(labelText: 'Confirm password'),
        ),
        if (error != null) Panel(color: pink, child: Text(error!)),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('connect-email-password'),
          onPressed: busy ? null : connect,
          child: Text(
            busy
                ? 'Connecting…'
                : needsVerification
                ? 'Verify with Google & enable email sign-in'
                : 'Enable email sign-in',
          ),
        ),
      ],
    ],
  );
}
