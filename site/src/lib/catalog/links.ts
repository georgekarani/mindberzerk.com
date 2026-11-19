import type { AppEntry, Platform } from './types';

/** Store and page links, derived from ids so a stored URL can never rot. */

export function playUrl(app: AppEntry): string | null {
  return app.playPackage ? `https://play.google.com/store/apps/details?id=${app.playPackage}` : null;
}

export function appStoreUrl(app: AppEntry): string | null {
  return app.appStoreId ? `https://apps.apple.com/app/id${app.appStoreId}` : null;
}

/** True when the app is presented by a page built from this site's templates. */
export function hasPage(app: AppEntry): boolean {
  return !app.web && !app.href;
}

/** Where the app's tile leads: its own site, a dedicated landing, or its template page. */
export function appHref(app: AppEntry): { href: string; external: boolean } {
  if (app.web) return { href: app.web, external: true };
  return { href: app.href ?? `/${app.id}`, external: false };
}

const PLATFORM_NAMES: Record<Platform, string> = {
  android: 'Android',
  ios: 'iOS',
  web: 'Web',
  windows: 'Windows',
  macos: 'macOS',
};

/** "Android · iOS · Web" */
export function platformLine(platforms: Platform[]): string {
  return platforms.map((p) => PLATFORM_NAMES[p]).join(' · ');
}

/** "Windows, macOS and iOS soon", or null with nothing announced. */
export function soonLine(platforms: Platform[] | undefined): string | null {
  if (!platforms?.length) return null;
  const names = platforms.map((p) => PLATFORM_NAMES[p]);
  const list = names.length === 1 ? names[0] : `${names.slice(0, -1).join(', ')} and ${names.at(-1)}`;
  return `${list} soon`;
}
