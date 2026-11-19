import 'server-only';

import { cache } from 'react';
import { CDN_BASE, CDN_REVALIDATE_SECONDS } from '@/lib/site';

/**
 * Total installs per app, the one number the site shows.
 *
 * The panel's scheduled job publishes `site/stats.json`. Each value is the
 * store's own install count as it appears on the public listing ("50K+"),
 * stored as its lower bound, so the site never claims more than the store
 * does. A number without a date and a source is never shown.
 */

export interface AppStats {
  /** Lower bound of the store's install count: 50000 for "50K+". */
  installs?: number;
}

export interface StatsDoc {
  /** ISO date the numbers were read. */
  asOf: string;
  /** Where they came from: "Google Play". */
  source: string;
  apps: Record<string, AppStats>;
}

/** Below this an install count reads as an empty shop, so it is withheld. */
export const MIN_SHOWN = 100;

const STATS_URL = `${CDN_BASE}/site/stats.json`;

/** Install counts from each public Play listing, 19 Nov 2026. */
const SEED: StatsDoc = {
  asOf: '2026-11-19',
  source: 'Google Play',
  apps: {
    tryst: { installs: 50_000 },
    'g-launcher': { installs: 1_000 },
    'g-vpn': { installs: 5_000 },
    'g-recovery': { installs: 5_000 },
    kenyahomeshub: { installs: 1_000 },
    fructa: { installs: 500 },
    culicars: { installs: 10 },
    'kaaga-water-project': { installs: 10 },
    monkeyhide: { installs: 5_000 },
    'sketji-tiles': { installs: 100 },
  },
};

const num = (v: unknown): number | undefined =>
  typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : undefined;

export const readStats = cache(async (): Promise<StatsDoc> => {
  try {
    const res = await fetch(STATS_URL, { next: { revalidate: CDN_REVALIDATE_SECONDS } });
    if (res.ok) {
      const doc = (await res.json()) as Partial<StatsDoc>;
      if (typeof doc.asOf === 'string' && typeof doc.source === 'string' && doc.apps && typeof doc.apps === 'object') {
        const apps: Record<string, AppStats> = {};
        for (const [id, s] of Object.entries(doc.apps)) {
          apps[id] = { installs: num((s as Record<string, unknown>)?.installs) };
        }
        return { asOf: doc.asOf, source: doc.source, apps };
      }
    }
  } catch {
    // Unreachable CDN: the dated seed renders.
  }
  return SEED;
});

export interface ShownStat {
  label: string;
  value: string;
}

/** Total installs, when there are enough to be worth printing. */
export function shownStats(s: AppStats | undefined): ShownStat[] {
  if (s?.installs === undefined || s.installs < MIN_SHOWN) return [];
  return [{ label: 'Installs', value: `${compact(s.installs)}+` }];
}

/** 50000 -> "50K", 500 -> "500". */
export function compact(n: number): string {
  if (n < 1000) return String(Math.round(n));
  const units: [number, string][] = [
    [1e9, 'B'],
    [1e6, 'M'],
    [1e3, 'K'],
  ];
  for (const [size, suffix] of units) {
    if (n >= size) return `${Number((n / size).toPrecision(3))}${suffix}`;
  }
  return String(n);
}

/** "19 Nov 2026" */
export function formatAsOf(iso: string): string {
  const d = new Date(`${iso}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return iso;
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' });
}
