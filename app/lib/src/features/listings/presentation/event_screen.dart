import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../../core/widgets/city_date_time_picker.dart';
import '../../profile/application/my_profile.dart';
import '../application/events.dart';
import '../application/listings.dart';
import '../domain/event.dart';
import 'listings_screens.dart';
import 'waitlist_widgets.dart';

/// Explains the event-specific conflicts of the server (Problem Details).
String eventFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.eventCapacityConflict),
      ) =>
        l.eventCapacityConflict,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.eventTimeInvalid),
      ) =>
        l.eventTimeInvalid,
      _ => listingFailureMessage(l, error),
    };

/// Creates an event, or edits its schedule, place and seat limit.
///
/// Title, description and scope are set once at creation: the server changes
/// only the schedule, location and capacity afterwards, so the form keeps the
/// remaining fields read-only.
class CreateEventScreen extends ConsumerStatefulWidget {
  const CreateEventScreen({this.initial, super.key});

  /// The event to edit; `null` when creating a new one.
  final ListingOutput? initial;

  @override
  ConsumerState<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends ConsumerState<CreateEventScreen> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();
  final location = TextEditingController();
  final capacity = TextEditingController();

  late DateTime startsAt;
  late DateTime endsAt;
  Visibility scope = Visibility.city;
  Audience audience = Audience.students;
  String? categoryId;
  String? scheduleError;

  bool get editing => widget.initial != null;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    final now = clock.now();
    title.text = item?.title ?? '';
    description.text = item?.description ?? '';
    location.text = item?.eventLocation ?? '';
    capacity.text = item?.eventCapacity?.toString() ?? '';
    startsAt = item?.eventStartsAt ?? now.add(const Duration(days: 1));
    endsAt = item?.eventEndsAt ?? startsAt.add(const Duration(hours: 2));
    if (item != null) {
      scope = item.visibility;
      audience = item.audience;
      categoryId = item.categoryId;
    }
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    location.dispose();
    capacity.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final l = context.l10n;
    if (!form.currentState!.validate()) throw const InvalidListingForm();
    final schedule = eventScheduleError(
      l,
      startsAt: startsAt,
      endsAt: endsAt,
      now: clock.now(),
    );
    if (schedule != null) {
      setState(() => scheduleError = schedule);
      throw const InvalidListingForm();
    }
    setState(() => scheduleError = null);
    final seats = int.parse(capacity.text.trim());
    final api = ref.read(campusApiProvider);
    final item = widget.initial;
    if (item != null) {
      await api.listings.editEvent(
        listingId: item.id,
        body: EventEdit(
          version: item.version,
          startsAt: startsAt,
          endsAt: endsAt,
          location: location.text.trim(),
          capacity: seats,
        ),
      );
    } else {
      await api.listings.publishEvent(
        body: EventInput(
          title: title.text.trim(),
          description: description.text.trim(),
          visibility: scope,
          audience: audience,
          categoryId: categoryId,
          startsAt: startsAt,
          endsAt: endsAt,
          location: location.text.trim(),
          capacity: seats,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    final categories = ref.watch(listingCategoriesProvider);
    final timezone = user?.cityTimezone ?? 'UTC';
    final today = tz.TZDateTime.from(clock.now(), cityLocation(timezone));
    final firstDate = DateTime(today.year, today.month, today.day);
    final lastDate = firstDate.add(const Duration(days: 365));
    final registered = editing ? eventRegisteredCount(widget.initial!) : null;
    return Scaffold(
      appBar: AppBar(title: Text(editing ? l.eventEdit : l.eventCreate)),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('event-title'),
              controller: title,
              enabled: !editing,
              decoration: InputDecoration(labelText: l.listingTitle),
              validator: (value) => value == null || value.trim().isEmpty
                  ? l.signInNameRequired
                  : null,
            ),
            TextFormField(
              key: const Key('event-description'),
              controller: description,
              enabled: !editing,
              minLines: 3,
              maxLines: null,
              decoration: InputDecoration(labelText: l.listingDescription),
              validator: (value) => value == null || value.trim().isEmpty
                  ? l.signInNameRequired
                  : null,
            ),
            if (!editing)
              categories.when(
                loading: () => const LinearProgressIndicator(),
                error: (error, _) => Column(
                  children: [
                    Text(apiFailureMessage(l, error)),
                    TextButton(
                      onPressed: () =>
                          ref.invalidate(listingCategoriesProvider),
                      child: Text(l.errorRetry),
                    ),
                  ],
                ),
                data: (items) => items.isEmpty
                    ? Text(l.listingCategoriesEmpty)
                    : DropdownButtonFormField<String>(
                        key: const Key('event-category'),
                        initialValue: items.any((item) => item.id == categoryId)
                            ? categoryId
                            : null,
                        decoration: InputDecoration(
                          labelText: l.listingCategory,
                        ),
                        items: [
                          for (final item in items)
                            DropdownMenuItem(
                              value: item.id,
                              child: Text(item.name),
                            ),
                        ],
                        validator: (value) =>
                            items.any((item) => item.id == value)
                            ? null
                            : l.profileChoose,
                        onChanged: (value) =>
                            setState(() => categoryId = value),
                      ),
              ),
            if (!editing) ...[
              DropdownButtonFormField<Visibility>(
                key: const Key('event-scope'),
                initialValue: scope,
                decoration: InputDecoration(labelText: l.listingScope),
                items: [
                  for (final value in [
                    Visibility.city,
                    if (user?.facultyId != null) Visibility.faculty,
                    if (user?.dormitoryId != null &&
                        user?.accountType == UserOutputAccountType.student)
                      Visibility.dormitory,
                  ])
                    DropdownMenuItem(
                      value: value,
                      child: Text(scopeName(l, value)),
                    ),
                ],
                onChanged: (value) => setState(() => scope = value!),
              ),
              DropdownButtonFormField<Audience>(
                key: const Key('event-audience'),
                initialValue:
                    user?.accountType == UserOutputAccountType.employee
                    ? Audience.community
                    : audience,
                decoration: InputDecoration(labelText: l.listingAudience),
                items: [
                  DropdownMenuItem(
                    value: Audience.students,
                    child: Text(l.listingStudents),
                  ),
                  DropdownMenuItem(
                    value: Audience.community,
                    child: Text(l.listingCommunity),
                  ),
                ],
                onChanged:
                    user == null ||
                        user.accountType == UserOutputAccountType.employee
                    ? null
                    : (value) => setState(() => audience = value!),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              l.eventStartsAt,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            CityDateTimePicker(
              value: startsAt,
              timezone: timezone,
              city: timezone,
              firstDate: firstDate,
              lastDate: lastDate,
              onChanged: (value) => setState(() {
                startsAt = value;
                if (!endsAt.isAfter(startsAt)) {
                  endsAt = startsAt.add(const Duration(hours: 2));
                }
                scheduleError = null;
              }),
            ),
            Text(l.eventEndsAt, style: Theme.of(context).textTheme.titleSmall),
            CityDateTimePicker(
              value: endsAt,
              timezone: timezone,
              city: timezone,
              firstDate: firstDate,
              lastDate: lastDate,
              onChanged: (value) => setState(() {
                endsAt = value;
                scheduleError = null;
              }),
            ),
            if (scheduleError != null)
              Text(scheduleError!, key: const Key('event-schedule-error')),
            TextFormField(
              key: const Key('event-location'),
              controller: location,
              decoration: InputDecoration(labelText: l.eventLocation),
              validator: (value) => value == null || value.trim().isEmpty
                  ? l.signInNameRequired
                  : null,
            ),
            TextFormField(
              key: const Key('event-capacity'),
              controller: capacity,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.eventCapacity),
              validator: (value) => eventCapacityError(
                l,
                capacity: int.tryParse(value?.trim() ?? ''),
                registered: registered,
              ),
            ),
            const SizedBox(height: 16),
            ListingAction(
              key: const Key('event-submit'),
              label: editing ? l.listingSaveChanges : l.listingPublish,
              failureMessage: eventFailureMessage,
              enabled: user != null,
              run: save,
              after: () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads the event of [id] and opens it in the edit form.
class EventEditScreen extends ConsumerWidget {
  const EventEditScreen({required this.id, super.key});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return ref
        .watch(listingProvider(id))
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (error, _) => Scaffold(
            appBar: AppBar(title: Text(l.eventEdit)),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(apiFailureMessage(l, error)),
                  TextButton(
                    onPressed: () => ref.invalidate(listingProvider(id)),
                    child: Text(l.errorRetry),
                  ),
                ],
              ),
            ),
          ),
          data: (item) => CreateEventScreen(initial: item),
        );
  }
}

/// Schedule, place and the seat counter of an event card.
class EventSummary extends StatelessWidget {
  const EventSummary({
    required this.listing,
    this.showEmptySeats = false,
    super.key,
  });

  final ListingOutput listing;

  /// Whether to show the counter at zero as well.
  ///
  /// Participants get the "no seats left" state from the seat section; the
  /// author needs the counter to see that the last seat has been taken.
  final bool showEmptySeats;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final startsAt = listing.eventStartsAt;
    final endsAt = listing.eventEndsAt;
    final location = listing.eventLocation;
    final remaining = listing.remainingPlaces;
    String time(DateTime instant) => formatCityTime(
      instant,
      timezone: listing.cityTimezone,
      city: listing.cityTimezone,
      l10n: l,
      includeDate: true,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (startsAt != null && endsAt != null)
          Text(
            l.eventTimeRange(time(startsAt), time(endsAt)),
            key: const Key('event-schedule'),
          ),
        if (location != null && location.isNotEmpty)
          Text(
            l.eventLocationValue(location),
            key: const Key('event-location-value'),
          ),
        if (remaining != null && (remaining > 0 || showEmptySeats))
          Text(
            eventSeatsText(l, remaining),
            key: const Key('event-seats-left'),
          ),
      ],
    );
  }
}

/// The own seat of an event: sign up, join the queue, or cancel.
class EventSeatSection extends ConsumerWidget {
  const EventSeatSection({required this.listing, super.key});

  final ListingOutput listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final seat = ref.watch(eventSeatProvider(listing.id));
    return seat.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(eventFailureMessage(l, error)),
          TextButton(
            onPressed: () => ref.invalidate(eventSeatProvider(listing.id)),
            child: Text(l.errorRetry),
          ),
        ],
      ),
      data: (seat) {
        final open = eventSignupOpen(seat.listing, clock.now());
        final widgets = <Widget>[];
        switch (seat.status) {
          case EventSeatStatus.registered:
            widgets.add(Text(l.eventRegistered));
            final interaction = seat.interaction;
            if (open && interaction != null) {
              widgets.add(
                WaitlistAction(
                  label: l.eventCancelSignup,
                  buttonKey: const Key('event-cancel-signup'),
                  filled: false,
                  failureMessage: eventFailureMessage,
                  run: () => ref
                      .read(campusApiProvider)
                      .listings
                      .transitionInteraction(
                        listingId: seat.listing.id,
                        interactionId: interaction.id,
                        body: const TransitionInput(
                          status: InteractionStatus.cancelled,
                        ),
                      ),
                ),
              );
            }
            break;
          case EventSeatStatus.queued:
            widgets.add(Text(l.eventQueued));
            final entry = seat.entry;
            if (entry != null) {
              if (entry.status == WaitlistStatus.offered) {
                widgets.add(
                  PlaceOfferCard(entry: entry, title: seat.listing.title),
                );
              } else {
                widgets.add(WaitlistQueueControls(entry: entry));
              }
            }
            break;
          case EventSeatStatus.full:
            widgets.add(Text(l.eventNoSeats));
            if (open) {
              widgets.add(
                WaitlistAction(
                  label: l.eventJoinQueue,
                  buttonKey: const Key('event-join-queue'),
                  failureMessage: eventFailureMessage,
                  run: () => ref
                      .read(campusApiProvider)
                      .listings
                      .signupEvent(
                        listingId: seat.listing.id,
                        body: const SignupInput(joinQueue: true),
                      ),
                ),
              );
            } else {
              widgets.add(Text(l.eventSignupClosed));
            }
            break;
          case EventSeatStatus.open:
            if (open) {
              widgets.add(
                WaitlistAction(
                  label: l.eventSignup,
                  buttonKey: const Key('event-signup'),
                  failureMessage: eventFailureMessage,
                  run: () => ref
                      .read(campusApiProvider)
                      .listings
                      .signupEvent(
                        listingId: seat.listing.id,
                        body: const SignupInput(),
                      ),
                ),
              );
            } else {
              widgets.add(Text(l.eventSignupClosed));
            }
        }
        return Column(
          key: Key('event-seat-${seat.status.name}'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: widgets,
        );
      },
    );
  }
}

/// The registered participants of an event; shown to its author.
class EventParticipantsList extends ConsumerStatefulWidget {
  const EventParticipantsList({required this.listingId, super.key});

  final String listingId;

  @override
  ConsumerState<EventParticipantsList> createState() =>
      _EventParticipantsListState();
}

class _EventParticipantsListState extends ConsumerState<EventParticipantsList> {
  String? cursor;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final provider = incomingProvider(widget.listingId, cursor);
    return ref
        .watch(provider)
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Column(
            children: [
              Text(apiFailureMessage(l, error)),
              TextButton(
                onPressed: () => ref.invalidate(provider),
                child: Text(l.errorRetry),
              ),
            ],
          ),
          data: (page) {
            final participants = [
              for (final item in page.items)
                if (item.status == InteractionStatus.accepted) item,
            ];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.eventParticipants,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (participants.isEmpty) Text(l.eventParticipantsEmpty),
                for (final item in participants)
                  ListTile(
                    key: Key('event-participant-${item.id}'),
                    title: Text(item.participantName),
                    subtitle: Text(l.reservationAccepted),
                  ),
                if (page.nextPage != null)
                  TextButton(
                    onPressed: () => setState(() => cursor = page.nextPage),
                    child: Text(l.listingsMore),
                  ),
                if (cursor != null)
                  TextButton(
                    onPressed: () => setState(() => cursor = null),
                    child: Text(l.listingsFirst),
                  ),
              ],
            );
          },
        );
  }
}

/// Controls of the event author: edit the schedule while the event is live.
class EventOwnerActions extends ConsumerWidget {
  const EventOwnerActions({required this.item, super.key});

  final ListingOutput item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    if (!eventSignupOpen(item, clock.now())) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('event-edit'),
        onPressed: () => context.push('/event/${item.id}/edit'),
        icon: const Icon(Icons.edit_outlined),
        label: Text(l.eventEdit),
      ),
    );
  }
}
