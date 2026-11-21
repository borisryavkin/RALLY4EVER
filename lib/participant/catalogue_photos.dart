import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'catalogue.dart';
import 'repository.dart';
import 'theme.dart';

Uint8List resizeCataloguePhoto(Uint8List bytes) {
  if (bytes.length > 20 * 1024 * 1024) {
    throw const FormatException('Choose a photo under 20 MB.');
  }
  img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    throw const FormatException('Choose a JPEG, PNG or WebP image.');
  }
  if (decoded == null) {
    throw const FormatException('Choose a JPEG, PNG or WebP image.');
  }
  if (decoded.width * decoded.height > 50000000) {
    throw const FormatException('Choose a photo under 50 megapixels.');
  }
  final image = img.bakeOrientation(decoded);
  final scale = math.min(1.0, 1600 / math.max(image.width, image.height));
  final resized = scale < 1
      ? img.copyResize(
          image,
          width: (image.width * scale).round(),
          height: (image.height * scale).round(),
        )
      : image;
  final jpeg = Uint8List.fromList(img.encodeJpg(resized, quality: 80));
  if (jpeg.length > 5 * 1024 * 1024) {
    throw const FormatException('Compressed photo must be under 5 MB.');
  }
  return jpeg;
}

class CataloguePhotoControl extends StatefulWidget {
  const CataloguePhotoControl({
    super.key,
    required this.repository,
    required this.record,
    required this.kind,
    this.onSaved,
    this.onBusy,
  });
  final ParticipantRepository repository;
  final Record record;
  final String kind;
  final VoidCallback? onSaved;
  final ValueChanged<bool>? onBusy;
  @override
  State<CataloguePhotoControl> createState() => _CataloguePhotoControlState();
}

class _CataloguePhotoControlState extends State<CataloguePhotoControl> {
  bool busy = false;
  double progress = 0;
  String? error;
  Future<void> save(String mode, [ImageSource? source]) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      progress = 0;
    });
    widget.onBusy?.call(true);
    try {
      var url = '';
      if (source != null) {
        final file = await ImagePicker().pickImage(source: source);
        if (file == null) return;
        final bytes = resizeCataloguePhoto(await file.readAsBytes());
        url = await widget.repository.uploadCataloguePhoto(
          widget.kind,
          widget.record['id'] as String,
          bytes,
          (value) {
            if (mounted) setState(() => progress = value);
          },
        );
      }
      final result = await widget.repository.call('adminSetPhoto', {
        'kind': widget.kind,
        'id': widget.record['id'],
        'revision': widget.record['revision'] ?? 0,
        'photoUrl': url,
        'mode': mode,
      });
      widget.record['photoUrl'] = url;
      widget.record['photoMode'] = mode;
      widget.record['revision'] =
          result['revision'] ?? (widget.record['revision'] ?? 0) + 1;
      widget.onSaved?.call();
    } catch (e) {
      if (mounted) setState(() => error = 'Photo was not saved: $e');
    } finally {
      if (mounted) setState(() => busy = false);
      widget.onBusy?.call(false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Photo', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      CataloguePhoto(record: widget.record, repository: widget.repository),
      if (busy) ...[
        LinearProgressIndicator(
          value: progress > 0 && progress < 1 ? progress : null,
        ),
        Text(
          progress < 1
              ? 'Uploading ${(progress * 100).round()}%'
              : 'Saving photo…',
        ),
      ],
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final source = await showModalBottomSheet<ImageSource>(
                      context: context,
                      builder: (context) => SafeArea(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              leading: const Icon(Icons.photo_library_outlined),
                              title: const Text('Choose from library'),
                              onTap: () =>
                                  Navigator.pop(context, ImageSource.gallery),
                            ),
                            ListTile(
                              leading: const Icon(Icons.camera_alt_outlined),
                              title: const Text('Take photo'),
                              onTap: () =>
                                  Navigator.pop(context, ImageSource.camera),
                            ),
                          ],
                        ),
                      ),
                    );
                    if (source != null) await save('override', source);
                  },
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Change photo'),
          ),
          if (widget.kind == 'session')
            TextButton(
              onPressed: busy ? null : () => save('venue'),
              child: const Text('Use venue photo'),
            ),
          TextButton(
            onPressed: busy ? null : () => save('none'),
            child: const Text('Remove photo'),
          ),
        ],
      ),
      if (error != null) Text(error!, style: const TextStyle(color: coral)),
      const SizedBox(height: 20),
    ],
  );
}

class VenueManagementPanel extends StatelessWidget {
  const VenueManagementPanel({super.key, required this.repository});
  final ParticipantRepository repository;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: repository,
    builder: (context, _) => Column(
      children: [
        for (final venue in repository.venues)
          ListTile(
            title: Text('${venue['name']}'),
            subtitle: Text('${venue['suburb'] ?? ''}'),
            trailing: const Icon(Icons.edit_outlined),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Edit venue photo')),
                  body: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        '${venue['name']}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const Text(
                        'Applies to sessions using this venue photo. Session overrides stay unchanged.',
                      ),
                      CataloguePhotoControl(
                        repository: repository,
                        record: venue,
                        kind: 'venue',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (repository.venues.isEmpty)
          const Text('No venues saved yet. Add a venue in the web admin.'),
      ],
    ),
  );
}
