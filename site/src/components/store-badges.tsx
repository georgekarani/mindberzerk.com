/* eslint-disable @next/next/no-img-element -- the stores serve their own badge artwork; it is linked as published, never optimised or redrawn */
import { appStoreUrl, playUrl } from '@/lib/catalog/links';
import type { AppEntry } from '@/lib/catalog/types';

/**
 * The official Google Play and App Store badges, loaded from each store's own
 * badge service so the artwork is always the current approved version. Only a
 * store the app is actually on gets a badge.
 *
 * Google's PNG carries a transparent margin around the badge; the negative
 * margin trims it so both badges sit on the same baseline at the same height.
 */

export const PLAY_BADGE_SRC = 'https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png';
/** Apple's black badge for light grounds, its white badge for dark ones. */
const appStoreBadgeSrc = (onDark: boolean) =>
  `https://toolbox.marketingtools.apple.com/api/v2/badges/download-on-the-app-store/${onDark ? 'white' : 'black'}/en-us`;

/** Visible badge height in px; both artworks are scaled to it. */
const HEIGHTS = { md: 54, sm: 42 } as const;
type BadgeSize = keyof typeof HEIGHTS;

export function PlayBadge({ href, appName, size = 'md' }: { href: string; appName: string; size?: BadgeSize }) {
  const H = HEIGHTS[size];
  return (
    <a href={href} className="inline-block transition-opacity hover:opacity-85" aria-label={`Get ${appName} on Google Play`}>
      {/* 646x250 artwork; the badge itself is 564x168, centred. */}
      <img src={PLAY_BADGE_SRC} alt="Get it on Google Play" width={Math.round(H * 3.845)} height={Math.round(H * 1.49)} style={{ margin: `${-Math.round(H * 0.245)}px ${-Math.round(H * 0.25)}px` }} />
    </a>
  );
}

export function AppStoreBadge({ href, appName, size = 'md', onDark = false }: { href: string; appName: string; size?: BadgeSize; onDark?: boolean }) {
  const H = HEIGHTS[size];
  return (
    <a href={href} className="inline-block transition-opacity hover:opacity-85" aria-label={`Download ${appName} on the App Store`}>
      <img src={appStoreBadgeSrc(onDark)} alt="Download on the App Store" width={Math.round(H * 3)} height={H} />
    </a>
  );
}

export function StoreBadges({ app, size = 'md', onDark = false }: { app: AppEntry; size?: BadgeSize; onDark?: boolean }) {
  const play = playUrl(app);
  const ios = appStoreUrl(app);
  if (!play && !ios) return null;
  return (
    <div className="flex flex-wrap items-center gap-3">
      {play ? <PlayBadge href={play} appName={app.name} size={size} /> : null}
      {ios ? <AppStoreBadge href={ios} appName={app.name} size={size} onDark={onDark} /> : null}
    </div>
  );
}
