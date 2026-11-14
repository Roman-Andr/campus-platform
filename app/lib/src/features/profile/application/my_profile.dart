import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_session.dart';

part 'my_profile.g.dart';

/// The signed-in user's account and profile, as the server keeps it;
/// `null` when nobody is signed in.
///
/// Loaded from the server after every sign-in and app start, so a profile
/// filled in on another device is the same here.
@Riverpod(keepAlive: true)
class MyProfile extends _$MyProfile {
  @override
  Future<UserOutput?> build() async {
    final status = ref.watch(authStatusProvider.select((value) => value.value));
    if (status != AuthenticationStatus.authenticated) return null;
    return ref.read(campusApiProvider).profile.getMe();
  }

  /// Saves the whole profile; throws when the server rejects it.
  Future<void> save(ProfileInput profile) async {
    final user = await ref
        .read(campusApiProvider)
        .profile
        .updateProfile(body: profile);
    state = AsyncData(user);
  }
}

/// Campus cities, by name in the interface language.
@riverpod
Future<List<CityOut>> cities(Ref ref) async =>
    (await ref.watch(campusApiProvider).university.listCities()).items;

/// Dormitories of the city [cityId], by name.
@riverpod
Future<List<CityPlaceOut>> dormitories(Ref ref, String cityId) async =>
    (await ref
            .watch(campusApiProvider)
            .university
            .listDormitories(cityId: cityId))
        .items;

/// Faculties of the city [cityId], by name.
@riverpod
Future<List<CityPlaceOut>> faculties(Ref ref, String cityId) async =>
    (await ref
            .watch(campusApiProvider)
            .university
            .listFaculties(cityId: cityId))
        .items;

/// Whether accounts of [type] give a course: students do, employees not.
bool hasCourse(AccountType type) => type != AccountType.employee;
