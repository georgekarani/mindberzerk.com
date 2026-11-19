import 'server-only';

import { cache } from 'react';
import { CDN_BASE, CDN_REVALIDATE_SECONDS } from '@/lib/site';
import { SEED_APPS } from './seed';
import type { AppEntry, Category, Platform, RegistryDoc, TileSize } from './types';

const REGISTRY_URL = `${CDN_BASE}/site/registry.json`;

const CATEGORIES: readonly Category[] = ['flagship', 'business', 'game'];
const PLATFORMS: readonly Platform[] = ['android', 'ios', 'web', 'windows', 'macos'];
const TILES: readonly TileSize[] = ['large', 'medium', 'small'];
const SLUG = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const HEX = /^#[0-9a-f]{6}$/i;

/** Slugs the site owns for its own pages; an app may never claim one. */
const RESERVED = new Set(['api', 'gvpn', 'studio', 'contact', 'icon.png', 'sitemap.xml', 'robots.txt']);

const str = (v: unknown): string | undefined => (typeof v === 'string' && v.trim() ? v.trim() : undefined);

const httpsUrl = (v: unknown): string | undefined => {
  const s = str(v);
  return s && /^https:\/\//.test(s) ? s : undefined;
};

/** A local path or an https URL; anything else (javascript:, data:) is dropped. */
const asset = (v: unknown): string | undefined => {
  const s = str(v);
  return s && (s.startsWith('/') || s.startsWith('https://')) ? s : undefined;
};

const platforms = (v: unknown): Platform[] =>
  Array.isArray(v) ? v.filter((p): p is Platform => PLATFORMS.includes(p as Platform)) : [];

const shots = (v: unknown) =>
  Array.isArray(v)
    ? v.flatMap((s) => {
        const src = asset((s as { src?: unknown })?.src);
        return src ? [{ src, alt: str((s as { alt?: unknown }).alt) ?? '' }] : [];
      })
    : undefined;

/**
 * Validates one published row. The document is written by the panel, but the
 * site still treats it as untrusted input: a row that fails a required field
 * is dropped rather than rendered half-formed.
 */
function parseEntry(raw: unknown): AppEntry | null {
  if (!raw || typeof raw !== 'object') return null;
  const r = raw as Record<string, unknown>;
  const id = str(r.id);
  const name = str(r.name);
  const category = r.category as Category;
  if (!id || !SLUG.test(id) || RESERVED.has(id) || !name || !CATEGORIES.includes(category)) return null;

  const entry: AppEntry = {
    id,
    name,
    category,
    priority: Number.isFinite(r.priority) ? Number(r.priority) : 99,
    tile: TILES.includes(r.tile as TileSize) ? (r.tile as TileSize) : 'small',
    tagline: str(r.tagline) ?? '',
    summary: str(r.summary),
    tint: HEX.test(String(r.tint)) ? String(r.tint) : '#a0a7b1',
    ground: HEX.test(String(r.ground)) ? String(r.ground) : '#15181b',
    icon: asset(r.icon),
    cover: shots(r.cover ? [r.cover] : undefined)?.[0],
    screens: shots(r.screens),
    features: Array.isArray(r.features)
      ? r.features.flatMap((f) => {
          const t = str((f as { title?: unknown })?.title);
          const b = str((f as { body?: unknown })?.body);
          if (!t || !b) return [];
          return [{ title: t, body: b, image: shots([(f as { image?: unknown }).image])?.[0] }];
        })
      : undefined,
    platforms: platforms(r.platforms),
    soon: platforms(r.soon),
    playPackage: str(r.playPackage),
    appStoreId: /^\d+$/.test(String(r.appStoreId ?? '')) ? String(r.appStoreId) : undefined,
    web: httpsUrl(r.web),
    href: str(r.href)?.startsWith('/') ? str(r.href) : undefined,
    cta: str(r.cta) ?? 'Open',
    privacyUrl: httpsUrl(r.privacyUrl),
    termsUrl: httpsUrl(r.termsUrl),
  };

  const b = r.business as Record<string, unknown> | undefined;
  if (b && str(b.headline)) {
    entry.business = {
      forWhom: str(b.forWhom) ?? 'businesses',
      headline: str(b.headline)!,
      audiences: Array.isArray(b.audiences)
        ? b.audiences.flatMap((a) => {
            const t = str((a as { title?: unknown })?.title);
            const body = str((a as { body?: unknown })?.body);
            return t && body ? [{ title: t, body }] : [];
          })
        : [],
      cta: str(b.cta) ?? 'Talk to us',
      inbox: str(b.inbox),
    };
  }
  return entry;
}

/**
 * The registry for this request. Published document when it parses into at
 * least one row, the seed otherwise. Wrapped in `cache` so a page and its
 * metadata share one fetch.
 */
export const readRegistry = cache(async (): Promise<AppEntry[]> => {
  try {
    const res = await fetch(REGISTRY_URL, { next: { revalidate: CDN_REVALIDATE_SECONDS } });
    if (res.ok) {
      const doc = (await res.json()) as Partial<RegistryDoc>;
      if (doc.formatVersion === 1 && Array.isArray(doc.apps)) {
        const apps = doc.apps.map(parseEntry).filter((a): a is AppEntry => a !== null);
        const unique = [...new Map(apps.map((a) => [a.id, a])).values()];
        if (unique.length > 0) return sortApps(unique);
      }
    }
  } catch {
    // Unreachable CDN: the seed renders.
  }
  return sortApps(SEED_APPS);
});

function sortApps(apps: AppEntry[]): AppEntry[] {
  const order = (c: Category) => CATEGORIES.indexOf(c);
  return [...apps].sort((a, b) => order(a.category) - order(b.category) || a.priority - b.priority);
}

export async function findApp(id: string): Promise<AppEntry | undefined> {
  return (await readRegistry()).find((a) => a.id === id);
}
