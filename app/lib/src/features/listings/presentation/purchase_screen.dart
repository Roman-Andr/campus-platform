import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/api/api_client.dart';
import '../../../core/api/api_failure_message.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../../core/widgets/city_date_time_picker.dart';
import '../../profile/application/my_profile.dart';
import '../application/help_config.dart';
import '../application/listings.dart';
import '../application/purchase.dart';
import '../domain/purchase.dart';
import 'cancellation.dart';
import 'listings_screens.dart';

/// Explains the purchase conflicts of the server (Problem Details).
String purchaseFailureMessage(AppLocalizations l, Object error) =>
    switch (ApiFailure.from(error)) {
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.listingPurchaseClosed),
      ) =>
        l.purchaseCollectionClosed,
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.listingPurchaseUnitsUnavailable,
        ),
        :final problem,
      ) =>
        switch (problem.additionalProperties['available']) {
          final num available when available > 0 => l.purchaseUnitsUnavailable(
            available.toInt(),
          ),
          _ => l.purchaseShareNoUnits,
        },
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.listingPurchaseLeaveRequiresApproval,
        ),
      ) =>
        l.purchaseLeaveApprovalRequired,
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.listingPurchaseShareExists,
        ),
      ) =>
        l.purchaseShareExists,
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.listingPurchaseVolumeInvalid,
        ),
      ) =>
        l.purchaseVolumeInvalid,
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.listingPurchaseDeadlineInvalid,
        ),
      ) =>
        l.purchaseDeadlineInvalid,
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.listingPurchaseWithdrawalExists,
        ),
      ) =>
        l.purchaseLeaveRequestPending,
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.listingPurchaseWithdrawalMissing,
        ),
      ) =>
        l.purchaseLeaveRequestMissing,
      ProblemFailure(
        code: ProblemCodeKnown(value: ProblemCodeValue.listingPurchaseNotFixed),
      ) =>
        l.purchaseNotFixed,
      ProblemFailure(
        code: ProblemCodeKnown(
          value: ProblemCodeValue.listingPurchaseCapacityConflict,
        ),
      ) =>
        l.purchaseCapacityConflict,
      ProblemFailure(status: 404) => l.listingUnavailable,
      _ => apiFailureMessage(l, error),
    };

/// Creates a group purchase with its unit price, volume bounds and deadline
/// (ТЗ п. 5.1.1, модуль 4, п. 13).
class CreatePurchaseScreen extends ConsumerStatefulWidget {
  const CreatePurchaseScreen({super.key});

  @override
  ConsumerState<CreatePurchaseScreen> createState() =>
      _CreatePurchaseScreenState();
}

class _CreatePurchaseScreenState extends ConsumerState<CreatePurchaseScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _min = TextEditingController(text: '1');
  final _max = TextEditingController();
  Visibility _scope = Visibility.city;
  Audience _audience = Audience.students;
  String? _categoryId;
  late DateTime _deadline = clock.now().add(const Duration(days: 3));
  String? _deadlineError;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final config = ref.read(helpConfigProvider);
    final issue = purchaseDeadlineIssue(
      _deadline,
      lifetime: config.listingLifetime,
    );
    if (issue != null) {
      setState(
        () => _deadlineError = purchaseDeadlineError(
          l,
          issue,
          lifetimeDays: config.listingLifetimeDays,
        ),
      );
      throw const InvalidListingForm();
    }
    setState(() => _deadlineError = null);
    if (!(_form.currentState?.validate() ?? false)) {
      throw const InvalidListingForm();
    }
    final price = normalizePurchasePrice(_price.text);
    final min = int.tryParse(_min.text.trim());
    final max = int.tryParse(_max.text.trim());
    if (price == null || min == null || max == null) {
      throw const InvalidListingForm();
    }
    final employee =
        ref.read(myProfileProvider).value?.accountType ==
        UserOutputAccountType.employee;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await ref
        .read(campusApiProvider)
        .listings
        .publishPurchase(
          body: PurchaseInput(
            title: _title.text.trim(),
            description: _description.text.trim(),
            visibility: _scope,
            audience: employee ? Audience.community : _audience,
            categoryId: _categoryId,
            pricePerUnit: PurchaseInputPricePerUnit.fromJson(price),
            minUnits: min,
            maxUnits: max,
            collectionDeadline: _deadline,
          ),
        );
    refreshListings(ref);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger?.showSnackBar(SnackBar(content: Text(l.purchasePublished)));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final config = ref.watch(helpConfigProvider);
    final user = ref.watch(myProfileProvider).value;
    final employee = user?.accountType == UserOutputAccountType.employee;
    final categories = ref.watch(listingCategoriesProvider);
    final timezone = user?.cityTimezone ?? 'UTC';
    final today = tz.TZDateTime.from(clock.now(), cityLocation(timezone));
    final firstDate = DateTime(today.year, today.month, today.day);
    final lastDate = firstDate.add(config.listingLifetime);
    final pickerValue = _deadline.isBefore(firstDate) ? firstDate : _deadline;
    return Scaffold(
      appBar: AppBar(title: Text(l.purchaseCreateTitle)),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            categories.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Column(
                children: [
                  Text(apiFailureMessage(l, error)),
                  TextButton(
                    onPressed: () => ref.invalidate(listingCategoriesProvider),
                    child: Text(l.errorRetry),
                  ),
                ],
              ),
              data: (items) => items.isEmpty
                  ? Text(l.listingCategoriesEmpty)
                  : DropdownButtonFormField<String>(
                      key: const Key('purchase-category'),
                      initialValue: items.any((item) => item.id == _categoryId)
                          ? _categoryId
                          : null,
                      decoration: InputDecoration(labelText: l.listingCategory),
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
                      onChanged: (value) => setState(() => _categoryId = value),
                    ),
            ),
            TextFormField(
              key: const Key('purchase-title'),
              controller: _title,
              decoration: InputDecoration(labelText: l.listingTitle),
              validator: (value) => value == null || value.trim().isEmpty
                  ? l.signInNameRequired
                  : null,
            ),
            TextFormField(
              key: const Key('purchase-description'),
              controller: _description,
              decoration: InputDecoration(labelText: l.listingDescription),
              minLines: 3,
              maxLines: null,
              validator: (value) => value == null || value.trim().isEmpty
                  ? l.signInNameRequired
                  : null,
            ),
            DropdownButtonFormField<Visibility>(
              key: const Key('purchase-scope'),
              initialValue: _scope,
              decoration: InputDecoration(labelText: l.listingScope),
              items: [
                for (final scope in [
                  Visibility.city,
                  if (user?.facultyId != null) Visibility.faculty,
                  if (user?.dormitoryId != null && !employee)
                    Visibility.dormitory,
                ])
                  DropdownMenuItem(
                    value: scope,
                    child: Text(scopeName(l, scope)),
                  ),
              ],
              onChanged: (value) => setState(() => _scope = value!),
            ),
            DropdownButtonFormField<Audience>(
              key: const Key('purchase-audience'),
              initialValue: employee ? Audience.community : _audience,
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
              onChanged: user == null || employee
                  ? null
                  : (value) => setState(() => _audience = value!),
            ),
            TextFormField(
              key: const Key('purchase-price'),
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: l.purchasePrice),
              validator: (value) => normalizePurchasePrice(value ?? '') == null
                  ? l.purchasePriceInvalid
                  : null,
            ),
            TextFormField(
              key: const Key('purchase-min-units'),
              controller: _min,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.purchaseMinUnits),
              validator: (value) {
                final min = int.tryParse(value?.trim() ?? '');
                return min == null || min < 1 ? l.purchaseMinInvalid : null;
              },
            ),
            TextFormField(
              key: const Key('purchase-max-units'),
              controller: _max,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.purchaseMaxUnits),
              validator: (value) {
                final max = int.tryParse(value?.trim() ?? '');
                final min = int.tryParse(_min.text.trim());
                if (max == null || max < 1) return l.purchaseMinInvalid;
                if (min != null && max < min) {
                  return l.purchaseMaxBelowMin(min);
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text(
              l.purchaseCollectionDeadline,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            CityDateTimePicker(
              value: pickerValue,
              timezone: timezone,
              city: timezone,
              firstDate: firstDate,
              lastDate: lastDate,
              onChanged: (value) => setState(() {
                _deadline = value;
                _deadlineError = null;
              }),
            ),
            if (_deadlineError != null)
              Text(_deadlineError!, key: const Key('purchase-deadline-error')),
            const SizedBox(height: 16),
            ListingAction(
              key: const Key('purchase-submit'),
              label: l.listingPublish,
              failureMessage: purchaseFailureMessage,
              enabled: user != null,
              run: _save,
            ),
          ],
        ),
      ),
    );
  }
}

/// Price, volume and deadline of a purchase on its card.
class PurchaseSummary extends StatelessWidget {
  const PurchaseSummary({required this.listing, super.key});

  final ListingOutput listing;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final stage = purchaseStageOf(listing);
    final deadline = listing.purchaseCollectionDeadline;
    final price = listing.purchaseUnitPrice;
    final min = listing.purchaseMinUnits;
    final time = deadline == null
        ? null
        : formatCityTime(
            deadline,
            timezone: listing.cityTimezone,
            city: listing.cityTimezone,
            l10n: l,
            includeDate: true,
          );
    return Column(
      key: const Key('purchase-summary'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(purchaseStageLabel(l, stage), key: const Key('purchase-stage')),
        if (price != null)
          Text(
            l.purchaseUnitPriceValue(formatPurchaseMoney(l, price)),
            key: const Key('purchase-unit-price'),
          ),
        Text(
          purchaseCollectedLabel(l, listing),
          key: const Key('purchase-collected'),
        ),
        if (min != null)
          Text(l.purchaseMinimumValue(min), key: const Key('purchase-minimum')),
        if (stage == PurchaseStage.fixed && listing.purchaseFixedUnits != null)
          Text(
            l.purchaseFixedUnitsValue(listing.purchaseFixedUnits!),
            key: const Key('purchase-fixed-units'),
          ),
        if (time != null)
          Text(
            l.purchaseCollectionDeadlineValue(time),
            key: const Key('purchase-deadline'),
          ),
      ],
    );
  }
}

/// The own share of a purchase: join, change units, leave, or ask to leave
/// once the composition is fixed.
class PurchaseShareSection extends ConsumerWidget {
  const PurchaseShareSection({required this.listing, super.key});

  final ListingOutput listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return ref
        .watch(myPurchaseShareProvider(listing.id))
        .when(
          loading: () => const SizedBox.shrink(),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(purchaseFailureMessage(l, error)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(myPurchaseShareProvider(listing.id)),
                child: Text(l.errorRetry),
              ),
            ],
          ),
          data: (share) => share == null
              ? _PurchaseJoinForm(listing: listing)
              : _PurchaseOwnShare(
                  key: ValueKey('purchase-share-${share.id}-${share.units}'),
                  listing: listing,
                  share: share,
                ),
        );
  }
}

class _PurchaseJoinForm extends ConsumerStatefulWidget {
  const _PurchaseJoinForm({required this.listing});

  final ListingOutput listing;

  @override
  ConsumerState<_PurchaseJoinForm> createState() => _PurchaseJoinFormState();
}

class _PurchaseJoinFormState extends ConsumerState<_PurchaseJoinForm> {
  final _form = GlobalKey<FormState>();
  final _units = TextEditingController(text: '1');

  @override
  void dispose() {
    _units.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final listing = widget.listing;
    if (!purchaseCollectionOpen(listing, clock.now())) {
      return Text(
        l.purchaseCollectionClosed,
        key: const Key('purchase-collection-closed'),
      );
    }
    final available = purchaseAvailableUnits(listing);
    return Form(
      key: _form,
      child: Column(
        key: const Key('purchase-join'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.purchaseShareTitle,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            l.purchaseShareAvailable(available),
            key: const Key('purchase-share-available'),
          ),
          if (available > 0)
            TextFormField(
              key: const Key('purchase-share-units'),
              controller: _units,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: l.purchaseShareInput),
              onChanged: (_) => setState(() {}),
              validator: (_) => purchaseUnitsError(
                l,
                listing,
                int.tryParse(_units.text.trim()),
              ),
            ),
          if (available > 0)
            Text(
              l.purchaseShareAmount(
                formatPurchaseMoney(
                  l,
                  purchaseAmount(
                    listing.purchaseUnitPrice ?? '0',
                    int.tryParse(_units.text.trim()) ?? 0,
                  ),
                ),
              ),
              key: const Key('purchase-amount-preview'),
            ),
          ListingAction(
            label: l.purchaseShareJoin,
            buttonKey: const Key('purchase-share-join'),
            failureMessage: purchaseFailureMessage,
            enabled: available > 0,
            run: () async {
              if (!(_form.currentState?.validate() ?? false)) {
                throw const InvalidListingForm();
              }
              final units = int.parse(_units.text.trim());
              await ref
                  .read(campusApiProvider)
                  .listings
                  .joinListingPurchase(
                    listingId: listing.id,
                    body: ShareInput(units: units),
                  );
            },
            after: () => ScaffoldMessenger.maybeOf(context)
                ?.showSnackBar(SnackBar(content: Text(l.purchaseShareJoined))),
          ),
        ],
      ),
    );
  }
}

class _PurchaseOwnShare extends ConsumerWidget {
  const _PurchaseOwnShare({
    required this.listing,
    required this.share,
    super.key,
  });

  final ListingOutput listing;
  final PurchaseShareOutput share;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final stage = purchaseStageOf(listing) ?? purchaseStageValue(share.stage);
    final units = share.units ?? 0;
    final open = purchaseCollectionOpen(listing, clock.now());
    return Column(
      key: const Key('purchase-own-share'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.purchaseShareTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          l.purchaseShareUnits(units),
          key: const Key('purchase-share-units-value'),
        ),
        Text(
          l.purchaseShareAmount(formatPurchaseMoney(l, share.amount)),
          key: const Key('purchase-share-amount'),
        ),
        if (stage == PurchaseStage.collecting) ...[
          if (open) ...[
            _PurchaseChangeForm(
              key: ValueKey('purchase-change-${share.id}-${share.units}'),
              listing: listing,
              share: share,
            ),
            ListingAction(
              label: l.purchaseShareLeave,
              buttonKey: const Key('purchase-share-leave'),
              failureMessage: purchaseFailureMessage,
              run: () async {
                await ref
                    .read(campusApiProvider)
                    .listings
                    .leaveMyPurchaseShare(listingId: listing.id);
              },
              after: () => ScaffoldMessenger.maybeOf(context)
                  ?.showSnackBar(SnackBar(content: Text(l.purchaseShareLeft))),
            ),
          ] else
            Text(
              l.purchaseCollectionClosed,
              key: const Key('purchase-collection-closed'),
            ),
        ],
        if (stage == PurchaseStage.fixed) ...[
          Text(
            l.purchaseLeaveApprovalRequired,
            key: const Key('purchase-leave-approval-required'),
          ),
          if (share.leaveRequestedAt == null)
            ListingAction(
              label: l.purchaseLeaveRequest,
              buttonKey: const Key('purchase-request-leave'),
              failureMessage: purchaseFailureMessage,
              run: () async {
                await ensureParticipantCancellation(
                  context,
                  ref,
                  listingId: listing.id,
                  interactionId: share.id,
                );
                await ref
                    .read(campusApiProvider)
                    .listings
                    .requestMyPurchaseWithdrawal(
                      listingId: listing.id,
                      body: const WithdrawalInput(),
                    );
              },
              after: () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text(l.purchaseLeaveRequestSent)),
              ),
            )
          else ...[
            Text(
              l.purchaseLeaveRequestPending,
              key: const Key('purchase-leave-request-pending'),
            ),
            ListingAction(
              label: l.purchaseLeaveCancel,
              buttonKey: const Key('purchase-cancel-leave'),
              failureMessage: purchaseFailureMessage,
              run: () async {
                await ref
                    .read(campusApiProvider)
                    .listings
                    .cancelMyPurchaseWithdrawal(listingId: listing.id);
              },
              after: () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                SnackBar(content: Text(l.purchaseLeaveRequestCancelled)),
              ),
            ),
          ],
        ],
        if (stage == PurchaseStage.cancelled)
          Text(
            l.purchaseStageCancelled,
            key: const Key('purchase-collection-cancelled'),
          ),
      ],
    );
  }
}

class _PurchaseChangeForm extends ConsumerStatefulWidget {
  const _PurchaseChangeForm({
    required this.listing,
    required this.share,
    super.key,
  });

  final ListingOutput listing;
  final PurchaseShareOutput share;

  @override
  ConsumerState<_PurchaseChangeForm> createState() =>
      _PurchaseChangeFormState();
}

class _PurchaseChangeFormState extends ConsumerState<_PurchaseChangeForm> {
  final _form = GlobalKey<FormState>();
  late final _units = TextEditingController(text: '${widget.share.units ?? 1}');

  @override
  void dispose() {
    _units.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final own = widget.share.units ?? 0;
    final available = purchaseAvailableUnits(widget.listing, ownUnits: own);
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.purchaseShareAvailable(available),
            key: const Key('purchase-share-available'),
          ),
          TextFormField(
            key: const Key('purchase-share-units'),
            controller: _units,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l.purchaseShareInput),
            onChanged: (_) => setState(() {}),
            validator: (_) => purchaseUnitsError(
              l,
              widget.listing,
              int.tryParse(_units.text.trim()),
              ownUnits: own,
            ),
          ),
          Text(
            l.purchaseNewAmount(
              formatPurchaseMoney(
                l,
                purchaseAmount(
                  widget.listing.purchaseUnitPrice ?? '0',
                  int.tryParse(_units.text.trim()) ?? 0,
                ),
              ),
            ),
            key: const Key('purchase-amount-preview'),
          ),
          ListingAction(
            label: l.purchaseShareChange,
            buttonKey: const Key('purchase-share-change'),
            failureMessage: purchaseFailureMessage,
            run: () async {
              if (!(_form.currentState?.validate() ?? false)) {
                throw const InvalidListingForm();
              }
              final units = int.parse(_units.text.trim());
              await ref
                  .read(campusApiProvider)
                  .listings
                  .changeMyPurchaseShare(
                    listingId: widget.listing.id,
                    body: ShareInput(units: units),
                  );
            },
            after: () => ScaffoldMessenger.maybeOf(context)
                ?.showSnackBar(SnackBar(content: Text(l.purchaseShareChanged))),
          ),
        ],
      ),
    );
  }
}

/// The whole composition with amounts, shown to the organiser.
///
/// A participant's request to leave a fixed purchase is decided here.
class PurchaseCompositionSection extends ConsumerWidget {
  const PurchaseCompositionSection({required this.listingId, super.key});

  final String listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return ref
        .watch(purchaseCompositionProvider(listingId))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (error, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(purchaseFailureMessage(l, error)),
              TextButton(
                onPressed: () =>
                    ref.invalidate(purchaseCompositionProvider(listingId)),
                child: Text(l.errorRetry),
              ),
            ],
          ),
          data: (composition) => Column(
            key: const Key('purchase-composition'),
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l.purchaseCompositionTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (composition.items?.isEmpty ?? true)
                Text(l.purchaseCompositionEmpty),
              for (final item
                  in composition.items ?? const <PurchaseShareOutput>[])
                _CompositionTile(listingId: listingId, item: item),
              Text(
                l.purchaseCompositionTotal(
                  composition.totalUnits,
                  formatPurchaseMoney(l, composition.totalAmount),
                ),
                key: const Key('purchase-composition-total'),
              ),
            ],
          ),
        );
  }
}

class _CompositionTile extends ConsumerWidget {
  const _CompositionTile({required this.listingId, required this.item});

  final String listingId;
  final PurchaseShareOutput item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final pending = item.leaveRequestedAt != null;
    return Column(
      key: Key('purchase-composition-item-${item.id}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(item.participantName),
          subtitle: Text(
            [
              l.purchaseShareUnits(item.units ?? 0),
              l.purchaseShareAmount(formatPurchaseMoney(l, item.amount)),
            ].join(' · '),
          ),
        ),
        if (pending) ...[
          Text(
            l.purchaseLeaveRequestedBy,
            key: Key('purchase-leave-request-${item.id}'),
          ),
          Wrap(
            spacing: 8,
            children: [
              ListingAction(
                label: l.purchaseLeaveApprove,
                buttonKey: Key('purchase-leave-approve-${item.id}'),
                failureMessage: purchaseFailureMessage,
                run: () => _decide(ref, approve: true),
                after: () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(content: Text(l.purchaseLeaveApproved)),
                ),
              ),
              ListingAction(
                label: l.purchaseLeaveReject,
                buttonKey: Key('purchase-leave-reject-${item.id}'),
                failureMessage: purchaseFailureMessage,
                run: () => _decide(ref, approve: false),
                after: () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  SnackBar(content: Text(l.purchaseLeaveRejected)),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _decide(WidgetRef ref, {required bool approve}) => ref
      .read(campusApiProvider)
      .listings
      .decideMyPurchaseWithdrawal(
        listingId: listingId,
        interactionId: item.id,
        body: WithdrawalDecision(approve: approve),
      );
}
