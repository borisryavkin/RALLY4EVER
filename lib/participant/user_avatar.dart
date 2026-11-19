import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'repository.dart';
import 'theme.dart';

/// The one shared avatar used everywhere the signed-in user's own identity
/// appears (Play header, Me tab, ...): the profile photo if one exists,
/// otherwise the navy initial circle, with no layout shift between states.
/// [repository] must be a live, listened-to instance (this widget reads its
/// current `profile` synchronously on every build, so it updates the moment
/// the profile document's `photoUpdatedAt` changes -- no separate stream).
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.repository,
    this.radius = 20,
    this.textStyle = const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
    ),
  });
  final ParticipantRepository repository;
  final double radius;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final initial = initialsFor(repository.profile);
    final placeholder = CircleAvatar(
      radius: radius,
      backgroundColor: navy,
      foregroundColor: Colors.white,
      child: Text(initial, style: textStyle),
    );
    if (repository.profile['photoUpdatedAt'] == null) return placeholder;
    return FutureBuilder<String?>(
      key: ValueKey(repository.profile['photoUpdatedAt']),
      future: repository.photoDownloadUrl(),
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (snapshot.connectionState != ConnectionState.done || url == null) {
          return placeholder;
        }
        return ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: radius * 2,
            height: radius * 2,
            fit: BoxFit.cover,
            placeholder: (context, url) => placeholder,
            errorWidget: (context, url, error) => placeholder,
          ),
        );
      },
    );
  }
}
