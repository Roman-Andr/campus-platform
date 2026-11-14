import 'package:material_ui/material_ui.dart' hide Visibility;

import '../../../core/api/api_client.dart';

/// A headman's area where they may publish pinned notices.
@immutable
class PublicationScope {
  const PublicationScope({
    required this.visibility,
    this.dormitoryId,
    this.facultyId,
  });

  final Visibility visibility;
  final String? dormitoryId;
  final String? facultyId;

  @override
  bool operator ==(Object other) =>
      other is PublicationScope &&
      other.visibility == visibility &&
      other.dormitoryId == dormitoryId &&
      other.facultyId == facultyId;

  @override
  int get hashCode => Object.hash(visibility, dormitoryId, facultyId);
}

/// Every area the account may pin a notice in.
///
/// Only headmen have one, and the server checks the scope again; the client
/// uses this list to offer the choice and to hide the action from others.
List<PublicationScope> publicationScopes(UserOutput? user) {
  if (user == null) return const [];
  final scopes = <PublicationScope>[];
  for (final assignment in user.roles) {
    final role = assignment.role;
    if (role is! RoleKnown || role.value != RoleValue.headman) continue;
    final dormitoryId = assignment.dormitoryId;
    final facultyId = assignment.facultyId;
    if (dormitoryId != null) {
      scopes.add(
        PublicationScope(
          visibility: Visibility.dormitory,
          dormitoryId: dormitoryId,
        ),
      );
    } else if (facultyId != null) {
      scopes.add(
        PublicationScope(visibility: Visibility.faculty, facultyId: facultyId),
      );
    }
  }
  return scopes;
}

/// Whether the account may pin notices anywhere.
bool isHeadman(UserOutput? user) => publicationScopes(user).isNotEmpty;
