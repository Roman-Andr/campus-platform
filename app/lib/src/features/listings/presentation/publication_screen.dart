import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Visibility;
import 'package:timezone/timezone.dart' as tz;

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/time/city_time.dart';
import '../../../core/widgets/city_date_time_picker.dart';
import '../../profile/application/my_profile.dart';
import '../domain/publication.dart';
import 'listings_screens.dart';

/// A headman publishes a pinned notice for their dormitory or faculty
/// (ТЗ п. 5.1.5); the server checks the scope and the pin deadline.
class CreatePublicationScreen extends ConsumerStatefulWidget {
  const CreatePublicationScreen({this.initial, super.key});

  /// The notice to edit; `null` when creating a new one.
  final ListingOutput? initial;

  @override
  ConsumerState<CreatePublicationScreen> createState() =>
      _CreatePublicationScreenState();
}

class _CreatePublicationScreenState
    extends ConsumerState<CreatePublicationScreen> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController();
  final description = TextEditingController();

  late DateTime pinnedUntil;
  PublicationScope? scope;
  String? pinError;

  @override
  void initState() {
    super.initState();
    final item = widget.initial;
    title.text = item?.title ?? '';
    description.text = item?.description ?? '';
    pinnedUntil = item?.pinnedUntil ?? clock.now().add(const Duration(days: 7));
    if (item != null) {
      scope = PublicationScope(
        visibility: item.visibility,
        dormitoryId: item.dormitoryId,
        facultyId: item.facultyId,
      );
    }
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save(PublicationScope selected) async {
    if (!form.currentState!.validate()) throw const InvalidListingForm();
    if (!pinnedUntil.isAfter(clock.now())) {
      setState(() => pinError = context.l10n.feedPinInFuture);
      throw const InvalidListingForm();
    }
    setState(() => pinError = null);
    final api = ref.read(campusApiProvider);
    final item = widget.initial;
    if (item != null) {
      await api.listings.editListing(
        listingId: item.id,
        body: ListingEdit(
          title: title.text.trim(),
          description: description.text.trim(),
          version: item.version,
          pinnedUntil: pinnedUntil,
        ),
      );
    } else {
      await api.listings.publishPublication(
        body: PublicationInput(
          title: title.text.trim(),
          description: description.text.trim(),
          visibility: selected.visibility,
          dormitoryId: selected.dormitoryId,
          facultyId: selected.facultyId,
          pinnedUntil: pinnedUntil,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final user = ref.watch(myProfileProvider).value;
    final scopes = publicationScopes(user);
    final selected = scope ?? (scopes.length == 1 ? scopes.single : null);
    final cityId = user?.cityId;
    final dormitories = cityId == null
        ? const <CityPlaceOut>[]
        : ref.watch(dormitoriesProvider(cityId)).value ??
              const <CityPlaceOut>[];
    final faculties = cityId == null
        ? const <CityPlaceOut>[]
        : ref.watch(facultiesProvider(cityId)).value ?? const <CityPlaceOut>[];
    String placeName(PublicationScope value) {
      if (value.visibility == Visibility.dormitory) {
        for (final place in dormitories) {
          if (place.id == value.dormitoryId) return place.name;
        }
        return l.profileDormitory;
      }
      for (final place in faculties) {
        if (place.id == value.facultyId) return place.name;
      }
      return l.profileFaculty;
    }

    final timezone = user?.cityTimezone ?? 'UTC';
    final today = tz.TZDateTime.from(clock.now(), cityLocation(timezone));
    final firstDate = DateTime(today.year, today.month, today.day);
    final lastDate = firstDate.add(const Duration(days: 365));
    final pickerValue = pinnedUntil.isBefore(firstDate)
        ? firstDate
        : pinnedUntil;
    final editing = widget.initial != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? l.feedEditPublication : l.feedCreatePublication),
      ),
      body: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (!editing && scopes.length > 1)
              DropdownButtonFormField<PublicationScope>(
                key: const Key('publication-scope'),
                initialValue: selected,
                decoration: InputDecoration(labelText: l.feedPublicationScope),
                items: [
                  for (final value in scopes)
                    DropdownMenuItem(
                      value: value,
                      child: Text(placeName(value)),
                    ),
                ],
                validator: (value) => value == null ? l.profileChoose : null,
                onChanged: (value) => setState(() => scope = value),
              )
            else
              ListTile(
                key: const Key('publication-scope-fixed'),
                title: Text(l.feedPublicationScope),
                subtitle: Text(
                  selected == null ? l.feedNoScope : placeName(selected),
                ),
              ),
            TextFormField(
              key: const Key('publication-title'),
              controller: title,
              decoration: InputDecoration(labelText: l.listingTitle),
              validator: (value) => value == null || value.trim().isEmpty
                  ? l.signInNameRequired
                  : null,
            ),
            TextFormField(
              key: const Key('publication-description'),
              controller: description,
              decoration: InputDecoration(labelText: l.listingDescription),
              minLines: 3,
              maxLines: null,
              validator: (value) => value == null || value.trim().isEmpty
                  ? l.signInNameRequired
                  : null,
            ),
            const SizedBox(height: 16),
            Text(l.feedPinUntil, style: Theme.of(context).textTheme.titleSmall),
            CityDateTimePicker(
              value: pickerValue,
              timezone: timezone,
              city: user?.cityTimezone ?? timezone,
              firstDate: firstDate,
              lastDate: lastDate,
              onChanged: (value) => setState(() {
                pinnedUntil = value;
                pinError = null;
              }),
            ),
            if (pinError != null) Text(pinError!),
            const SizedBox(height: 16),
            ListingAction(
              label: editing ? l.listingSaveChanges : l.listingPublish,
              enabled: user != null && selected != null,
              run: () => save(selected!),
              after: () => context.pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Edit and unpin controls of a notice; shown to its author.
class PublicationActions extends ConsumerWidget {
  const PublicationActions({required this.item, super.key});

  final ListingOutput item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    return Wrap(
      spacing: 8,
      children: [
        TextButton.icon(
          key: const Key('publication-edit'),
          onPressed: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) => CreatePublicationScreen(initial: item),
            ),
          ),
          icon: const Icon(Icons.edit_outlined),
          label: Text(l.feedEditPublication),
        ),
        if (item.pinnedUntil != null)
          ListingAction(
            label: l.feedUnpin,
            run: () async {
              await ref
                  .read(campusApiProvider)
                  .listings
                  .unpinPublication(listingId: item.id);
            },
          ),
      ],
    );
  }
}
