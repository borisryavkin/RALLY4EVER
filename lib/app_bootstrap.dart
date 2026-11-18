import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'data/build_environment.dart';
import 'data/emulator_backend.dart';
import 'data/staging_backend.dart';
import 'participant/app.dart';
import 'participant/repository.dart';
import 'participant/theme.dart';

Future<ParticipantRepository> connectParticipantRepository() async {
  final environment = BuildEnvironment.validate();
  if (environment == 'emulator' &&
      !const bool.fromEnvironment('USE_FIREBASE_EMULATORS')) {
    return DisabledParticipantRepository(); // Explicit debug preview only.
  }
  final backend = environment == 'staging'
      ? await StagingBackend.connect()
      : await EmulatorBackend.connect();
  final repository = FirebaseParticipantRepository(backend);
  try {
    await repository.restore();
    return repository;
  } catch (_) {
    repository.dispose();
    rethrow;
  }
}

/// Initialization failures stay visible and retryable instead of turning a
/// staging installation into a disabled emulator-preview sign-in screen.
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, this.connect = connectParticipantRepository});
  final Future<ParticipantRepository> Function() connect;

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _StartupResult {
  const _StartupResult({this.repository, this.error});
  final ParticipantRepository? repository;
  final Object? error;
}

class _AppBootstrapState extends State<AppBootstrap> {
  ParticipantRepository? _repository;
  late Future<_StartupResult> connection = _connect();

  Future<_StartupResult> _connect() async {
    try {
      final repository = await widget.connect();
      if (!mounted) {
        repository.dispose();
      } else {
        _repository = repository;
      }
      return _StartupResult(repository: repository);
    } catch (error) {
      // Capture before a rebuild attaches FutureBuilder's listener on retry.
      return _StartupResult(error: error);
    }
  }

  @override
  void dispose() {
    _repository?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_StartupResult>(
    future: connection,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.done &&
          snapshot.data?.repository != null) {
        return ParticipantApp(repository: snapshot.requireData.repository!);
      }
      final error = snapshot.connectionState == ConnectionState.done
          ? snapshot.data?.error
          : null;
      return MaterialApp(
        theme: rallyTheme(),
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: error == null
                      ? const CircularProgressIndicator()
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'We couldn’t start sign-in',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Please retry. If this continues, share the support code below with Rally4Ever.',
                            ),
                            const SizedBox(height: 12),
                            Text(
                              error is FirebaseException
                                  ? 'Support code: ${error.plugin}/${error.code}'
                                  : 'Support code: backend-startup',
                              key: const Key('startup-support-code'),
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              key: const Key('retry-backend'),
                              onPressed: () => setState(() {
                                connection = _connect();
                              }),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
