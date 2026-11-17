import 'package:flutter/material.dart';

import 'repository.dart';
import 'theme.dart';

class AccountForm extends StatefulWidget {
  const AccountForm({
    super.key,
    required this.repository,
    required this.onAction,
    required this.busy,
  });
  final ParticipantRepository repository;
  final Future<void> Function(Future<void> Function()) onAction;
  final bool busy;
  @override
  State<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends State<AccountForm> {
  final email = TextEditingController(),
      password = TextEditingController(),
      link = TextEditingController();
  bool signup = false, showLink = false;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    link.dispose();
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
      if (!showLink) ...[
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
      ],
      const SizedBox(height: 20),
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
      const Divider(height: 28),
      OutlinedButton(
        onPressed: widget.busy || !widget.repository.enabled
            ? null
            : () => widget.onAction(() async {
                await widget.repository.sendLink(email.text);
                if (mounted) setState(() => showLink = true);
              }),
        child: const Text('Email me a one-time sign-in link'),
      ),
      TextButton(
        onPressed: () => setState(() => showLink = !showLink),
        child: const Text('I have an email link'),
      ),
      if (showLink) ...[
        _field('Email link', link, 'email-link'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: widget.busy
              ? null
              : () => widget.onAction(
                  () => widget.repository.completeLink(email.text, link.text),
                ),
          child: const Text('Continue with email link'),
        ),
      ],
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

class ProfileStep extends StatefulWidget {
  const ProfileStep({
    super.key,
    required this.step,
    required this.profile,
    required this.onSave,
    required this.onSkip,
  });
  final int step;
  final Record profile;
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
  late final Record about = Map<String, dynamic>.from(
    widget.profile['about'] as Map? ?? {},
  );
  late final Record prefs = {
    'useInReports': false,
    'wellbeingCheckIns': false,
    'showInWhosGoing': false,
    'marketingEmails': false,
    ...Map<String, dynamic>.from(widget.profile['preferences'] as Map? ?? {}),
  };
  String? error;
  @override
  void dispose() {
    first.dispose();
    postcode.dispose();
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
  Future<void> save() async {
    if (widget.step == 1 &&
        (first.text.trim().isEmpty ||
            !RegExp(r'^\d{4}$').hasMatch(postcode.text.trim()))) {
      setState(
        () => error = 'Enter your first name and a four-digit postcode.',
      );
      return;
    }
    await widget.onSave(
      widget.step == 1
          ? {
              'firstName': first.text.trim(),
              'postcode': postcode.text.trim(),
              'about': about,
            }
          : widget.step == 5
          ? {'preferences': prefs}
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
            'Step ${widget.step} of 5',
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
        value: widget.step / 5,
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
        _field('First name', first, 'firstName'),
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
        choices('Cultural background', 'culturalBackground', [
          'Aboriginal and/or Torres Strait Islander',
          'Born outside Australia',
          'Prefer not to say',
        ]),
      ],
      if (widget.step == 3) ...[
        choices('Do you have a disability or access need?', 'accessNeed', [
          'Yes',
          'No',
          'Prefer not to say',
        ]),
        choices('Right now, are you…', 'currentActivity', [
          'Working',
          'Studying',
          'Looking for work',
          'Retired',
          'Prefer not to say',
        ]),
        choices('How did you hear about us?', 'referral', [
          'Friend',
          'Uni / campus',
          'Social media',
          'Local club',
          'Other',
        ]),
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
      if (error != null) Text(error!, style: const TextStyle(color: coral)),
      const SizedBox(height: 24),
      FilledButton(
        key: const Key('profile-next'),
        onPressed: save,
        child: Text(widget.step == 5 ? 'Save and find a program' : 'Next'),
      ),
    ],
  );
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
