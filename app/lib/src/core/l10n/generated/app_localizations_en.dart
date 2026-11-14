// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Campus';

  @override
  String get homeWelcome => 'Welcome to Campus';

  @override
  String get homePlaceholder =>
      'Listings, events and group purchases of your community will appear here.';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsLanguageRussian => 'Русский';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsThemeSystem => 'System default';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get errorNetwork =>
      'Can\'t reach the server. Check your internet connection and try again.';

  @override
  String get errorServer =>
      'Something went wrong on the server. Please try again later.';

  @override
  String get errorRequest => 'Couldn\'t complete the action. Please try again.';

  @override
  String get errorNotFound => 'Not found: it may have been deleted.';

  @override
  String get errorValidation => 'Please check the information you entered.';

  @override
  String get errorListChanged => 'The list has changed. Please refresh it.';

  @override
  String get errorUpdateRequired =>
      'This version of the app is out of date. Please update the app.';

  @override
  String get errorUnexpected => 'Something went wrong. Please try again.';

  @override
  String get errorRetry => 'Try again';

  @override
  String get offlineBanner => 'You\'re offline';

  @override
  String get updateTitle => 'Update required';

  @override
  String get updateBody =>
      'This version of the app is no longer supported. Install the new version to continue.';

  @override
  String updateBodyVersion(String version) {
    return 'This version of the app is no longer supported. Install version $version or newer to continue.';
  }

  @override
  String get updateDownload => 'Download update';

  @override
  String get updateDownloadFailed => 'Couldn\'t open the download page.';

  @override
  String get errorRateLimited =>
      'Too many requests. Wait a little and try again.';

  @override
  String get signInTitle => 'Sign in';

  @override
  String get signInEmailIntro =>
      'Sign in with your university e-mail or a backup personal address: we will send a sign-in code to it.';

  @override
  String get signInEmailLabel => 'University or backup e-mail';

  @override
  String get signInEmailInvalid =>
      'Enter an e-mail address, e.g. ivanov@edu.hse.ru.';

  @override
  String get signInGetCode => 'Get code';

  @override
  String get signInCodeTitle => 'Code from the e-mail';

  @override
  String signInCodeSent(String email) {
    return 'We sent a code to $email. If there is no e-mail, check the spam folder.';
  }

  @override
  String get signInCodeLabel => '6-digit code';

  @override
  String get signInCodeIncomplete => 'Enter all 6 digits of the code.';

  @override
  String get signInSubmit => 'Sign in';

  @override
  String get signInResend => 'Send the code again';

  @override
  String signInResendIn(String wait) {
    return 'You can send the code again in $wait';
  }

  @override
  String get signInResent => 'A new code has been sent';

  @override
  String get signInChangeEmail => 'Change e-mail';

  @override
  String get signInNameTitle => 'Sign up';

  @override
  String get signInNameIntro =>
      'This is your first sign-in. Enter your first and last names: other students will see them.';

  @override
  String get signInFirstName => 'First name';

  @override
  String get signInLastName => 'Last name';

  @override
  String get signInNameRequired => 'Fill in this field.';

  @override
  String get signInNameInvalid =>
      'Use only letters, spaces, hyphens and apostrophes.';

  @override
  String get signInFinish => 'Sign up';

  @override
  String get authErrorDomain =>
      'This address is not a university e-mail. Sign in with an address in the university domain.';

  @override
  String get authErrorCodeInvalid =>
      'Wrong code. Check the e-mail and try again.';

  @override
  String get authErrorCodeExpired =>
      'The code has expired or was already used. Request a new code.';

  @override
  String get authErrorAttemptsExceeded =>
      'Too many wrong attempts. Request a new code.';

  @override
  String authErrorRateLimitedFor(String wait) {
    return 'Too many attempts. Try again in $wait.';
  }

  @override
  String waitSeconds(int count) {
    return '$count s';
  }

  @override
  String waitMinutes(int count) {
    return '$count min';
  }

  @override
  String get settingsAccount => 'Account';

  @override
  String get signOut => 'Sign out';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileSetupTitle => 'Your profile';

  @override
  String get profileSetupIntro =>
      'Tell us where you study and live: you will see listings of your dormitory, faculty and city.';

  @override
  String get profileEditTitle => 'Edit profile';

  @override
  String get profileCity => 'Campus city';

  @override
  String get profileDormitory => 'Dormitory';

  @override
  String get profileNoDormitory => 'I don\'t live in a dormitory';

  @override
  String get profileFaculty => 'Faculty';

  @override
  String get profileCourse => 'Year of study';

  @override
  String get profileChoose => 'Choose from the list.';

  @override
  String get profilePlaceUnavailable =>
      'This option is no longer available, choose another one.';

  @override
  String get profileContinue => 'Continue';

  @override
  String get profileSave => 'Save';

  @override
  String get profileEmail => 'E-mail';

  @override
  String get profileAccountStudent => 'Student';

  @override
  String get profileAccountEmployee => 'Employee';

  @override
  String get profileAccountFormerEmployee => 'Former employee';

  @override
  String profileCourseValue(int course) {
    return 'Year $course';
  }

  @override
  String get profileEmails => 'E-mail addresses';

  @override
  String get emailsBackupHint =>
      'The backup address is only for signing in and security notifications. It gives no rights and does not change the account type.';

  @override
  String get emailsKindCorporate => 'Corporate';

  @override
  String get emailsKindBackup => 'Backup';

  @override
  String get emailsAddCorporate => 'Add corporate address';

  @override
  String get emailsAddBackup => 'Add backup address';

  @override
  String get emailsReplaceBackup => 'Replace backup address';

  @override
  String get emailsEmailLabel => 'E-mail address';

  @override
  String get emailsGetCode => 'Get code';

  @override
  String emailsCodeSent(String email) {
    return 'We sent a code to $email.';
  }

  @override
  String get emailsConfirm => 'Confirm';

  @override
  String get emailsDelete => 'Delete';

  @override
  String get emailsCancel => 'Cancel';

  @override
  String emailsDeleteConfirm(String email) {
    return 'Delete the address $email?';
  }

  @override
  String get emailsDeleted => 'Address deleted';

  @override
  String get emailsSaved => 'Address added';

  @override
  String get emailsLastCorporateNote =>
      'The only corporate address cannot be deleted.';

  @override
  String get emailsErrorTaken =>
      'This address is already in use. Use another one.';

  @override
  String get emailsErrorCorporateDomain =>
      'Use an address in a university domain.';

  @override
  String get emailsErrorBackupDomain =>
      'A backup address must not be in a university domain.';

  @override
  String emailsErrorRateLimitedFor(String wait) {
    return 'Too many requests. Try again in $wait.';
  }

  @override
  String get listingsCity => 'City';

  @override
  String get listingsEmpty => 'Nothing here yet';

  @override
  String get listingsMore => 'Load more';

  @override
  String get listingsFirst => 'First page';

  @override
  String get listingDetails => 'Listing';

  @override
  String listingAuthor(String name) {
    return 'Author: $name';
  }

  @override
  String get listingReserve => 'Reserve';

  @override
  String get listingCreate => 'Give away an item';

  @override
  String get listingTitle => 'Title';

  @override
  String get listingDescription => 'Description';

  @override
  String get listingScope => 'Visibility area';

  @override
  String get listingAudience => 'Audience';

  @override
  String get listingStudents => 'Students';

  @override
  String get listingCommunity => 'Community';

  @override
  String get listingPublish => 'Publish';

  @override
  String get listingsMine => 'My listings and participation';

  @override
  String get listingsOwn => 'My listings';

  @override
  String get listingsReservations => 'My participation';

  @override
  String get listingIncoming => 'Incoming requests';

  @override
  String get feedPinned => 'Pinned';

  @override
  String feedPinnedUntil(String date) {
    return 'Pinned until $date';
  }

  @override
  String get feedFilterAllKinds => 'All types';

  @override
  String get feedFilterAllCategories => 'All categories';

  @override
  String get feedFilterAllDormitories => 'All dormitories';

  @override
  String get feedFiltersReset => 'Reset filters';

  @override
  String get feedCreatePublication => 'Post a notice';

  @override
  String get feedEditPublication => 'Edit notice';

  @override
  String get feedPublicationScope => 'Publish in';

  @override
  String get feedPinUntil => 'Pinned until';

  @override
  String get feedPinInFuture => 'Choose a future date and time.';

  @override
  String get feedNoScope => 'You have no area to publish in.';

  @override
  String get feedUnpin => 'Unpin';

  @override
  String get listingKindPublication => 'Notice';

  @override
  String get reservationPending => 'Pending';

  @override
  String get reservationAccepted => 'Accepted';

  @override
  String get reservationRejected => 'Rejected';

  @override
  String get reservationCancelled => 'Cancelled';

  @override
  String get reservationAccept => 'Accept';

  @override
  String get reservationReject => 'Reject';

  @override
  String get listingActive => 'Available';

  @override
  String get listingBusy => 'Reserved';

  @override
  String get listingExpired => 'Expired';

  @override
  String get listingConflict =>
      'This item is already reserved or no longer available. Refresh the listing.';

  @override
  String get listingForbidden => 'This action is unavailable for your account.';

  @override
  String get listingCategory => 'Category';

  @override
  String get listingCategoriesEmpty =>
      'Categories are unavailable. Please try again later.';

  @override
  String get listingDraft => 'Draft';

  @override
  String get listingCompleted => 'Completed';

  @override
  String get listingHidden => 'Hidden';

  @override
  String get reservationNoShow => 'No show';

  @override
  String get listingStatusUnknown => 'Status unavailable';

  @override
  String cityTimeZone(String time, String city, String offset) {
    return '$time, $city, $offset';
  }

  @override
  String cityDateTimeHelp(String city) {
    return 'Date and time: $city';
  }

  @override
  String get chooseCityDateTime => 'Choose date and time';

  @override
  String get cityTimeDoesNotExist =>
      'This time does not exist in the city time zone. Choose another time.';

  @override
  String get consentDocuments => 'Consents and documents';

  @override
  String get consentRules => 'Community rules';

  @override
  String get consentPrivacy => 'Privacy policy';

  @override
  String get consentProcessing => 'Personal data processing consent';

  @override
  String get consentCrossBorder => 'Cross-border data transfer';

  @override
  String get consentAcceptRequired =>
      'I accept the community rules, privacy policy and personal data processing consent (required).';

  @override
  String get consentCrossBorderOptional =>
      'I consent to cross-border data transfer (optional).';

  @override
  String get consentCrossBorderEffects =>
      'Enables full push notification text, the Telegram bot and AI features.';

  @override
  String get consentUpdateTitle => 'Updated documents';

  @override
  String get consentUpdateIntro =>
      'Read and accept the current document versions to continue.';

  @override
  String get consentContinue => 'Accept and continue';

  @override
  String get consentClose => 'Close';

  @override
  String get consentCancel => 'Cancel';

  @override
  String get consentRevoke => 'Revoke consent';

  @override
  String get consentRevokeTitle => 'Revoke data transfer consent?';

  @override
  String get consentRevokeEffects =>
      'Push notifications will contain no names or message text. The Telegram bot and AI features will be disabled.';

  @override
  String get devicesTitle => 'Devices';

  @override
  String get devicesCurrent => 'This device';

  @override
  String get devicesUnknown => 'Unnamed device';

  @override
  String get devicesSignOutAll => 'Sign out of all devices';

  @override
  String get devicesConfirmAll =>
      'Sign out of all devices, including this one?';

  @override
  String devicesConfirmOne(String device) {
    return 'Sign out of $device?';
  }

  @override
  String get devicesCancel => 'Cancel';

  @override
  String devicesSignedIn(String time) {
    return 'Signed in: $time';
  }

  @override
  String devicesLastActive(String time) {
    return 'Last active: $time';
  }

  @override
  String get devicesEmpty => 'No active sessions';

  @override
  String devicesPlatform(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'android': 'Android',
      'web': 'Web browser',
      'desktop': 'Desktop',
      'telegram': 'Telegram',
      'admin': 'Admin panel',
      'other': 'Other platform',
    });
    return '$_temp0';
  }

  @override
  String photoCount(int count, int limit) {
    return 'Photos: $count of $limit';
  }

  @override
  String get photoChoose => 'Choose photos';

  @override
  String get photoTake => 'Take a photo';

  @override
  String photoUploading(int percent) {
    return 'Uploading: $percent%';
  }

  @override
  String get photoProcessing => 'Processing…';

  @override
  String photoRejected(String reason) {
    return 'Rejected: $reason';
  }

  @override
  String photoRejectedTooLarge(int megabytes) {
    return 'the file is larger than $megabytes MB';
  }

  @override
  String get photoRejectedUnsupported =>
      'unsupported format, use JPEG, PNG, WebP or HEIC';

  @override
  String get photoRejectedTooManyPixels => 'the resolution is too high';

  @override
  String get photoRejectedInvalidImage => 'the file is damaged or not an image';

  @override
  String get photoRejectedOther => 'the photo can\'t be used';

  @override
  String get photoRemove => 'Remove photo';

  @override
  String get photoMoveEarlier => 'Move earlier';

  @override
  String photoLimit(int limit) {
    return 'You can add up to $limit photos';
  }

  @override
  String photoTooLarge(String name, int megabytes) {
    return '$name: the file is larger than $megabytes MB';
  }

  @override
  String get photoWait => 'Wait until the photos finish uploading';

  @override
  String photoOf(int index, int count) {
    return 'Photo $index of $count';
  }

  @override
  String get listingSaveDraft => 'Save draft';

  @override
  String get listingSaveChanges => 'Save changes';

  @override
  String get listingEditDraft => 'Edit draft';

  @override
  String get listingRepublish => 'Publish again';

  @override
  String get listingExtend => 'Extend listing';

  @override
  String get listingsArchive => 'Archive';

  @override
  String get reservationCancel => 'Cancel request or reservation';

  @override
  String get reservationRejectedExpired => 'The listing expired.';

  @override
  String get reservationRejectedClosed => 'The author closed the listing.';

  @override
  String get reservationRejectedTimeout =>
      'The author did not respond in time.';

  @override
  String get reservationRejectedAuthor => 'The author rejected the request.';

  @override
  String get reservationRejectedOther => 'The request was rejected.';

  @override
  String listingHiddenReason(String reason) {
    return 'Hidden: $reason';
  }

  @override
  String listingRateLimitedFor(int seconds) {
    return 'Too many requests. Try again in $seconds seconds.';
  }

  @override
  String get listingVersionConflict =>
      'The listing changed. Reopen it before editing.';

  @override
  String get listingUnavailable =>
      'The listing is unavailable. It may have been removed or access has changed.';

  @override
  String get listingTransitionConflict =>
      'This action is unavailable in the current status. Refresh the listing.';

  @override
  String get listingExtended => 'The listing has been extended.';

  @override
  String get mySectionDrafts => 'Drafts';

  @override
  String get mySectionActive => 'Active';

  @override
  String get mySectionBusy => 'Reserved';

  @override
  String get listingKindGiveaway => 'Giveaway';

  @override
  String get favoritesTitle => 'Favorites';

  @override
  String get favoritesEmpty => 'No favorites yet';

  @override
  String get favoriteAdd => 'Add to favorites';

  @override
  String get favoriteRemove => 'Remove from favorites';

  @override
  String get favoriteUnavailable => 'Listing unavailable';

  @override
  String get savedCopy => 'Offline: showing saved data';

  @override
  String participationStage(String stage) {
    return 'Stage: $stage';
  }

  @override
  String get timelineTitle => 'Interaction history';

  @override
  String get timelineOpen => 'History';

  @override
  String get timelineEmpty => 'No events yet';

  @override
  String get timelineForbidden =>
      'Only the listing author and the participant can see this history.';

  @override
  String get timelineSystem => 'System';

  @override
  String get timelineYou => 'You';

  @override
  String get timelineParticipant => 'Participant';

  @override
  String get timelineRequested => 'Request sent';

  @override
  String get timelineTransition => 'Status changed';

  @override
  String get timelineAutoRejected => 'Request rejected automatically';

  @override
  String get timelineStageChanged => 'Stage changed';

  @override
  String get timelineOther => 'Action';

  @override
  String timelineStatusChange(String from, String to) {
    return '$from → $to';
  }

  @override
  String timelineReason(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get timelineReasonHidden => 'The listing was hidden by moderation.';

  @override
  String get timelineViaAssistant => 'Via assistant';

  @override
  String get timelineOfflineQr => 'Offline QR';

  @override
  String get profilePhoto => 'Profile photo';

  @override
  String get profilePhotoChoose => 'Choose a photo';

  @override
  String get profilePhotoReplace => 'Change photo';

  @override
  String get profilePhotoCamera => 'Take a photo';

  @override
  String get profilePhotoRemove => 'Remove photo';

  @override
  String get profilePhotoUploading => 'Uploading the photo…';

  @override
  String get profilePhotoProcessing => 'Checking the photo…';

  @override
  String profilePhotoTooLarge(int megabytes) {
    return 'The file is larger than $megabytes MB, choose a smaller photo.';
  }

  @override
  String get profilePhotoRejected =>
      'This doesn\'t look like a photo: choose a JPEG, PNG, WebP or HEIC image.';

  @override
  String get profilePhotoTimeout =>
      'Checking the photo takes too long. Please try again.';

  @override
  String get profileSkills => 'Skills';

  @override
  String get profileSkillsCan => 'I can';

  @override
  String get profileSkillsWants => 'I want to learn';

  @override
  String get profileSkillsNone => 'None yet';

  @override
  String get profileSkillsEdit => 'Edit skills';

  @override
  String get profileSkillsAdd => 'Add';

  @override
  String get profileSkillsSearch => 'Find a skill';

  @override
  String get profileSkillsNotFound => 'Nothing found';

  @override
  String profileSkillRemove(String name) {
    return 'Remove “$name”';
  }

  @override
  String get profileSkillsUnavailable =>
      'Some skills are no longer available: remove them and save again.';

  @override
  String get profileNameChange => 'Change name';

  @override
  String get profileNameRule =>
      'Name changes are logged, and the next one won\'t be available right away. Use your real first and last names.';

  @override
  String profileNameNextChange(String date) {
    return 'Next name change: not before $date';
  }

  @override
  String profileNameTooSoon(String date) {
    return 'The name was changed recently. Next change: not before $date.';
  }

  @override
  String get profileSetupPhotoIntro =>
      'Add a photo so that people recognize you when you meet. You can skip this step.';

  @override
  String get profileSetupSkillsIntro =>
      'Mark what you can do and what you want to learn: it helps to find someone to swap skills with. You can skip this step.';

  @override
  String get profileSkip => 'Skip';

  @override
  String get profileDone => 'Done';
}
