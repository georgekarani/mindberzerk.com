import { appStoreUrl, playUrl } from '@/lib/catalog/links';
import type { AppEntry } from '@/lib/catalog/types';

/**
 * Play and App Store badges, drawn rather than bitmap so they stay sharp and
 * cost no requests. Only a store the app is actually on gets a badge.
 */

function PlayGlyph() {
  return (
    <svg width="24" height="26" viewBox="0 0 26 28" aria-hidden="true">
      <path d="M1 1l14 13L1 27z" fill="#00D7FE" />
      <path d="M1 1l18 10-4 3z" fill="#00F076" />
      <path d="M1 27l18-10-4-3z" fill="#FF3A44" />
      <path d="M19 11l6 3-6 3-4-3z" fill="#FFD400" />
    </svg>
  );
}

function AppleGlyph() {
  return (
    <svg width="22" height="26" viewBox="0 0 24 28" fill="#fff" aria-hidden="true">
      <path d="M19.6 14.9c0-3 2.5-4.5 2.6-4.6-1.4-2.1-3.6-2.4-4.4-2.4-1.9-.2-3.6 1.1-4.6 1.1-.9 0-2.4-1.1-4-1-2 0-3.9 1.2-5 3-2.1 3.7-.5 9.2 1.5 12.2 1 1.5 2.2 3.1 3.8 3 1.5-.1 2.1-1 4-1 1.8 0 2.4 1 4 1 1.6 0 2.7-1.5 3.7-3 1.2-1.7 1.6-3.3 1.7-3.4-.1 0-3.3-1.3-3.3-4.9zM16.6 6c.8-1 1.4-2.4 1.2-3.8-1.2.1-2.6.8-3.5 1.8-.8.9-1.4 2.3-1.2 3.7 1.3.1 2.7-.7 3.5-1.7z" />
    </svg>
  );
}

const BADGE =
  'inline-flex h-14 items-center gap-3 rounded-xl border border-[#5a5a5a] bg-black pl-4 pr-5 text-white transition-opacity hover:opacity-85';

export function StoreBadges({ app }: { app: AppEntry }) {
  const play = playUrl(app);
  const ios = appStoreUrl(app);
  if (!play && !ios) return null;
  return (
    <div className="flex flex-wrap gap-3">
      {play ? (
        <a href={play} className={BADGE} aria-label={`Get ${app.name} on Google Play`}>
          <PlayGlyph />
          <span className="flex flex-col leading-[1.1]">
            <span className="text-[10px] tracking-[0.04em]">GET IT ON</span>
            <span className="text-[19px] font-semibold">Google Play</span>
          </span>
        </a>
      ) : null}
      {ios ? (
        <a href={ios} className={BADGE} aria-label={`Download ${app.name} on the App Store`}>
          <AppleGlyph />
          <span className="flex flex-col leading-[1.1]">
            <span className="text-[10px]">Download on the</span>
            <span className="text-[19px] font-semibold">App Store</span>
          </span>
        </a>
      ) : null}
    </div>
  );
}
