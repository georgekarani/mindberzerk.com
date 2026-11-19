import 'server-only';

import { cache } from 'react';
import { CDN_BASE, CDN_REVALIDATE_SECONDS } from '@/lib/site';

/**
 * The home hero, published by the panel to `site/home.json`.
 *
 * A new object rather than the old `site/content.json`: that document's hero
 * spoke for G Launcher alone, and reading it would put that headline back on
 * the studio page until somebody republished it.
 */

export interface HomeCopy {
  eyebrow: string;
  /** Text after the first comma renders in the accent colour. */
  headline: string;
  lede: string;
}

const SEED: HomeCopy = {
  eyebrow: 'Mindberzerk Studio',
  headline: 'Apps for people everywhere, and for businesses in Kenya.',
  lede: 'Tryst, G Launcher, G VPN and G Recovery for everyone. KenyaHomesHub, Fructa, CuliCars, Culimix and Kaaga for Kenyan businesses.',
};

export const readHomeCopy = cache(async (): Promise<HomeCopy> => {
  try {
    const res = await fetch(`${CDN_BASE}/site/home.json`, { next: { revalidate: CDN_REVALIDATE_SECONDS } });
    if (!res.ok) return SEED;
    const doc = (await res.json()) as Partial<HomeCopy>;
    const pick = (v: unknown, fallback: string) => (typeof v === 'string' && v.trim() ? v.trim() : fallback);
    return { eyebrow: pick(doc.eyebrow, SEED.eyebrow), headline: pick(doc.headline, SEED.headline), lede: pick(doc.lede, SEED.lede) };
  } catch {
    return SEED;
  }
});

export function splitHeadline(headline: string): { plain: string; accent: string | null } {
  const i = headline.indexOf(',');
  if (i < 0) return { plain: headline, accent: null };
  return { plain: headline.slice(0, i + 1), accent: headline.slice(i + 1).trim() || null };
}
