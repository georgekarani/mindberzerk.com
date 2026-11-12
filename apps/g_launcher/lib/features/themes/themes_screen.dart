import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:g_launcher/i18n/i18n.dart';

import '../../data/billing/bundle_offer.dart';
import '../../data/billing/entitlements.dart';
import '../../data/cdn/pack_auto_update.dart';
import '../../data/cdn/pack_repository.dart';
import '../../design/components/components.dart';
import '../../design/tokens/typography.dart';
import 'store_preview.dart';
import 'store_shots.dart';
import 'theme_actions.dart';
import 'theme_catalog.dart';
import 'theme_detail_screen.dart';

/// The theme storefront. A header, a 2-col grid of mini-desktop preview cards,
/// and a "more" list of themes that arrive over the CDN.
///
/// This screen's chrome is now the ACTIVE theme's (Phase B, B2): the frame,
/// cards, tags and buttons read the derived chrome via [ChromeScope], so the
/// gallery is dressed in whatever distro is applied — the same rule as Settings.
/// This reverses the earlier "neutral house chrome" decision. The mini-desktop
/// PREVIEWS are the deliberate exception: each paints a specific distro from
/// [ThemePreviewSpec] catalog data (colours and its mono labels), independent of
/// the active theme, because a preview must depict the distro it advertises, not
/// the one you're currently running.
///
/// **PHASE C: the CDN registry landed, so this is now live.** Tapping a card
/// does whatever its [CardStatus] says: apply, download, update, buy, or tell
/// the user to update the app. Nothing is faked any more.
///
/// The one rule that survived from the honest-placeholder era and still
/// matters: **an action that cannot succeed must not present as a button.** A
/// `requiresAppUpdate` card showing Get would leave someone tapping at a
/// download that never arrives and concluding the app is broken, which is
/// exactly the failure the old "coming soon" message existed to avoid. So it
/// draws its own label instead.
///
/// The catalogue is read from the CACHED index, so this screen opens instantly
/// and works offline; a refresh runs in the background on open and re-reads
/// only if something actually changed.
/// Which slice of the catalogue the storefront is showing.
///
/// ─── WHY THERE IS NO "POPULAR" ──────────────────────────────────────────────
///
/// It was asked for and it cannot be built honestly yet. Nothing counts distro
/// installs: that is Phase 6 and it is blocked on the launcher emitting
/// `app_present` and on BigQuery export. A tab labelled Popular would be
/// ordered by nothing, and on a STORE screen that is not a harmless placeholder
/// but an implicit claim that other people bought these.
///
/// [paid] is the honest tab that works today, derived from `sku != null` with
/// no new data, and it is the same axis the admin panel already filters on.
///
/// The other honest version is Featured, an authored flag set per distro in the
/// panel. It is editorial rather than measured, which is fine and true, but it
/// needs the signed index to carry the flag, so it would list only bundled
/// distros until that lands. Swapping this arm for it is one filter and one
/// label.
/// The storefront filters.
///
/// ─── TWO SLICES THAT DO NOT OVERLAP ─────────────────────────────────────────
///
/// These were Installed and Paid, and a distro you had bought was both, so the
/// counts read "Installed 15, Paid 12" on a 15-distro catalogue and Paid kept
/// listing things that were already yours. Ownership is the question a buyer
/// is actually asking, so the split is by that: what you can use now (free,
/// bought or covered by a bundle, on the phone or one tap from it) and what
/// still costs money. Every card is in exactly one of the two.
enum ThemeTab {
  all,
  yours,
  toBuy;

  String get labelKey => switch (this) {
        ThemeTab.all => 'themes.tab.all',
        ThemeTab.yours => 'themes.tab.yours',
        ThemeTab.toBuy => 'themes.tab.toBuy',
      };

  /// Still costs money. A paid distro that needs a newer app is not yours
  /// yet either (its status says "update the app", not "owned"), so it waits
  /// under To buy with the locked ones rather than sitting among Yours.
  static bool _forSale(ThemeCard c) =>
      c.status == CardStatus.locked ||
      (c.status == CardStatus.requiresAppUpdate && c.sku != null);

  bool matches(ThemeCard c) => switch (this) {
        ThemeTab.all => true,
        ThemeTab.yours => !_forSale(c),
        ThemeTab.toBuy => _forSale(c),
      };
}

/// AUTO-DISPOSES, so closing the storefront resets it to All.
///
/// Deliberate: a tab is a filter you applied a moment ago, not a preference.
/// Coming back days later to a Paid-only list, having forgotten you narrowed
/// it, reads as distros having disappeared.
final themeTabProvider = StateProvider.autoDispose<ThemeTab>(
  (ref) => ThemeTab.all,
);

class ThemesScreen extends ConsumerWidget {
  const ThemesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ─── .value, NOT asData, AND THAT IS THE FLICKER FIX ─────────────────
    //
    // `asData` is null for `AsyncLoading`, and Riverpod produces exactly that
    // state on every refresh, carrying the previous value with it, which
    // `asData` then discards. `AsyncValue.value` is nullable in Riverpod 3 and
    // returns that retained value; `valueOrNull` was the 2.x name and is gone. `PackActions.install` invalidates the catalogue
    // after each pack, so opening the store with a dozen stale packs rendered
    // an EMPTY grid a dozen times: the cards vanished and came back, over and
    // over, which is the flashing in the review.
    //
    // So a reload is invisible and the grid only changes when its contents
    // genuinely do.
    final cards = ref.watch(themeCatalogProvider).value ?? const <ThemeCard>[];
    final progress = ref.watch(packProgressProvider);

    // THE FETCH. `catalogueProvider` is the cached index and never hits the
    // network; this is the one thing that asks the CDN whether anything is new.
    // Watched rather than read so the grid rebuilds when the answer lands, and
    // fired once per app run — see `catalogueRefreshProvider`.
    ref.watch(catalogueRefreshProvider);
    // Watched here so a price arriving from Play repaints the whole grid at
    // once, rather than each card independently re-reading a provider family.
    ref.watch(ownedSkusProvider);

    final tab = ref.watch(themeTabProvider);

    // Filtered for display only. `cards` stays whole for the counts on the
    // tabs, which have to say how many are in each slice rather than how many
    // are in the slice you are already looking at.
    final shown = [
      for (final c in cards)
        if (tab.matches(c)) c,
    ];

    // Active is decided in `theme_actions.dart` now, because the detail page
    // has to ask the same question and two copies of an id-fallback rule is one
    // copy too many.
    bool isActive(ThemeCard c) => themeCardIsActive(ref, c);

    /// What a tap on the card BODY does.
    ///
    /// ─── ROUTED BY STATUS, NOT UNIFORMLY ──────────────────────────────────
    ///
    /// Anything already on the device applies on one tap, as it always has.
    /// Switching distros is the frequent action on this screen, and the detail
    /// page has nothing to tell an owner that Settings cannot, so growing it a
    /// tap would be the wrong trade for the common case.
    ///
    /// `locked` and `available` open the page instead. Those are the two states
    /// where a tap COMMITS: one opens Play's payment sheet, the other starts a
    /// download measured in megabytes, and until now both did it with no screen
    /// in between saying what the distro is or what is in it.
    ///
    /// `requiresAppUpdate` deliberately stays on the storefront. Its message is
    /// one line and there is no action behind it, so a page whose only button
    /// is disabled would be a longer way to say the same thing.
    ///
    /// A consequence worth knowing while testing: on a device where every
    /// distro is already installed, nothing routes to the detail page at all.
    void onCardTap(ThemeCard c) {
      final opensDetail = !isActive(c) &&
          (c.status == CardStatus.locked || c.status == CardStatus.available);

      if (!opensDetail) {
        // Deliberately not awaited: this is a tap handler, and the action
        // already reports everything it does.
        unawaited(runThemeCardAction(context, ref, c));
        return;
      }

      Navigator.of(context).push(
        MaterialPageRoute<void>(
          // packIdOrSpec, never `id`: they differ on the bundled distros and
          // the pack pipeline knows only the second.
          //
          // NO `onAction` ANY MORE. The page used to take the flow as a
          // callback and pop itself before running it, so Play's sheet opened
          // over this list instead of over the page the user was reading. It
          // now calls `runThemeCardAction` with its OWN context and stays put.
          builder: (_) => ThemeDetailScreen(packId: c.packIdOrSpec),
        ),
      );
    }

    return ThemedScaffold(
      // Pull to refresh. The automatic fetch above runs once per app run, which
      // is right for the common case and useless in the one that matters: you
      // have just published something and want it NOW. `refresh()` sends an
      // ETag, so a pull that finds nothing new costs a 304 with no body.
      //
      // Colours passed explicitly because RefreshIndicator otherwise reads
      // `Theme.of`, which this screen deliberately does not have — see
      // no_constants.sh's settings scope.
      body: RefreshIndicator(
        color: ChromeScope.of(context).colors.accent,
        backgroundColor: ChromeScope.of(context).colors.line,
        // ─── A PULL UPDATES TOO ───────────────────────────────────────
        //
        // This called `refresh()` alone, which fetched the index and left any
        // pack that had just gone stale sitting there saying Update.
        //
        // I originally exempted a manual pull on the reasoning that it is
        // someone asking to SEE the catalogue rather than to download fifteen
        // packs. That is the wrong reading: a pull is a person saying "check
        // for changes", and finding one and then not acting on it is the
        // launcher deciding for them. Every route to a fetch now has the same
        // consequence, which is also one fewer rule to remember.
        onRefresh: () => refreshAndAutoUpdate(
          ref.read(packActionsProvider),
          ref.read(packAutoUpdaterProvider),
        ),
        // ─── SLIVERS, AND IT WAS A ListView OF A Column ────────────────────
        //
        // A Column builds every child the moment it is laid out. So all thirty
        // cards mounted on open, all thirty `_CardPreview`s watched their
        // provider in the same frame, and thirty peeks went onto native's
        // single-threaded executor at once. The card at the bottom of the list
        // waited behind twenty-nine manifest fetches for a picture nobody had
        // scrolled to, on a connection somebody is paying for by the megabyte.
        //
        // The ListView around it did not help: `ListView(children: [...])` is
        // `SliverChildListDelegate`, which also builds everything. Laziness
        // needs a BUILDER, and a builder needs the cards to be their own sliver
        // rather than one widget in a list.
        //
        // ─── AND THIS IS WHY THERE IS NO RASTER CACHE ──────────────────────
        //
        // The plan said cache each card's picture, keyed on packId, version and
        // wallpaper. That was aimed at the wrong cost. Painting a DevicePreview
        // is a handful of DecoratedBoxes; the expensive part was thirty network
        // round trips, and lazily building means about five previews exist at
        // any moment. A cache would add a keying rule to keep correct across
        // republishes for a saving that no longer exists.
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: EdgeInsets.only(
                top: MediaQuery.viewPaddingOf(context).top,
              ),
              sliver: const SliverToBoxAdapter(child: _Header()),
            ),
            SliverToBoxAdapter(child: _Tabs(cards: cards)),

            // The all-distros offer, above the list it would replace. Hidden
            // on Yours, where nothing is for sale.
            if (tab != ThemeTab.yours)
              SliverToBoxAdapter(child: _BundleBanner(cards: cards)),

            // A filter can legitimately be empty: Paid before any paid distro
            // is published, for one. Says so rather than showing a blank page,
            // which is indistinguishable from a catalogue that failed to load.
            if (shown.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 28, 16, 28),
                  child: Text(
                    // Literal, like every other string on this screen. Three
                    // `context.t` keys here would be the only localised text in
                    // the file and would need keys that do not exist yet; the
                    // screen localises as a unit or not at all.
                    context.t(switch (tab) {
                      ThemeTab.yours => 'themes.empty.yours',
                      ThemeTab.toBuy => 'themes.empty.toBuy',
                      ThemeTab.all => 'themes.empty.all',
                    }),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ChromeScope.of(context).colors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ),

            // ─── ONE COLUMN, AND SIZED BY ITS CONTENT ─────────────────────
            //
            // This was a two-up grid of 150dp cells, which gives a preview
            // about 100dp tall and 150 wide. At that size a mini desktop can
            // show a colour and very little else, so every CDN distro read as a
            // coloured rectangle with a price beside it, and the distro being
            // charged for was the emptiest thing on the screen.
            //
            // A full-width card gives the preview 152dp of height and the whole
            // width, which is enough to draw a panel, a dock, windows and
            // icons: the distro's signature rather than its palette. It also
            // leaves room under the meta row for what the card is actually for,
            // which is saying what this distro DOES.
            //
            // ─── AND WHY IT IS NOT A GridView, AND NO LONGER A Column ──────
            //
            // It was a GridView with a fixed `mainAxisExtent`, on the reasoning
            // that cards of differing heights make a list that jumps about as
            // the catalogue loads. That reasoning was wrong the moment feature
            // rows existed: the three bundled distros carry two rows and a CDN
            // pack carries none, so the cards ALWAYS differ. Fixing the height
            // did not make them uniform, it forced variable text into a
            // constant box, and it overflowed by 3dp at the default font size.
            // At a system text scale of 1.3 it would have overflowed by thirty.
            //
            // A self-sizing card has no such cliff. The preview stays fixed at
            // 152 so every card shows the same size picture; everything below
            // takes the height its text actually needs.
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.builder(
                itemCount: shown.length,
                // KEYED ON THE PACK, so the sliver's recycling cannot hand a
                // card's element to a different distro as the list is filtered.
                // Without it, switching tabs would reuse the element that
                // already holds a peek subscription for another pack, and the
                // picture would belong to whichever card previously sat in that
                // slot.
                itemBuilder: (context, i) => Padding(
                  key: ValueKey(shown[i].packIdOrSpec),
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 26),
                  child: _ThemeCard(
                    card: shown[i],
                    active: isActive(shown[i]),
                    // null when nothing is in flight for this pack, which is
                    // the normal case; the card only grows a bar while it is
                    // downloading.
                    progress: progress[shown[i].packIdOrSpec],
                    onTap: () => onCardTap(shown[i]),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Card
// ─────────────────────────────────────────────────────────────────────────────

/// The filter strip.
///
/// Counts come from the WHOLE list, not the filtered one, because the number on
/// a tab has to say how many are in that slice rather than how many are in the
/// slice already on screen. A Paid tab reading 0 while showing nine paid
/// distros is the version of this that gets shipped by accident.
class _Tabs extends ConsumerWidget {
  const _Tabs({required this.cards});

  final List<ThemeCard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeTabProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: [
          for (final t in ThemeTab.values) ...[
            if (t != ThemeTab.values.first) const SizedBox(width: 8),
            _TabChip(
              label: context.t(t.labelKey),
              // No count on All: it is the total, and a number there is the one
              // figure on the strip that tells you nothing you can act on.
              count: t == ThemeTab.all ? null : cards.where(t.matches).length,
              selected: t == current,
              onTap: () => ref.read(themeTabProvider.notifier).state = t,
            ),
          ],
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int? count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;

    return Material(
      color: selected ? c.accent : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: selected ? c.accent : c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: selected ? c.onAccent : c.text,
                ),
              ),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: selected
                        ? c.onAccent.withValues(alpha: 0.75)
                        : c.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    this.progress,
    required this.card,
    required this.active,
    required this.onTap,
  });

  final ThemeCard card;
  final bool active;
  final VoidCallback onTap;

  /// Download progress, null when nothing is in flight for this pack.
  final double? progress;

  /// Height of the picture. Three portrait screenshots at this height fit a
  /// 360dp screen with the page gutters, so the common card never scrolls.
  static const double pictureHeight = 208;

  /// Full bleed: the picture is the card. No surface, no border and no feature
  /// text; the name and one action sit under it, and everything that explains
  /// the distro lives on its page.
  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    final c = d.colors;
    return Semantics(
      button: true,
      selected: active,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: pictureHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _CardPreview(card: card),
                  if (progress != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: ThemedProgress.linear(
                        value: progress! <= 0 ? null : progress,
                        accent: card.preview.accent,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 10, 0, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          card.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (card.subtitle.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            card.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: c.textMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  _Trailing(card: card, active: active),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The card's picture: the distro, rendered from its own theme.json.
///
/// ─── THREE PANES, AND THE CALL SITE DID NOT HAVE TO CHANGE ──────────────────
///
/// [StorePreview] defaults to [kStoreCardModes], so a card gets desktop, drawer
/// and folder without saying so, and the detail hero is the one that overrides
/// it with the single mode its strip has selected. The default belongs to the
/// card because the card is the thing that cannot ask.
///
/// ─── IT FALLS BACK, AND THE FALLBACK IS THE POINT ───────────────────────────
///
/// [StorePreview] answers with the peeked distro when it has one and with
/// whatever is passed as the fallback when it does not, which happens on every
/// cold open before the peek returns, offline, and whenever a signature fails.
///
/// The fallback is `ThemePreview` from the signed index's preview block, which
/// is exactly what this card drew before any of this existed. That is why
/// `ThemePreviewSpec` and its twelve-arm renderer stay: they are the offline
/// floor, not legacy. A storefront rendering blank rectangles on a plane is a
/// bug report.
///
/// ─── AND IT DOES NOT SPIN ───────────────────────────────────────────────────
///
/// No shimmer, no placeholder, no progress. A card showing a loading state and
/// then a picture would flash on every open for a change the user did not ask
/// for, and this screen has just finished having its flicker removed. The index
/// preview is a real picture; it is simply a less specific one, and replacing it
/// when a better one arrives is invisible in the good case and harmless in the
/// bad one.
class _CardPreview extends ConsumerWidget {
  const _CardPreview({required this.card});

  final ThemeCard card;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Real screenshots first; the drawn distro only when the pack has none or
    // they cannot be resolved yet.
    final shots = ref
            .watch(
              storeShotsProvider(
                (packId: card.packIdOrSpec, version: card.remoteVersion),
              ),
            )
            .value ??
        const <ImageProvider>[];
    if (shots.isNotEmpty) return StoreShotRow(shots: shots);

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: StorePreview(
        card: card,
        fallback: ThemePreview(card.preview),
      ),
    );
  }
}

/// The right-hand meta element: the active check, a price, or the DE tag.
///
/// ─── THE PRO BADGE IS GONE, AND IT WAS WRONG TWICE ──────────────────────────
///
/// There is no Pro tier. Every launcher FEATURE is free — the boot-log editor,
/// scheduled switching, the cube transition, all of it — and what is sold is
/// whole distros and icon packs. A badge reading "Pro" was the last piece of UI
/// still describing a model that was dropped, and it was the only word on this
/// screen implying some capability was withheld.
///
/// It was also useless as an affordance. "Pro" tells you a thing costs money and
/// refuses to say how much, so the only way to find out was to tap, get Play's
/// sheet, and read the number there. A price is the same amount of pixels and
/// answers the question.
///
/// A ConsumerWidget now, because the price comes from Play through
/// `productPriceProvider` — a LOCALISED string Play formats for the user's
/// country and currency, never a number formatted here, which would be wrong in
/// every market this launcher actually targets.
class _Trailing extends ConsumerWidget {
  const _Trailing({required this.card, required this.active});

  final ThemeCard card;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ChromeScope.of(context).colors;

    // ORDER MATTERS, and this is the order:
    //   active > requiresAppUpdate > update > locked > available > tag
    //
    // requiresAppUpdate sits above everything except the active ring because it
    // is the one state where every other affordance would be a lie. A Pro badge
    // on a theme this build cannot run invites a purchase that installs
    // nothing, which is the worst outcome on this screen.
    if (!active && card.status == CardStatus.requiresAppUpdate) {
      return _MiniLabel(context.t('themes.updateApp'));
    }
    if (!active && card.status == CardStatus.updateAvailable) {
      return _MiniLabel(context.t('themes.update'));
    }
    if (!active && card.status == CardStatus.locked) {
      // The price when Play has answered, the word Buy when it has not.
      //
      // Null is the ordinary state in three real cases: the build is not on a
      // Play track yet, the device has no Play Services, or the product does not
      // exist in the console. All three render a card with no price, so a
      // fallback word is what stops the trailing slot going blank and reading as
      // a card that failed to load.
      return _MiniLabel(
        ref.watch(productPriceProvider(card.sku)) ?? context.t('themes.buy'),
        filled: true,
      );
    }
    if (!active && card.status == CardStatus.available) {
      return _MiniLabel(context.t('themes.get'));
    }

    // THE ACTIVE CARD SHOWS ITS UPDATE. Every branch above is `!active`
    // guarded, which meant the distro someone actually runs was the one card
    // that could never say a newer version exists - the user had to switch
    // distros just to see the chip. Tap already pulls it; now the eye is told.
    if (active &&
        (card.status == CardStatus.updateAvailable ||
            card.status == CardStatus.available)) {
      return _MiniLabel(context.t('themes.update'));
    }

    if (active) {
      return Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: c.accent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(Icons.check, size: 11, color: c.onAccent),
      );
    }
    // ─── EVERYTHING LEFT IS ON THE DEVICE AND NOT WORN ────────────────────
    //
    // Bundled or installed, not active, nothing to buy and nothing to fetch.
    // The only thing a tap can do here is apply it, so the slot says so.
    //
    // ─── THIS SLOT USED TO DRAW THE DE TAG, AND MOSTLY DREW NOTHING ───────
    //
    // It read `card.tag`, which `_cardFromPack` sets to null on every CDN
    // entry, so eleven of fourteen installed cards rendered an empty corner:
    // no price, no action, no chip. A card with a picture, a name and a blank
    // third element reads as one that failed to load rather than one that is
    // simply ready.
    //
    // The three cards that DID have a tag lost nothing worth keeping. Ubuntu's
    // said GNOME directly above a subtitle reading `24.04 · GNOME`, which is
    // the same duplication `_cardFromPack` removed the tag for in the first
    // place. `ThemeCard.tag` is now read by nothing; it is left on the class
    // rather than deleted in a pass about something else.
    //
    // Word, not an icon, for the reason [_MiniLabel] gives: Apply, Get and
    // Update are three different promises and a single glyph would collapse
    // them into the ambiguity this whole state machine exists to remove.
    return _MiniLabel(context.t('themes.apply'));
  }
}

/// A short coloured word in the trailing slot: Get, Update, Update app.
///
/// Text rather than an icon because these three mean genuinely different things
/// and a download glyph would collapse them into one, which is the ambiguity
/// this whole state machine exists to remove.
class _MiniLabel extends StatelessWidget {
  const _MiniLabel(this.text, {this.filled = false});

  final String text;

  /// Accent fill for the one state that costs money, so a price stands out
  /// from Get, Apply and Update.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? c.accent : c.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: filled ? c.onAccent : c.text,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The mini-desktop preview. Pure decoration driven by ThemePreviewSpec.
// ─────────────────────────────────────────────────────────────────────────────

/// Where a preview's bar sits, if it has one.
///
/// Three values because there are three truths: seven of fifteen distros were
/// drawn with a top bar they do not have, and four of those have one along the
/// bottom instead.
enum _Bar { top, bottom, none }

class ThemePreview extends StatelessWidget {
  const ThemePreview(this.spec, {super.key});

  final ThemePreviewSpec spec;

  static const _white55 = Color(0x8CFFFFFF);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: spec.radial
            ? RadialGradient(
                center: const Alignment(0.56, -0.76), // 78% 12%
                radius: 1.1,
                colors: spec.bg,
              )
            : LinearGradient(
                begin: Alignment.topRight, // ~160deg
                end: Alignment.bottomLeft,
                colors: spec.bg,
              ),
      ),
      child: Stack(
        children: [
          // ─── THE BAR IS NOT UNCONDITIONAL ANY MORE ────────────────────
          //
          // This said "every layout has one" and painted it at the top. Four
          // distros have their bar along the BOTTOM and three have none at
          // all, so for seven of fifteen the first thing the card drew was
          // wrong.
          if (_bar != _Bar.none)
            Positioned(
              left: 9,
              right: 9,
              top: _bar == _Bar.top ? 9 : null,
              bottom: _bar == _Bar.bottom ? 9 : null,
              child: Container(
                height: 7,
                decoration: BoxDecoration(
                  color: spec.bar,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ..._layout(),
        ],
      ),
    );
  }

  /// Where this layout puts its bar. See the Stack above.
  _Bar get _bar => switch (spec.layout) {
        PreviewLayout.barBottom => _Bar.bottom,
        // A phone has Android's status bar, not the launcher's, and a terminal
        // has none either. Drawing one would be the only untrue thing on those
        // two cards.
        PreviewLayout.terminal => _Bar.none,
        _ => _Bar.top,
      };

  List<Widget> _layout() {
    switch (spec.layout) {
      // ─── THE FIVE ADDED WHEN THE LAYOUT STOPPED BEING THE SHELL ───────
      //
      // Each is a variation on a shape this widget already drew, which is why
      // the fix was a derivation change rather than a new preview system.
      case PreviewLayout.dockFlat:
        return [
          Positioned(
            left: 9,
            right: 9,
            top: 26,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _tiles(18),
            ),
          ),
          // ON the edge, square where it meets. `dockBottom` floats clear of
          // it; that gap is the whole difference between Plank and a Latte
          // dock and it is visible at this size.
          Positioned(
            left: 34,
            right: 34,
            bottom: 0,
            child: Container(
              height: 12,
              decoration: BoxDecoration(
                color: spec.dockBg ?? _white55,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
            ),
          ),
        ];

      case PreviewLayout.noDock:
        // Tiles and a bar, and nothing else. The absence IS the picture.
        return [
          Positioned(
            left: 9,
            right: 9,
            top: 30,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _tiles(18),
            ),
          ),
        ];

      case PreviewLayout.barBottom:
        // The bar moved in the Stack above, so this only has to leave room at
        // the foot instead of at the head.
        return [
          Positioned(
            left: 9,
            right: 9,
            top: 14,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _tiles(18),
            ),
          ),
        ];

      case PreviewLayout.dash:
        return [
          Positioned(
            left: 9,
            right: 9,
            top: 26,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _tiles(18),
            ),
          ),
          // DASHED, because it is not there until you ask. A solid strip would
          // say the opposite of what this distro is selling.
          Positioned(
            left: 40,
            right: 40,
            bottom: 11,
            child: Container(
              height: 10,
              decoration: BoxDecoration(
                color: (spec.accent ?? _white55).withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: _white55, width: 0.8),
              ),
            ),
          ),
        ];

      case PreviewLayout.tiled:
        return [
          // Edge to edge with hairline gaps, which is what a tiling desktop
          // looks like from across a room and the one thing no other card here
          // shows.
          Positioned(
            left: 9,
            right: 9,
            top: 24,
            bottom: 11,
            child: GridView.count(
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 2,
              crossAxisSpacing: 2,
              children: [
                for (var i = 0; i < 4; i++)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: (spec.icons.isNotEmpty
                              ? spec.icons[i % spec.icons.length]
                              : _white55)
                          .withValues(alpha: 0.5),
                      border: Border.all(color: _white55, width: 0.7),
                    ),
                  ),
              ],
            ),
          ),
        ];

      case PreviewLayout.dockLeft:
        return [
          // Left dock strip with three dots; the first is the accent launcher.
          Positioned(
            left: 9,
            top: 26,
            bottom: 9,
            width: 13,
            child: Container(
              decoration: BoxDecoration(
                color: spec.dockBg,
                borderRadius: BorderRadius.circular(5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  _dot(spec.accent ?? _white55),
                  const SizedBox(height: 4),
                  _dot(_white55),
                  const SizedBox(height: 4),
                  _dot(_white55),
                ],
              ),
            ),
          ),
          Positioned(
            left: 29,
            top: 25,
            child: Row(mainAxisSize: MainAxisSize.min, children: _tiles(18)),
          ),
        ];

      case PreviewLayout.dockBottom:
        return [
          Positioned(
            left: 9,
            right: 9,
            bottom: 9,
            child: Container(
              decoration: BoxDecoration(
                color: spec.dockBg,
                borderRadius: BorderRadius.circular(5),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(children: _tiles(14)),
            ),
          ),
        ];

      case PreviewLayout.iconsCentered:
        return [
          Positioned(
            left: 9,
            right: 9,
            top: 27,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _tiles(18),
            ),
          ),
        ];

      case PreviewLayout.iconsLeft:
        return [
          Positioned(
            left: 9,
            top: 27,
            child: Row(mainAxisSize: MainAxisSize.min, children: _tiles(18)),
          ),
          if (spec.corner != null)
            Positioned(
              right: 9,
              bottom: 8,
              child: Text(
                spec.corner!,
                style: TextStyle(
                  fontFamily: GType.mono,
                  fontSize: 9,
                  color: spec.icons.isNotEmpty ? spec.icons.last : _white55,
                ),
              ),
            ),
        ];

      case PreviewLayout.dockMagnified:
        return [
          Positioned(
            left: 0,
            right: 0,
            bottom: 8,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: spec.dockBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.fromLTRB(5, 4, 5, 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  // Bottom-aligned and centre-magnified, matching the real dock:
                  // a swollen icon grows UPWARD while its feet stay on the line.
                  // Drawing them all the same size would make this preview a
                  // KDE panel with different colours.
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: _magnifiedTiles(),
                ),
              ),
            ),
          ),
        ];

      // PHASE C. A catalogue theme whose colours we do not have yet.
      //
      // A DELIBERATE BLANK, not a generic desktop. The temptation is to draw a
      // plausible dock and bar so the grid looks even, but that invents a look
      // for a theme nobody has seen, and the first thing the user does after
      // downloading is compare it to the preview that lied. An empty frame says
      // "we do not know yet", which is true and costs nothing.
      case PreviewLayout.unknown:
        return const [];

      case PreviewLayout.terminal:
        return [
          Positioned(
            left: 9,
            right: 9,
            top: 25,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '~ ❯ ',
                      style: TextStyle(
                        fontFamily: GType.mono,
                        fontSize: 10,
                        color: Color(0xFF52F088),
                      ),
                    ),
                    Container(
                        width: 6, height: 10, color: const Color(0xFF52F088)),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'firefox files',
                  style: TextStyle(
                    fontFamily: GType.mono,
                    fontSize: 10,
                    color: Color(0xFF2E7A48),
                  ),
                ),
              ],
            ),
          ),
        ];
    }
  }

  Widget _dot(Color c) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(2),
        ),
      );

  /// The magnifying dock's preview tiles: the middle one large, its neighbours
  /// tapering. Sized by hand rather than by AquaDockMetrics — this is a 120px
  /// thumbnail, not the dock, and importing the real geometry here would couple
  /// the storefront to the shell for no gain.
  List<Widget> _magnifiedTiles() {
    const sizes = <double>[10, 17, 10];
    final out = <Widget>[];
    for (var i = 0; i < spec.icons.length; i++) {
      if (i > 0) out.add(const SizedBox(width: 4));
      final size = sizes[i % sizes.length];
      out.add(
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: spec.icons[i],
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
        ),
      );
    }
    return out;
  }

  List<Widget> _tiles(double size) {
    final out = <Widget>[];
    for (var i = 0; i < spec.icons.length; i++) {
      if (i > 0) out.add(const SizedBox(width: 5));
      out.add(
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: spec.icons[i],
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      );
    }
    return out;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Headers — widgets (not inline in build) so they render UNDER the ThemedScaffold
// scope and read the live chrome instead of a house constant.
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final d = ChromeScope.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.t('themes.distros'), style: d.text.display),
        ],
      ),
    );
  }
}

/// The all-distros bundle: one row above the list.
///
/// The cards below are the pictures of what it unlocks, so the offer itself is
/// a title, one line of what is in it, and the price. Once owned it shrinks to
/// a single line saying so.
class _BundleBanner extends ConsumerWidget {
  const _BundleBanner({required this.cards});

  final List<ThemeCard> cards;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(allDistrosOfferProvider);
    if (offer == null) return const SizedBox.shrink();

    final c = ChromeScope.of(context).colors;

    if (offer.owned) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Row(
          children: [
            Icon(Icons.check, size: 16, color: c.accent),
            const SizedBox(width: 6),
            Text(
              context.t('themes.bundle.owned'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: c.accent,
              ),
            ),
          ],
        ),
      );
    }

    final distros = offer.distroCount;
    final icons = offer.iconPackCount;
    final line = distros == 0
        ? context.t('themes.bundle.everything')
        : icons == 0
            ? context.t('themes.bundle.distros', {'n': '$distros'})
            : context.t(
                'themes.bundle.distrosIcons',
                {'n': '$distros', 'icons': '$icons'},
              );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
      child: Semantics(
        button: true,
        label: offer.price == null
            ? offer.title
            : '${offer.title}, ${offer.price}',
        excludeSemantics: true,
        child: Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => unawaited(runBundlePurchase(context, ref, offer)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          offer.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          line,
                          style: TextStyle(fontSize: 12, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  _MiniLabel(
                    offer.price ?? context.t('themes.buy'),
                    filled: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
