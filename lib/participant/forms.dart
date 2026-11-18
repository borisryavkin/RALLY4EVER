import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'repository.dart';
import 'theme.dart';

class AccountForm extends StatefulWidget {
  const AccountForm({
    super.key,
    required this.repository,
    required this.onAction,
    required this.busy,
    required this.onForgotPassword,
  });
  final ParticipantRepository repository;
  final Future<void> Function(Future<void> Function()) onAction;
  final bool busy;
  final VoidCallback onForgotPassword;
  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final email = TextEditingController(), password = TextEditingController();
  bool signup = false;
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
      const SizedBox(height: 48),
      const Text(
        'ONE COMMUNITY. ONE ACCOUNT.',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: slate,
        ),
      ),
      const SizedBox(height: 14),
      Text(
        widget.repository.email != null && !widget.repository.verified
            ? 'Check your inbox'
            : signup
            ? 'Join the\ncommunity'
            : 'Welcome\nback',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 12),
      Text(
        widget.repository.email != null && !widget.repository.verified
            ? 'Open the verification email, then come back here.'
            : 'One email, one profile. Find your people and your next session.',
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
        'Coaches: use your Google Workspace account. Access is approved by your admin.',
        style: TextStyle(fontSize: 12),
      ),
      const SizedBox(height: 16),
      _field('Email', email, 'email', keyboard: TextInputType.emailAddress),
      const SizedBox(height: 14),
      TextField(
        key: const Key('password'),
        controller: password,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Password',
          hintText: 'At least 6 characters',
        ),
      ),
      if (!signup) ...[
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            key: const Key('forgot-password'),
            onPressed: widget.onForgotPassword,
            child: const Text('Forgot password?'),
          ),
        ),
      ],
      const SizedBox(height: 6),
      FilledButton(
        key: const Key('authenticate'),
        onPressed: widget.busy || !widget.repository.enabled
            ? null
            : () => widget.onAction(
                () => signup
                    ? widget.repository.signUp(email.text, password.text)
                    : widget.repository.signIn(email.text, password.text),
              ),
        child: Text(signup ? 'Create account' : 'Sign in'),
      ),
      if (widget.repository.email != null && !widget.repository.verified) ...[
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () =>
              widget.onAction(widget.repository.refreshVerification),
          child: const Text("I've verified my email"),
        ),
      ],
      TextButton(
        onPressed: () => setState(() => signup = !signup),
        child: Text(
          signup ? 'Already a member? Sign in' : 'New here? Create an account',
        ),
      ),
      if (!widget.repository.enabled)
        const Panel(
          color: pink,
          child: Text(
            'Start the local emulators and run with USE_FIREBASE_EMULATORS=true to sign in.',
          ),
        ),
      const SizedBox(height: 16),
      const Text(
        'Coaches use their pre-created account. Tools appear according to your role.',
        style: TextStyle(fontSize: 12, color: slate),
      ),
    ],
  );
}

Widget _field(
  String label,
  TextEditingController controller,
  String name, {
  TextInputType? keyboard,
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
        decoration: InputDecoration(hintText: label),
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
        'If you normally use Google, tap Continue with Google instead.',
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
  'aboriginal_torres_strait_islander': 'Aboriginal and/or Torres Strait Islander',
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
  String? keyFor(Map<String, String> options, Object? label) =>
      options.entries
          .firstWhere(
            (e) => e.value == label,
            orElse: () => const MapEntry('', ''),
          )
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
  if (about.containsKey('referralOther') && !about.containsKey('heardAboutOther')) {
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
  });
  final int step;
  final Record profile;
  final Record contact;
  final Future<void> Function(Record) onSave;
  final VoidCallback onSkip;
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
        (widget.contact['emergencyContact'] as Map?)?['name'] as String? ??
        '',
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

  Widget choices(String label, String name, List<String> options) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w700, color: navy),
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
  }) {
    final selected = Set<String>.from(about[name] as List? ?? const []);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, color: navy),
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
    final rawBytes = await picked.readAsBytes();
    if (rawBytes.lengthInBytes > 5 * 1024 * 1024) {
      setState(() => photoError = 'Choose a photo under 5 MB.');
      return;
    }
    final decoded = img.decodeImage(rawBytes);
    if (decoded == null) {
      setState(() => photoError = 'That file could not be read as an image.');
      return;
    }
    final side = decoded.width < decoded.height ? decoded.width : decoded.height;
    final square = img.copyCrop(
      decoded,
      x: (decoded.width - side) ~/ 2,
      y: (decoded.height - side) ~/ 2,
      width: side,
      height: side,
    );
    final resized = img.copyResize(square, width: 512, height: 512);
    setState(() {
      pickedPhotoBytes = img.encodeJpg(resized, quality: 85);
      removePhoto = false;
    });
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
    await widget.onSave(
      widget.step == 1
          ? {
              'firstName': first.text.trim(),
              'postcode': postcode.text.trim(),
              'about': about,
            }
          : widget.step == 5
          ? {'preferences': prefs}
          : widget.step == 6
          ? {
              'mobile': mobile.text.trim().replaceAll(' ', '') == '+61'
                  ? ''
                  : normalizeAustralianMobile(mobile.text),
              'emergencyContact': {
                'name': emergencyName.text.trim(),
                'mobile': emergencyMobile.text.trim().isEmpty
                    ? ''
                    : normalizeAustralianMobile(emergencyMobile.text),
              },
            }
          : widget.step == 7
          ? {
              'photoBytes': removePhoto ? null : pickedPhotoBytes,
              'photoSkip': pickedPhotoBytes == null && !removePhoto,
            }
          : {'about': about},
    );
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
          if (widget.step > 1)
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
          'In case we ever\nneed to reach you',
          'Add a photo\n(optional)',
        ][widget.step - 1],
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 10),
      Text(
        widget.step == 1
            ? 'Just the basics to get you started.'
            : 'Optional. Share what feels right for you.',
      ),
      const SizedBox(height: 24),
      if (widget.step == 1) ...[
        _field('Name', first, 'firstName'),
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
          '65+',
        ]),
      ],
      if (widget.step == 2) ...[
        choices('Gender', 'gender', [
          'Woman',
          'Man',
          'Non-binary',
          'Prefer not to say',
        ]),
        multiChoices(
          'Cultural background',
          'culturalBackground',
          culturalBackgroundOptions,
          exclusive: culturalBackgroundExclusive,
        ),
      ],
      if (widget.step == 3) ...[
        choices('Do you have a disability or access need?', 'accessNeed', [
          'Yes',
          'No',
          'Prefer not to say',
        ]),
        multiChoices(
          'Right now, are you…',
          'occupation',
          occupationOptions,
          exclusive: occupationExclusive,
        ),
        multiChoices('How did you hear about us?', 'heardAbout', heardAboutOptions),
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
        const Text(
          'You can change these choices in your profile.',
          style: TextStyle(fontSize: 12),
        ),
      ],
      if (widget.step == 6) ...[
        const Text(
          'Optional. Not shared with other participants; visible only to you, '
          'admins, and a coach for a session you attend.',
          style: TextStyle(fontSize: 12),
        ),
        const SizedBox(height: 16),
        _field(
          'Mobile number',
          mobile,
          'mobile',
          keyboard: TextInputType.phone,
        ),
        const SizedBox(height: 12),
        _field('Emergency contact name', emergencyName, 'emergencyName'),
        const SizedBox(height: 12),
        _field(
          'Emergency contact number',
          emergencyMobile,
          'emergencyMobile',
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
                        (widget.profile['firstName'] as String? ?? '?')
                            .let((s) => s.isEmpty ? '?' : s[0].toUpperCase()),
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
    ],
  );
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

class NoAppCheckInForm extends StatefulWidget {
  const NoAppCheckInForm({super.key, required this.repository});
  final ParticipantRepository repository;
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
  Record? position;
  CheckInLink? link;
  String? requestId, error;
  bool accepted = false, busy = false, pending = false;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function() task) async {
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

  @override
  Widget build(BuildContext context) {
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
              fontFamily: 'Figtree',
              fontSize: 26,
              fontWeight: FontWeight.w800,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Check in with\nyour coach',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 10),
        const Text(
          'No app account needed. Returning members may need to verify their email.',
        ),
        const SizedBox(height: 20),
        if (error != null) Panel(color: pink, child: Text(error!)),
        if (busy) const LinearProgressIndicator(),
        if (requestId != null) ...[
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
                    if (result['status'] == 'pending' && mounted) {
                      setState(() => pending = true);
                    }
                  }),
            child: const Text('Verify and check in'),
          ),
        ] else ...[
          _field('Session QR link', fields['qr']!, 'noapp-qr'),
          OutlinedButton(
            onPressed: busy
                ? null
                : () => run(() async {
                    link = CheckInLink.parse(fields['qr']!.text);
                    position = await widget.repository.location();
                    final info = await widget.repository.call('getNoAppForms', {
                      'eventCode': link!.eventCode,
                      'secret': link!.secret,
                      ...position!,
                    });
                    if (mounted) {
                      setState(
                        () => forms = (info['forms'] as List)
                            .map((f) => Map<String, dynamic>.from(f as Map))
                            .toList(),
                      );
                    }
                  }),
            child: const Text('Load session agreements'),
          ),
          const SizedBox(height: 14),
          for (final item in [
            ('email', 'Email'),
            ('firstName', 'First name'),
            ('mobile', 'Mobile'),
            ('emergencyName', 'Emergency contact name'),
            ('emergencyMobile', 'Emergency contact mobile'),
          ])
            _field(item.$2, fields[item.$1]!, 'noapp-${item.$1}'),
          for (final f in forms) ...[
            const SizedBox(height: 12),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${f['title']} · v${f['version']}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(f['content'] as String),
                ],
              ),
            ),
          ],
          if (forms.isNotEmpty)
            CheckboxListTile(
              value: accepted,
              onChanged: (v) => setState(() => accepted = v ?? false),
              title: const Text('I have read and agree to these forms.'),
            ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: busy || !accepted || link == null
                ? null
                : () => run(() async {
                    final result = await widget.repository.call(
                      'beginNoAppCheckIn',
                      {
                        'email': fields['email']!.text,
                        'eventCode': link!.eventCode,
                        'secret': link!.secret,
                        ...position!,
                        'firstName': fields['firstName']!.text,
                        'mobile': fields['mobile']!.text,
                        'emergencyContact': {
                          'name': fields['emergencyName']!.text,
                          'mobile': fields['emergencyMobile']!.text,
                        },
                        'signedVersions': {
                          for (final f in forms) f['id']: f['version'],
                        },
                      },
                    );
                    if (mounted) {
                      setState(() {
                        requestId = result['requestId'] as String?;
                        pending = result['status'] == 'pending';
                      });
                    }
                  }),
            child: const Text('Check in'),
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'Your coach confirms every check-in in person. This does not sign you in to the member app.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}
