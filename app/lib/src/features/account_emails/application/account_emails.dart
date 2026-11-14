import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/api/api_client.dart';
import '../../../core/auth/auth_session.dart';
import '../../profile/application/my_profile.dart';

part 'account_emails.g.dart';

/// Verified e-mail addresses of the signed-in account.
@riverpod
Future<List<AddressOutput>> accountEmails(Ref ref) async {
  final status = ref.watch(authStatusProvider).value;
  if (status != AuthenticationStatus.authenticated) return const [];
  return ref.watch(campusApiProvider).accountEmails.listAddresses();
}

/// Changing the account's e-mail addresses.
///
/// A new address appears in the list only after the server accepts its
/// code. Corporate addresses change the account type, so the profile is
/// reloaded after adding or deleting one.
@Riverpod(keepAlive: true)
class AccountEmailActions extends _$AccountEmailActions {
  @override
  void build() {}

  Future<void> requestCode({
    required String email,
    required AddressInputKind kind,
  }) async {
    await ref
        .read(campusApiProvider)
        .accountEmails
        .requestAddressCode(
          body: AddressInput(email: email, kind: kind),
        );
  }

  Future<void> confirm({
    required String email,
    required AddressInputKind kind,
    required String code,
  }) async {
    await ref
        .read(campusApiProvider)
        .accountEmails
        .confirmAddress(
          body: ConfirmAddressInput(
            email: email,
            kind: _confirmKindOf(kind),
            code: code,
          ),
        );
    ref.invalidate(accountEmailsProvider);
    if (kind == AddressInputKind.corporate) ref.invalidate(myProfileProvider);
  }

  Future<void> delete(AddressOutput address) async {
    await ref
        .read(campusApiProvider)
        .accountEmails
        .deleteAddress(addressId: address.id);
    ref.invalidate(accountEmailsProvider);
    if (address.kind == AddressOutputKind.corporate) {
      ref.invalidate(myProfileProvider);
    }
  }
}

/// Whether the interface may offer deleting [address].
///
/// The server rejects deleting the last corporate address: it decides the
/// account type and must stay as a way to sign in.
bool canDeleteAddress(
  AddressOutput address,
  Iterable<AddressOutput> addresses,
) =>
    address.kind != AddressOutputKind.corporate ||
    addresses.where((row) => row.kind == AddressOutputKind.corporate).length >
        1;

ConfirmAddressInputKind _confirmKindOf(AddressInputKind kind) =>
    kind.toJson() == AddressInputKind.backup.toJson()
    ? ConfirmAddressInputKind.backup
    : ConfirmAddressInputKind.corporate;
