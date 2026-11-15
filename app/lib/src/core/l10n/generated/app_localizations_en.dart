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
  String get errorForbidden => 'You don\'t have access to this action.';

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
  String get photoPreview => 'Photo preview';

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
  String get meetingTitle => 'Meeting';

  @override
  String get meetingNotScheduled => 'No meeting scheduled yet';

  @override
  String get meetingCurrent => 'Current meeting';

  @override
  String get meetingYourProposal => 'Your proposal';

  @override
  String get meetingNewProposal => 'New proposal';

  @override
  String meetingPlace(String place) {
    return 'Place: $place';
  }

  @override
  String get meetingAwaitingAnswer =>
      'Waiting for the other participant to respond';

  @override
  String get meetingAwaitingYourAnswer => 'Waiting for your response';

  @override
  String get meetingOpen => 'Open meeting';

  @override
  String get meetingAccept => 'Confirm';

  @override
  String get meetingReschedule => 'Reschedule';

  @override
  String get meetingSuggest => 'Suggest a time and place';

  @override
  String get meetingChangeProposal => 'Change proposal';

  @override
  String get meetingFormTitle => 'Time and place';

  @override
  String get meetingPlaceLabel => 'Meeting place';

  @override
  String get meetingPlaceRequired => 'Enter a meeting place.';

  @override
  String get meetingTimeRequired => 'Choose a meeting time.';

  @override
  String get meetingTimePast => 'The time can\'t be in the past.';

  @override
  String get meetingSaveProposal => 'Send proposal';

  @override
  String get meetingDismiss => 'Cancel';

  @override
  String get meetingStale =>
      'The proposal has changed. Check the new time and place.';

  @override
  String get meetingStateConflict =>
      'A meeting can only be scheduled for an accepted interaction.';

  @override
  String get meetingTimeInvalid => 'Choose a time in the future.';

  @override
  String get meetingPlaceInvalid => 'Check the meeting place.';

  @override
  String get meetingUnavailable => 'The meeting is unavailable.';

  @override
  String get meetingConfirmed => 'Meeting confirmed.';

  @override
  String get meetingProposalSent => 'Proposal sent.';

  @override
  String get meetingCancelInteraction => 'Cancel interaction';

  @override
  String get meetingCancelTitle => 'Cancel the interaction?';

  @override
  String get meetingCancelBody =>
      'The meeting and its reminders will be cancelled.';

  @override
  String get meetingCancelKeep => 'Keep';

  @override
  String get meetingCancelConfirm => 'Cancel';

  @override
  String get noMeetingTitle => 'Without a meeting';

  @override
  String get noMeetingBothConfirm =>
      'Both participants confirm that the interaction took place without a meeting.';

  @override
  String get noMeetingOpen => 'Open confirmation';

  @override
  String get noMeetingIntro =>
      'Confirm that the interaction took place without a meeting. It is completed after both participants agree.';

  @override
  String get noMeetingConfirm => 'Confirm without a meeting';

  @override
  String get noMeetingYourConsent => 'Your consent';

  @override
  String get noMeetingOtherConsent => 'The other participant\'s consent';

  @override
  String noMeetingConfirmedAt(String time) {
    return 'Confirmed $time';
  }

  @override
  String get noMeetingNotConfirmed => 'Not yet';

  @override
  String get noMeetingWaiting => 'Waiting for the other participant.';

  @override
  String get noMeetingRefresh => 'Refresh';

  @override
  String get noMeetingCompletedStatus => 'Completed without a meeting';

  @override
  String get noMeetingCompleted =>
      'The interaction is completed without a meeting.';

  @override
  String noMeetingAgreedAt(String time) {
    return 'Agreed time: $time';
  }

  @override
  String noMeetingCompletedAt(String time) {
    return 'Completed: $time';
  }

  @override
  String get noMeetingSent => 'Consent sent.';

  @override
  String get noMeetingUnavailable =>
      'This interaction cannot be completed without a meeting.';

  @override
  String get noMeetingForbidden => 'You cannot confirm this interaction.';

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

  @override
  String get feedSearch => 'Search listings';

  @override
  String get feedSearchClear => 'Clear search';

  @override
  String get feedSearchEmpty => 'No matching listings';

  @override
  String get listingsQueue => 'Queues and offers';

  @override
  String get waitlistJoin => 'Join queue';

  @override
  String get waitlistLeave => 'Leave queue';

  @override
  String waitlistPosition(int position) {
    return 'Your place in the queue: $position';
  }

  @override
  String get waitlistRefresh => 'Refresh position';

  @override
  String get waitlistWaiting => 'Waiting in the queue';

  @override
  String get waitlistEmpty =>
      'You are not in any queue and have no place offers';

  @override
  String get waitlistSection => 'Your queues';

  @override
  String get waitlistFree =>
      'A place is already free: reserve the item instead.';

  @override
  String get waitlistDuplicate => 'You are already in this queue.';

  @override
  String get waitlistParticipating =>
      'You already participate in this listing.';

  @override
  String get waitlistUnavailable => 'This listing has no queue.';

  @override
  String get waitlistOfferPending =>
      'The place is offered to another participant.';

  @override
  String get waitlistOfferMissing => 'This place offer is no longer active.';

  @override
  String get waitlistOfferExpired => 'The place offer has expired.';

  @override
  String get offerSection => 'Place offers';

  @override
  String get offerTitle => 'Place offer';

  @override
  String get offerOffered => 'A place is offered to you';

  @override
  String offerCountdown(String time) {
    return 'Offer expires in $time';
  }

  @override
  String get offerExpired => 'The offer has expired.';

  @override
  String get offerAccept => 'Confirm';

  @override
  String get offerDecline => 'Decline';

  @override
  String get offerConfirmed =>
      'Offer confirmed. The application is waiting for the author.';

  @override
  String get offerDeclined => 'Offer declined.';

  @override
  String get offerUnavailable => 'This offer is no longer available.';

  @override
  String get offerOpenListing => 'Open listing';

  @override
  String get realtimeConnecting => 'Connecting to realtime…';

  @override
  String get realtimeReconnecting => 'Realtime connection lost. Reconnecting…';

  @override
  String get realtimeConnected => 'Realtime connected';

  @override
  String get realtimeOffline => 'Realtime is offline';

  @override
  String get realtimeUpdating => 'Updating data…';

  @override
  String get realtimeSessionEnded => 'Your session has ended. Sign in again.';

  @override
  String get realtimeChannelForbidden =>
      'You no longer have access to this channel.';

  @override
  String get realtimeChannelInvalid => 'This channel is unavailable.';

  @override
  String get realtimeUnavailable =>
      'Realtime is temporarily unavailable. We will try again.';

  @override
  String get realtimeHistoryLost =>
      'Some events are no longer available; the data has been reloaded.';

  @override
  String get realtimeNetworkLost => 'No connection. Reconnecting…';

  @override
  String get realtimeError => 'Could not update realtime. Try again later.';

  @override
  String realtimeLastEvent(String time) {
    return 'Last event: $time';
  }

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsEmpty => 'No notifications yet';

  @override
  String get notificationsMarkAllRead => 'Mark all as read';

  @override
  String get notificationsNoScreen =>
      'There is no screen for this notification in the app yet.';

  @override
  String get listingKindEvent => 'Event';

  @override
  String get eventCreate => 'New event';

  @override
  String get eventEdit => 'Edit event';

  @override
  String get eventStartsAt => 'Starts at';

  @override
  String get eventEndsAt => 'Ends at';

  @override
  String get eventLocation => 'Location';

  @override
  String eventLocationValue(String location) {
    return 'Location: $location';
  }

  @override
  String get eventCapacity => 'Seat limit';

  @override
  String eventSeatsLeft(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Seats left: $count',
      one: 'Seats left: $count',
      zero: 'No seats left',
    );
    return '$_temp0';
  }

  @override
  String get eventNoSeats => 'No seats left';

  @override
  String get eventSignup => 'Sign up';

  @override
  String get eventRegistered => 'You are registered';

  @override
  String get eventQueued => 'You are in the queue';

  @override
  String get eventJoinQueue => 'Join the queue';

  @override
  String get eventCancelSignup => 'Cancel signup';

  @override
  String get eventParticipants => 'Registered participants';

  @override
  String get eventParticipantRegistered => 'Registered';

  @override
  String get eventParticipantsEmpty => 'No one has signed up yet';

  @override
  String get eventSignupClosed => 'Signup closed';

  @override
  String get eventTimeInvalid =>
      'The event must start in the future and end after its start.';

  @override
  String eventTimeRange(String start, String end) {
    return '$start — $end';
  }

  @override
  String get eventCapacityInvalid => 'The seat limit must be at least 1.';

  @override
  String eventCapacityBelowRegistered(int registered) {
    return 'The seat limit cannot be lower than the number of registered participants: $registered.';
  }

  @override
  String get eventCapacityConflict =>
      'The seat limit cannot be lower than the number of registered participants.';

  @override
  String get moreActions => 'More';

  @override
  String get listingKindSkill => 'Skill';

  @override
  String get skillDirection => 'Direction';

  @override
  String get skillCreateTitle => 'New skill listing';

  @override
  String get skillDirectionTeach => 'I can teach';

  @override
  String get skillDirectionLearn => 'I want to learn';

  @override
  String get skillDirectionRequired =>
      'Choose what you can teach or want to learn.';

  @override
  String get skillPublished => 'The skill listing has been published.';

  @override
  String get lessonOptionsTitle => 'Time options';

  @override
  String get lessonPropose => 'Offer a lesson';

  @override
  String get lessonProposeTitle => 'Lesson time';

  @override
  String get lessonRepeat => 'Another lesson';

  @override
  String lessonRepeatTitle(String name) {
    return 'Another lesson with $name';
  }

  @override
  String lessonCounterpart(String name) {
    return 'With: $name';
  }

  @override
  String lessonOptionsHint(int min, int max) {
    return 'Choose $min to $max time options.';
  }

  @override
  String lessonOptionNumber(int number) {
    return 'Option $number';
  }

  @override
  String get lessonAddOption => 'Add a time option';

  @override
  String get lessonRemoveOption => 'Remove option';

  @override
  String lessonOptionsTooFew(int min) {
    return 'Add at least $min time options.';
  }

  @override
  String lessonOptionsTooMany(int max) {
    return 'A lesson can have at most $max time options.';
  }

  @override
  String lessonOptionsInvalid(int min, int max) {
    return 'A lesson needs $min to $max time options in the future.';
  }

  @override
  String get lessonConflict =>
      'The lesson has already been answered. Refresh the listing.';

  @override
  String get lessonForbidden =>
      'Only the author and the participant can answer the lesson.';

  @override
  String get lessonOnline => 'Online';

  @override
  String get lessonOffline => 'In person';

  @override
  String get lessonOnlineSwitch => 'Online meeting';

  @override
  String get lessonPlaceLabel => 'Lesson place';

  @override
  String get lessonOptionProposed => 'Awaiting response';

  @override
  String get lessonOptionSelected => 'Selected';

  @override
  String get lessonOptionDeclined => 'Declined';

  @override
  String get lessonOptionByYou => 'Your option';

  @override
  String get lessonOptionByParticipant => 'Participant\'s option';

  @override
  String get lessonOptionByAuthor => 'Author\'s option';

  @override
  String get lessonAccept => 'Choose this time';

  @override
  String get lessonCounter => 'Offer another time';

  @override
  String get lessonCounterTitle => 'Another time';

  @override
  String get lessonSend => 'Send';

  @override
  String get lessonSent => 'Lesson offered.';

  @override
  String get lessonCounterSent => 'Another time offered.';

  @override
  String get lessonAccepted => 'Lesson scheduled.';

  @override
  String get lessonRepeated => 'Another lesson offered.';

  @override
  String get lessonNoOptions => 'There are no time options.';

  @override
  String get lessonAwaitingAnswer => 'Waiting for the author';

  @override
  String get lessonAwaitingYourAnswer => 'Waiting for your response';

  @override
  String get lessonAwaitingParticipant => 'Waiting for the participant';

  @override
  String lessonResponseDue(String time) {
    return 'Answer by $time';
  }

  @override
  String get meetingOnline => 'Online meeting';

  @override
  String get listingKindHelp => 'Help request';

  @override
  String get feedCreateHelp => 'Ask for help';

  @override
  String get helpCreateTitle => 'New help request';

  @override
  String get helpPublished => 'The help request has been published.';

  @override
  String get helpDeadline => 'Relevant until';

  @override
  String get helpDeadlinePast => 'Choose a future deadline.';

  @override
  String get helpDeadlineInvalid =>
      'The deadline must be in the future and no later than the listing lifetime.';

  @override
  String get helpRespond => 'Respond';

  @override
  String get helpResponded => 'Response sent.';

  @override
  String get helpApplicationPending =>
      'Your response is waiting for the author.';

  @override
  String get helpReserve => 'Reserve';

  @override
  String get helpReserveNotice =>
      'An executor is already selected; you remain in the reserve.';

  @override
  String get helpExecutor => 'Executor';

  @override
  String get helpYouAreExecutor => 'You are the executor.';

  @override
  String get helpSelectExecutor => 'Choose executor';

  @override
  String get helpSelected => 'The executor has been selected.';

  @override
  String get helpConflict =>
      'The help request has already changed. Refresh the listing.';

  @override
  String get helpForbidden => 'You cannot act on this help request.';

  @override
  String get helpIncoming => 'Responses';

  @override
  String helpDeadlineHint(int days) {
    return 'Not later than the listing lifetime ($days days).';
  }

  @override
  String helpDeadlineTooLate(int days) {
    return 'The deadline cannot be later than $days days.';
  }

  @override
  String helpRelevantUntil(String date) {
    return 'Relevant until $date';
  }
}
