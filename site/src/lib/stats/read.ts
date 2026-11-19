import 'server-only';

import { cache } from 'react';
import { CDN_BASE, CDN_REVALIDATE_SECONDS } from '@/lib/site';

/**
 * Live per-app numbers.
 *
 * The panel's scheduled job reads Play and App Store reporting and publishes
 * `site/stats.json`. The site shows only numbers that carry a date and a
 * source, and drops any it cannot read. Nothing here is ever estimated.
 */

export interface AppStats {
  /** Installs over the reporting window. */
  installs?: number;
  /** Monthly active devices. */
  activeDevices?: number;
  /** Store rating, 1 to 5. */
  rating?: number;
}

export interface StatsDoc {
  /** ISO date the numbers were read. */
  asOf: string;
  /** Human label for where they came from: "Google Play, last 28 days". */
  source: string;
  apps: Record<string, AppStats>;
}

/**
 * A number this small reads as an empty shop rather than a fact worth showing,
 * so it is withheld. It is still in the document for the panel.
 */
export const MIN_SHOWN = 50;

const STATS_URL = `${CDN_BASE}/site/stats.json`;

/** Read from Play Console on 19 Nov 2026 for the revamp handoff. */
const SEED: StatsDoc = {
  asOf: '2026-11-19',
  source: 'Google Play, last 28 days',
  apps: {
    tryst: { installs: 1180, activeDevices: 1060 },
    'g-launcher': { installs: 1420, activeDevices: 791 },
    'g-vpn': { installs: 241, activeDevices: 182 },
    'g-recovery': { installs: 203, activeDevices: 144 },
    kenyahomeshub: { installs: 100, activeDevices: 149 },
    fructa: { installs: 147, activeDevices: 118 },
  },
};

const num = (v: unknown): number | undefined => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : undefined);

export const readStats = cache(async (): Promise<StatsDoc> => {
  try {
    const res = await fetch(STATS_URL, { next: { revalidate: CDN_REVALIDATE_SECONDS } });
    if (res.ok) {
      const doc = (await res.json()) as Partial<StatsDoc>;
      if (typeof doc.asOf === 'string' && typeof doc.source === 'string' && doc.apps && typeof doc.apps === 'object') {
        const apps: Record<string, AppStats> = {};
        for (const [id, s] of Object.entries(doc.apps)) {
          const v = s as Record<string, unknown>;
          const rating = num(v.rating);
          apps[id] = {
            installs: num(v.installs),
            activeDevices: num(v.activeDevices),
            rating: rating !== undefined && rating >= 1 && rating <= 5 ? rating : undefined,
          };
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

/** The stats worth printing for one app, in display order. */
export function shownStats(s: AppStats | undefined): ShownStat[] {
  if (!s) return [];
  const out: ShownStat[] = [];
  if (s.rating !== undefined) out.push({ label: 'Rating', value: s.rating.toFixed(1) });
  if (s.installs !== undefined && s.installs >= MIN_SHOWN) out.push({ label: 'Installs', value: compact(s.installs) });
  if (s.activeDevices !== undefined && s.activeDevices >= MIN_SHOWN)
    out.push({ label: 'Monthly devices', value: compact(s.activeDevices) });
  return out;
}

/** 1420 -> "1.42K", 791 -> "791". */
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
