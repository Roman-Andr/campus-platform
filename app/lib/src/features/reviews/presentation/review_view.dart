import 'package:material_ui/material_ui.dart';

import '../../../core/api/api_client.dart';
import '../../../core/l10n/l10n.dart';
import '../domain/review.dart';

/// A review as it is shown: its own title, the author when known, the stars,
/// the ready-made tags, the text, the time and the answer when there is one.
class ReviewView extends StatelessWidget {
  const ReviewView({
    required this.review,
    required this.cityTime,
    this.title,
    this.showOwner = false,
    super.key,
  });

  final ReviewOutput review;

  /// Formats an instant in the city of the listing (#44).
  final String Function(DateTime instant) cityTime;

  /// Heading above the review; none when the screen already names it.
  final String? title;

  /// Whether the name of the author is shown: the review about the viewer
  /// comes from the other side, whose name is not always known locally.
  final bool showOwner;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final reply = reviewReplyOf(review);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title case final title?)
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            if (showOwner) Text(review.authorName),
            Row(
              children: [
                for (var star = 1; star <= 5; star++)
                  Icon(
                    star <= review.rating ? Icons.star : Icons.star_border,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                const SizedBox(width: 8),
                Text(l.reviewRatingOf(review.rating)),
              ],
            ),
            if (review.tags.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final name in reviewTagNames(l, review.tags))
                    Chip(
                      label: Text(name),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              )
            else
              Text(l.reviewTagsNone),
            if (review.text case final text?) Text(text),
            if (review.hidden)
              Text(
                l.reviewHiddenByModerator,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(cityTime(review.createdAt)),
            ),
            if (reply != null) ReviewReplyView(reply: reply),
          ],
        ),
      ),
    );
  }
}

/// The single public answer of the addressee of a review.
class ReviewReplyView extends StatelessWidget {
  const ReviewReplyView({required this.reply, super.key});

  final ReviewReplyOutput reply;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Padding(
      key: const Key('review-reply'),
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.reviewReplyBy(reply.authorName),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(reply.text),
        ],
      ),
    );
  }
}
