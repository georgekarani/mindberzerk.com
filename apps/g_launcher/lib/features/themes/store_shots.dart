/// Real phone screenshots for the distro store.
///
/// A distro's theme.json may list `screenshots`, bare filenames shipped in the
/// pack (home, drawer, settings). When present the store shows them instead of
/// the drawn preview, because a drawing from theme.json is an approximation of
/// the distro and a screenshot is the distro. The drawing stays as the
/// fallback for packs without screenshots, offline, and failed loads.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/cdn/pack_preview_url.dart';
import '../../design/components/components.dart';
import 'theme_peek.dart';

/// Width over height of a phone screenshot (a 1080 x 2340 class display).
const double kShotAspect = 9 / 19.5;

/// The screenshots for one distro, as images, in display order.
///
/// Installed packs read their own files, so an owned distro shows its shots
/// offline. Everything else reads the CDN copy beside the pack's signed files.
/// Empty when the distro lists none or nothing can be resolved.
final storeShotsProvider =
    FutureProvider.family<List<ImageProvider>, PeekRequest>((ref, req) async {
  final peeked = await ref.watch(peekedThemeProvider(req).future);
  final names = peeked?.spec.screenshots ?? const <String>[];
  if (peeked == null || names.isEmpty) return const [];

  if (peeked.assetsOnDisk) {
    return [
      for (final name in names)
        if (peeked.spec.source.asset(name).existsSync)
          peeked.spec.source.asset(name).image,
    ];
  }

  final folder = await ref.watch(packCdnFolderProvider(req.packId).future);
  if (folder == null) return const [];
  return [
    for (final name in names) NetworkImage(folder + name.split('/').last),
  ];
});

/// One screenshot with rounded corners, the surface colour while it loads,
/// and the same colour if it fails, so a missing file reads as an empty slot
/// rather than a broken image.
class StoreShot extends StatelessWidget {
  const StoreShot({super.key, required this.image, this.radius = 12});

  final ImageProvider image;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: kShotAspect,
        child: DecoratedBox(
          decoration: BoxDecoration(color: c.surface),
          child: Image(
            image: image,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// A card's picture: the screenshots side by side at a fixed height.
///
/// Scrolls sideways only when they do not fit, which on a phone in portrait
/// means four or more.
class StoreShotRow extends StatelessWidget {
  const StoreShotRow({super.key, required this.shots, this.gap = 6});

  final List<ImageProvider> shots;
  final double gap;

  @override
  Widget build(BuildContext context) => ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: shots.length,
        separatorBuilder: (_, __) => SizedBox(width: gap),
        itemBuilder: (_, i) => StoreShot(image: shots[i]),
      );
}

/// The distro page's hero: one screenshot at a time, full height, swiped
/// sideways, with the neighbours peeking in and dots underneath.
class StoreShotPager extends StatefulWidget {
  const StoreShotPager({
    super.key,
    required this.shots,
    required this.height,
  });

  final List<ImageProvider> shots;
  final double height;

  @override
  State<StoreShotPager> createState() => _StoreShotPagerState();
}

class _StoreShotPagerState extends State<StoreShotPager> {
  /// The fraction of the width one page takes: a screenshot at [height] is
  /// narrower than the screen, so the next one shows at the edge and invites
  /// the swipe.
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.62);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = ChromeScope.of(context).colors;
    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.shots.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                child: StoreShot(image: widget.shots[i], radius: 20),
              ),
            ),
          ),
        ),
        if (widget.shots.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.shots.length; i++)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: i == _page ? 14 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 2.5),
                    decoration: BoxDecoration(
                      color: i == _page ? c.text : c.line,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
