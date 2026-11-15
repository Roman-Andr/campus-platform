import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../../core/widgets/city_date_time_picker.dart';
import '../../profile/application/my_profile.dart';
import '../../qr/presentation/qr_summary.dart';
import '../application/lesson_config.dart';
import '../application/listings.dart';
import '../domain/skills.dart';
import 'cancellation.dart';
import 'meeting_screen.dart';
import 'no_meeting_screen.dart';
import 'status_labels.dart';

/// The city name for time annotations; the zone is the fallback.
String lessonCity(WidgetRef ref, ListingOutput listing) =>
    ref
        .watch(citiesProvider)
        .value
        ?.where((city) => city.id == listing.cityId)
        .firstOrNull
        ?.name ??
    listing.cityTimezone;

/// A lesson mutation that keeps the card visible and explains Problem
/// Details locally.
class LessonAction extends ConsumerStatefulWidget {
  const LessonAction({
    required this.label,
    required this.run,
    this.buttonKey,
    this.filled = true,
    this.successMessage,
    this.after,
    super.key,
  });

  final String label;
  final Future<void> Function() run;
  final Key? buttonKey;
  final bool filled;
  final String? successMessage;
  final VoidCallback? after;

  @override
  ConsumerState<LessonAction> createState() => _LessonActionState();
}

class _LessonActionState extends ConsumerState<LessonAction> {
  bool busy = false;
  String? error;

  Future<void> _run() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.run();
      if (!mounted) return;
      refreshListings(ref);
      final message = widget.successMessage;
      if (message != null) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text(message)));
      }
      widget.after?.call();
    } on CancellationDismissed {
      // The user kept the interaction.
    } on Object catch (e) {
      if (mounted) {
        final config = ref.read(lessonConfigProvider);
        setState(
          () => error = lessonFailureMessage(
            context.l10n,
            e,
            minOptions: config.minOptions,
            maxOptions: config.maxOptions,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final onPressed = busy ? null : _run;
    final key = widget.buttonKey;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null)
          Text(
            error!,
            key: const Key('lesson-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (widget.filled)
          FilledButton(
            key: key,
            onPressed: onPressed,
            child: Text(widget.label),
          )
        else
          TextButton(key: key, onPressed: onPressed, child: Text(widget.label)),
      ],
    );
  }
}

/// A future time of the city, used as the default of a new option.
DateTime _defaultTime(int index) =>
    clock.now().add(Duration(days: 1, hours: index));

/// Editable fields of one time option: a city time, a place or online.
class LessonSlotFields extends StatelessWidget {
  const LessonSlotFields({
    required this.draft,
    required this.place,
    required this.timezone,
    required this.city,
    required this.prefix,
    required this.onTimeChanged,
    required this.onOnlineChanged,
    required this.onPlaceChanged,
    this.title,
    this.error,
    this.onRemove,
    super.key,
  });

  final LessonSlotDraft draft;
  final TextEditingController place;
  final String timezone;
  final String city;
  final String prefix;
  final String? title;
  final ValueChanged<DateTime> onTimeChanged;
  final ValueChanged<bool> onOnlineChanged;
  final ValueChanged<String> onPlaceChanged;
  final String? error;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final now = tz.TZDateTime.from(clock.now(), cityLocation(timezone));
    final firstDate = DateTime(now.year, now.month, now.day);
    return Card(
      key: Key(prefix),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null || onRemove != null)
              Row(
                children: [
                  Expanded(child: Text(title ?? '')),
                  if (onRemove != null)
                    IconButton(
                      key: Key('$prefix-remove'),
                      tooltip: l.lessonRemoveOption,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: onRemove,
                    ),
                ],
              ),
            CityDateTimePicker(
              key: Key('$prefix-time'),
              value: draft.time,
              timezone: timezone,
              city: city,
              firstDate: firstDate,
              lastDate: firstDate.add(const Duration(days: 365)),
              onChanged: onTimeChanged,
            ),
            SwitchListTile(
              key: Key('$prefix-online'),
              contentPadding: EdgeInsets.zero,
              title: Text(l.lessonOnlineSwitch),
              value: draft.online,
              onChanged: onOnlineChanged,
            ),
            if (draft.online)
              Text(l.lessonOnline)
            else
              TextField(
                key: Key('$prefix-place'),
                controller: place,
                decoration: InputDecoration(labelText: l.lessonPlaceLabel),
                onChanged: onPlaceChanged,
              ),
            if (error != null)
              Text(
                error!,
                key: Key('$prefix-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }
}

/// A form of 2–3 lesson time options; the bounds come from [LessonConfig].
class LessonSlotsForm extends ConsumerStatefulWidget {
  const LessonSlotsForm({
    required this.listing,
    required this.minOptions,
    required this.maxOptions,
    required this.onSubmit,
    super.key,
  });

  final ListingOutput listing;
  final int minOptions;
  final int maxOptions;

  /// Sends the options; the caller closes the form on success.
  final Future<void> Function(List<LessonSlotInput> options) onSubmit;

  @override
  ConsumerState<LessonSlotsForm> createState() => _LessonSlotsFormState();
}

class _SlotEntry {
  _SlotEntry(this.draft) : place = TextEditingController(text: draft.location);

  LessonSlotDraft draft;
  final TextEditingController place;
  String? error;
}

class _LessonSlotsFormState extends ConsumerState<LessonSlotsForm> {
  late final List<_SlotEntry> _slots = List.generate(
    widget.minOptions.clamp(1, widget.maxOptions),
    (index) => _SlotEntry(LessonSlotDraft(time: _defaultTime(index))),
  );
  String? _countError;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    for (final slot in _slots) {
      slot.place.dispose();
    }
    super.dispose();
  }

  void _add() {
    if (_slots.length >= widget.maxOptions) return;
    final index = _slots.length;
    setState(() {
      _countError = null;
      _slots.add(_SlotEntry(LessonSlotDraft(time: _defaultTime(index))));
    });
  }

  void _remove(int index) {
    if (_slots.length <= 1) return;
    setState(() {
      _countError = null;
      _slots.removeAt(index).place.dispose();
    });
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final countError = lessonCountError(
      l,
      _slots.length,
      minOptions: widget.minOptions,
      maxOptions: widget.maxOptions,
    );
    var valid = countError == null;
    setState(() {
      _countError = countError;
      _error = null;
      for (final slot in _slots) {
        slot.error = slot.draft.error(l);
        if (slot.error != null) valid = false;
      }
    });
    if (!valid) return;
    setState(() => _busy = true);
    try {
      await widget.onSubmit([for (final slot in _slots) slot.draft.toInput()]);
    } on Object catch (e) {
      if (mounted) {
        final config = ref.read(lessonConfigProvider);
        setState(
          () => _error = lessonFailureMessage(
            context.l10n,
            e,
            minOptions: config.minOptions,
            maxOptions: config.maxOptions,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final city = lessonCity(ref, widget.listing);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.lessonOptionsHint(widget.minOptions, widget.maxOptions)),
        for (var index = 0; index < _slots.length; index++)
          LessonSlotFields(
            draft: _slots[index].draft,
            place: _slots[index].place,
            timezone: widget.listing.cityTimezone,
            city: city,
            prefix: 'lesson-slot-$index',
            title: l.lessonOptionNumber(index + 1),
            error: _slots[index].error,
            onRemove: _slots.length > 1 ? () => _remove(index) : null,
            onTimeChanged: (time) => setState(() {
              _slots[index].draft = _slots[index].draft.copyWith(time: time);
              _slots[index].error = null;
            }),
            onOnlineChanged: (online) => setState(() {
              _slots[index].draft = _slots[index].draft.copyWith(
                online: online,
              );
              _slots[index].error = null;
            }),
            onPlaceChanged: (value) => setState(() {
              _slots[index].draft = _slots[index].draft.copyWith(
                location: value,
              );
              _slots[index].error = null;
            }),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const Key('lesson-add-option'),
          onPressed: _slots.length < widget.maxOptions && !_busy ? _add : null,
          icon: const Icon(Icons.add),
          label: Text(l.lessonAddOption),
        ),
        if (_countError != null)
          Text(
            _countError!,
            key: const Key('lesson-options-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (_error != null)
          Text(
            _error!,
            key: const Key('lesson-form-error'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('lesson-submit'),
          onPressed: _busy ? null : _submit,
          child: Text(l.lessonSend),
        ),
      ],
    );
  }
}

/// The form of a lesson: 2–3 options for a new or repeated lesson, or the
/// author's counter-proposal with one option.
class LessonFormScreen extends ConsumerWidget {
  const LessonFormScreen({required this.listing, this.repeatOf, super.key});

  final ListingOutput listing;

  /// The lesson to repeat with the same participant; null for a new one.
  final InteractionOutput? repeatOf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final config = ref.watch(lessonConfigProvider);
    final me = ref.watch(myProfileProvider).value?.id;
    final repeat = repeatOf;
    // The participant repeats with the author and the author with the
    // participant: show the other side, never the current user's own name.
    final counterpart = repeat == null
        ? null
        : listing.authorId == me
        ? repeat.participantName
        : listing.authorName;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          counterpart == null
              ? l.lessonProposeTitle
              : l.lessonRepeatTitle(counterpart),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (counterpart != null) ...[
            Text(l.lessonCounterpart(counterpart)),
            const SizedBox(height: 8),
          ],
          LessonSlotsForm(
            listing: listing,
            minOptions: config.minOptions,
            maxOptions: config.maxOptions,
            onSubmit: (options) async {
              final api = ref.read(campusApiProvider).listings;
              final messenger = ScaffoldMessenger.maybeOf(context);
              // Both requests carry every option; a failure is shown by the
              // form, so only a successful send closes it.
              await (repeat == null
                  ? api.proposeLesson(
                      listingId: listing.id,
                      body: LessonInput(options: options),
                    )
                  : api.repeatLesson(
                      listingId: listing.id,
                      interactionId: repeat.id,
                      body: LessonInput(options: options),
                    ));
              refreshListings(ref);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              messenger?.showSnackBar(
                SnackBar(
                  content: Text(
                    repeat == null ? l.lessonSent : l.lessonRepeated,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Opens the lesson form and keeps the previous lesson as is.
void openLessonForm(
  BuildContext context,
  WidgetRef ref,
  ListingOutput listing, {
  InteractionOutput? repeatOf,
}) {
  Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => LessonFormScreen(listing: listing, repeatOf: repeatOf),
    ),
  );
}

/// "Another lesson" on an accepted or completed lesson.
class LessonRepeatButton extends ConsumerWidget {
  const LessonRepeatButton({
    required this.item,
    required this.listing,
    super.key,
  });

  final InteractionOutput item;
  final ListingOutput listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myProfileProvider).value?.id;
    if (!lessonCanRepeat(item, listing, me)) return const SizedBox.shrink();
    return TextButton.icon(
      key: Key('lesson-repeat-${item.id}'),
      onPressed: () => openLessonForm(context, ref, listing, repeatOf: item),
      icon: const Icon(Icons.event_repeat),
      label: Text(context.l10n.lessonRepeat),
    );
  }
}

/// The time options of one lesson: who proposed each and who may choose it.
class LessonOptionsCard extends ConsumerStatefulWidget {
  const LessonOptionsCard({
    required this.item,
    required this.listing,
    this.onChanged,
    super.key,
  });

  final InteractionOutput item;
  final ListingOutput listing;
  final VoidCallback? onChanged;

  @override
  ConsumerState<LessonOptionsCard> createState() => _LessonOptionsCardState();
}

class _LessonOptionsCardState extends ConsumerState<LessonOptionsCard> {
  bool _countering = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final me = ref.watch(myProfileProvider).value?.id;
    final options = lessonOptionsOf(widget.item);
    final city = lessonCity(ref, widget.listing);
    final pending = widget.item.status == InteractionStatus.pending;
    final awaiting = lessonAwaitingLabel(l, widget.item, widget.listing, me);
    return Card(
      key: Key('lesson-options-${widget.item.id}'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.lessonOptionsTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (options.isEmpty) Text(l.lessonNoOptions),
            for (final option in options)
              _LessonOptionRow(
                item: widget.item,
                listing: widget.listing,
                option: option,
                city: city,
                me: me,
                onChanged: widget.onChanged,
              ),
            if (pending) ...[
              Text(awaiting, key: Key('lesson-awaiting-${widget.item.id}')),
              if (widget.item.responseDueAt != null)
                Text(
                  l.lessonResponseDue(
                    formatCityTime(
                      widget.item.responseDueAt!,
                      timezone: widget.listing.cityTimezone,
                      city: city,
                      l10n: l,
                      includeDate: true,
                    ),
                  ),
                ),
              if (lessonCanCounter(widget.item, widget.listing, me))
                TextButton.icon(
                  key: const Key('lesson-counter'),
                  onPressed: () => setState(() => _countering = !_countering),
                  icon: const Icon(Icons.edit_calendar_outlined),
                  label: Text(l.lessonCounter),
                ),
            ],
            if (_countering)
              _LessonCounterForm(
                item: widget.item,
                listing: widget.listing,
                onDone: () => setState(() => _countering = false),
              ),
          ],
        ),
      ),
    );
  }
}

class _LessonOptionRow extends ConsumerWidget {
  const _LessonOptionRow({
    required this.item,
    required this.listing,
    required this.option,
    required this.city,
    required this.me,
    this.onChanged,
  });

  final InteractionOutput item;
  final ListingOutput listing;
  final LessonOptionOutput option;
  final String city;
  final String? me;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final when = formatCityTime(
      option.time,
      timezone: listing.cityTimezone,
      city: city,
      l10n: l,
      includeDate: true,
    );
    final format = option.online
        ? l.lessonOnline
        : option.location == null
        ? l.lessonOffline
        : l.meetingPlace(option.location!);
    final author = switch (option.proposedById) {
      final id when id == me => l.lessonOptionByYou,
      final id when id == listing.authorId => l.lessonOptionByAuthor,
      _ => l.lessonOptionByParticipant,
    };
    final canAccept = lessonOptionCanBeAccepted(item, listing, option, me);
    return ListTile(
      key: Key('lesson-option-${option.id}'),
      contentPadding: EdgeInsets.zero,
      title: Text('$when · $format'),
      subtitle: Text('$author · ${lessonOptionStatusLabel(l, option.status)}'),
      trailing: canAccept
          ? LessonAction(
              label: l.lessonAccept,
              buttonKey: Key('lesson-accept-${option.id}'),
              successMessage: l.lessonAccepted,
              after: onChanged,
              run: () async {
                await ref
                    .read(campusApiProvider)
                    .listings
                    .acceptLesson(
                      listingId: listing.id,
                      interactionId: item.id,
                      body: LessonAcceptInput(optionId: option.id),
                    );
              },
            )
          : null,
    );
  }
}

/// The author's counter-proposal: one time instead of the offered options.
class _LessonCounterForm extends ConsumerStatefulWidget {
  const _LessonCounterForm({
    required this.item,
    required this.listing,
    required this.onDone,
  });

  final InteractionOutput item;
  final ListingOutput listing;
  final VoidCallback onDone;

  @override
  ConsumerState<_LessonCounterForm> createState() => _LessonCounterFormState();
}

class _LessonCounterFormState extends ConsumerState<_LessonCounterForm> {
  late LessonSlotDraft _draft = LessonSlotDraft(time: _defaultTime(0));
  final _place = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _place.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = context.l10n;
    final error = _draft.error(l);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(campusApiProvider)
          .listings
          .counterProposeLesson(
            listingId: widget.listing.id,
            interactionId: widget.item.id,
            body: counterSlot(_draft),
          );
      refreshListings(ref);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(l.lessonCounterSent)));
      widget.onDone();
    } on Object catch (e) {
      if (mounted) {
        final config = ref.read(lessonConfigProvider);
        setState(
          () => _error = lessonFailureMessage(
            context.l10n,
            e,
            minOptions: config.minOptions,
            maxOptions: config.maxOptions,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final city = lessonCity(ref, widget.listing);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.lessonCounterTitle),
        LessonSlotFields(
          draft: _draft,
          place: _place,
          timezone: widget.listing.cityTimezone,
          city: city,
          prefix: 'lesson-counter',
          error: _error,
          onTimeChanged: (time) => setState(() {
            _draft = _draft.copyWith(time: time);
            _error = null;
          }),
          onOnlineChanged: (online) => setState(() {
            _draft = _draft.copyWith(online: online);
            _error = null;
          }),
          onPlaceChanged: (value) => setState(() {
            _draft = _draft.copyWith(location: value);
            _error = null;
          }),
        ),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              key: const Key('lesson-counter-send'),
              onPressed: _busy ? null : _submit,
              child: Text(l.lessonSend),
            ),
            TextButton(
              key: const Key('lesson-counter-cancel'),
              onPressed: _busy ? null : widget.onDone,
              child: Text(l.meetingDismiss),
            ),
          ],
        ),
      ],
    );
  }
}

/// A lesson row of the participant: options, meeting, repeat and withdrawal.
class LessonParticipationSection extends ConsumerWidget {
  const LessonParticipationSection({required this.listing, super.key});

  final ListingOutput listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final config = ref.watch(lessonConfigProvider);
    return ref
        .watch(listingParticipationProvider(listing.id))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lessonFailureMessage(
                  l,
                  e,
                  minOptions: config.minOptions,
                  maxOptions: config.maxOptions,
                ),
              ),
              TextButton(
                onPressed: () =>
                    ref.invalidate(listingParticipationProvider(listing.id)),
                child: Text(l.errorRetry),
              ),
            ],
          ),
          data: (items) {
            final active = lessonHasActiveLesson(items);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in items)
                  _LessonParticipationCard(item: item, listing: listing),
                if (!active)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: FilledButton.icon(
                      key: const Key('lesson-propose'),
                      onPressed: () => openLessonForm(context, ref, listing),
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text(l.lessonPropose),
                    ),
                  ),
              ],
            );
          },
        );
  }
}

class _LessonParticipationCard extends ConsumerWidget {
  const _LessonParticipationCard({required this.item, required this.listing});

  final InteractionOutput item;
  final ListingOutput listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final me = ref.watch(myProfileProvider).value?.id;
    final city = lessonCity(ref, listing);
    final active =
        item.status == InteractionStatus.pending ||
        item.status == InteractionStatus.accepted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          interactionStatusLabel(l, item.status),
          key: Key('lesson-status-${item.id}'),
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (active || lessonOptionsOf(item).isNotEmpty)
          LessonOptionsCard(item: item, listing: listing),
        MeetingSummary(item: item, timezone: listing.cityTimezone, city: city),
        LessonRepeatButton(item: item, listing: listing),
        NoMeetingSummary(item: item, kind: listing.kind),
        QrConfirmationSummary(item: item, kind: listing.kind),
        if (active && item.participantId == me)
          LessonAction(
            label: l.reservationCancel,
            filled: false,
            run: () async {
              await ensureParticipantCancellation(
                context,
                ref,
                listingId: listing.id,
                interactionId: item.id,
              );
              await ref
                  .read(campusApiProvider)
                  .listings
                  .transitionInteraction(
                    listingId: listing.id,
                    interactionId: item.id,
                    body: const TransitionInput(
                      status: InteractionStatus.cancelled,
                    ),
                  );
            },
          ),
      ],
    );
  }
}
