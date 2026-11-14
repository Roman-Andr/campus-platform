import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_session.dart';

part 'skills.g.dart';

/// Skills of the signed-in user's profile: "can" and "wants to learn",
/// tags of the common reference (ТЗ п. 5.1.1, модуль 2, п. 1).
@Riverpod(keepAlive: true)
class MySkills extends _$MySkills {
  @override
  Future<SkillsOutput?> build() async {
    final status = ref.watch(authStatusProvider.select((value) => value.value));
    if (status != AuthenticationStatus.authenticated) return null;
    return ref.read(campusApiProvider).profile.getMySkills();
  }

  /// Replaces both lists; throws when the server rejects them.
  Future<void> save({
    required Iterable<SkillTagOutput> can,
    required Iterable<SkillTagOutput> wants,
  }) async {
    final skills = await ref
        .read(campusApiProvider)
        .profile
        .setMySkills(
          body: SkillsInput(
            can: [for (final tag in can) tag.id],
            wants: [for (final tag in wants) tag.id],
          ),
        );
    state = AsyncData(skills);
  }
}

/// Skill tags whose name in the interface language starts with [query].
@riverpod
Future<List<SkillTagOutput>> skillTagSearch(Ref ref, String query) async =>
    (await ref
            .watch(campusApiProvider)
            .skills
            .listSkillTags(q: query.trim().isEmpty ? null : query.trim()))
        .items;
