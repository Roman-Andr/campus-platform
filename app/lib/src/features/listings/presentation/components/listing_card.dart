import 'package:material_ui/material_ui.dart';

import '../../../../core/design_system/foundations/tokens.dart';
import '../../../../core/design_system/patterns/patterns.dart';
import '../view_data/listing_card_data.dart';

class ListingHeader extends StatelessWidget {
  const ListingHeader({required this.data, super.key});
  final ListingCardData data;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(data.title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: CampusSpace.sm),
      Wrap(
        spacing: CampusSpace.sm,
        runSpacing: CampusSpace.sm,
        children: [
          StatusLabel(data: data.status),
          if (data.scope != null) ScopeBadge(label: data.scope!),
        ],
      ),
      const SizedBox(height: CampusSpace.md),
      AuthorRow(data: data.author),
    ],
  );
}

/// Card actions are slots, never inferred from listing kind, role or status.
class ListingCard extends StatelessWidget {
  const ListingCard({
    required this.data,
    this.onOpen,
    this.actions = const [],
    super.key,
  });
  final ListingCardData data;
  final VoidCallback? onOpen;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onOpen,
          child: Padding(
            padding: CampusSpace.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?data.photo,
                ListingHeader(data: data),
                if (data.summary != null)
                  Padding(
                    padding: const EdgeInsets.only(top: CampusSpace.sm),
                    child: Text(data.summary!),
                  ),
              ],
            ),
          ),
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: CampusSpace.page,
            child: Wrap(
              spacing: CampusSpace.sm,
              runSpacing: CampusSpace.sm,
              children: actions,
            ),
          ),
      ],
    ),
  );
}
