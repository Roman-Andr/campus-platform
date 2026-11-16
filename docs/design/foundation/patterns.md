# Patterns and screen composition (#381)

Patterns are display composition, not domain workflows. Import the barrel
`core/design_system/patterns/patterns.dart`. Shared patterns never import
features/API/providers. Feature view data and mappers can depend on their own
domain and localization; they must not load or mutate anything.

| Composition | Named consumers/contracts |
| --- | --- |
| AuthorRow + nullable AuthorViewData | Listing details/cards (#397–399), participant/review rows (#401/#404). Redacted name suppresses image and private detail |
| ScopeBadge, StatusLabel + StatusViewData | Publications/audience (#399), listing feed/cards (#385/#397), interaction summary (#401). Labels/tone provided; unknown → neutral, no inferred actions |
| DeadlineBanner | Place offer (#400), interaction/event deadlines (#401/#398). Server time/policy stays in application |
| PhotoStrip/PhotoTile + PhotoStage | Thing editor (#394), service/publication editors (#395/#396). Upload/processing/retry transitions stay in existing photo pipeline |
| FormSection + EditorScaffold | All editor families (#394–396); visibility/audience/description are composed sections, not one mega-form |
| TimelineEntry | Agreement chronology (#401), event attendance/history (#402); no new lifecycle or payment calculations |
| BottomActions | Editors, detail confirmations and agreement screens; wraps and honors safe area, supplied through Scaffold.bottomNavigationBar |
| InlineNotice/StatePanel | Shared retained-content offline/conflict/retry versus initial-load/empty/error states |

`features/listings/presentation/view_data/ListingCardData` belongs to listings.
`ListingCard` and `ListingHeader` live in that feature and use shared primitives.
`listingStatusData` reuses the existing status-label mapper, with neutral
unknown fallback. UI never grants reservation/queue/payment/QR permissions.
Actions are child slots and callbacks supplied only after existing application
policy allows them. A photo is an optional UI slot, not a URL fetch. Do not
turn the shared card into a switch over eight domain kinds.

The catalog demonstrates giveaway and help cards with the same contract,
redacted/unknown/no-photo, photo stages, timeline/offer/conflict, and a small
editor in `catalog/pattern_stories.dart`. These are confirmed future consumer
contracts; no mass screen migration is included. Catalog copy is synthetic.

## Reference recipe for the next screen

1. Route/container watches the existing feature controller and policy.
2. Map data to a feature-owned immutable view-data object. Keep redacted fields
   null, unknown labels neutral, server-derived actions explicit.
3. Build EditorScaffold with FormSection children (description, PhotoStrip,
   authorized audience selector, feature-specific fields). Use native fields.
4. Place BusyAction in actions, binding busy to the actual request and
   onPressed to the existing controller command. Never await motion first.
5. Add InlineNotice above retained content for offline/conflict/partial error.
   Use StatePanel only when there is no useful content.
6. Add Widgetbook fixtures with the same view data and stub callbacks; no
   production providers. `ExampleEditor` is an executable small composition.
7. Test text/focus/draft preservation, errors, callbacks, large RU/EN text,
   keyboard/Back and route guards. Run analyzer, relevant feature behavior,
   design-system tests, and localization checks. Review applicable goldens.

No domain logic, generated API, cache/queue or authorization is migrated by
these patterns. Avoid editing central router, ARB or foundations in parallel
screen PRs without coordinating ownership; see the final handoff guide.
