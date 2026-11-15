import 'package:intl/intl.dart';

import '../../../core/api/api_failure.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/api/generated/campus_api.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../domain/privacy.dart';

/// A message for a failed privacy request.
///
/// The server detail is never shown; in particular, a block is never
/// explained as a reason to the unavailable recipient.
String privacyFailureMessage(AppLocalizations l10n, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(status: 403) => l10n.errorForbidden,
      ProblemFailure(status: 404) => l10n.errorNotFound,
      _ => apiFailureMessage(l10n, error),
    };

/// The short name of [policy], used on the profile and in the radio list.
String messagePolicyLabel(AppLocalizations l10n, MessagePolicy policy) =>
    switch (policy) {
      MessagePolicy.all => l10n.messagePolicyAll,
      MessagePolicy.related => l10n.messagePolicyRelated,
    };

/// The explanation of [policy] under its radio option.
String messagePolicyHint(AppLocalizations l10n, MessagePolicy policy) =>
    switch (policy) {
      MessagePolicy.all => l10n.messagePolicyAllHint,
      MessagePolicy.related => l10n.messagePolicyRelatedHint,
    };

/// The account type of a blocked user.
String blockedAccountLabel(
  AppLocalizations l10n,
  BlockedUserOutputAccountType type,
) => switch (type.toJson()) {
  'employee' => l10n.profileAccountEmployee,
  'former_employee' => l10n.profileAccountFormerEmployee,
  _ => l10n.profileAccountStudent,
};

/// The displayed name of a blocked user.
String blockedUserName(BlockedUserOutput user) =>
    '${user.firstName} ${user.lastName}'.trim();

/// When [user] was blocked, in the city zone of the signed-in user (ТЗ #44).
///
/// Without a filled city the device zone is the best available and needs no
/// city annotation.
String blockedAtText(
  DateTime instant,
  UserOutput? signedIn,
  AppLocalizations l10n,
) {
  final timezone = signedIn?.cityTimezone;
  if (timezone == null) {
    return DateFormat.yMd(l10n.localeName).add_Hm().format(instant.toLocal());
  }
  return formatCityTime(
    instant,
    timezone: timezone,
    city: timezone,
    l10n: l10n,
    includeDate: true,
  );
}
