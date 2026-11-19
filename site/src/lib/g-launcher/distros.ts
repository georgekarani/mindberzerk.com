import 'server-only';

import { cache } from 'react';
import { CDN_BASE, CDN_REVALIDATE_SECONDS } from '@/lib/site';

/**
 * G Launcher's storefront for the app page.
 *
 * Two sources, each owning what it knows:
 *  - prices, titles and grants mirror `backend/content/products.json`, the
 *    file every Play SKU is checked against;
 *  - which paid distros are LIVE comes from the signed catalogue at
 *    `g-launcher/index.json`. A distro whose pack is not published is not
 *    sold on the page, because a purchase that grants nothing downloadable is
 *    a refund request.
 * When the index cannot be read every priced distro shows, since the prices
 * themselves are known.
 */

export interface Distro {
  /** Pack id, as in the index and the theme registry. */
  id: string;
  title: string;
  /** Short line drawn on the card. */
  note: string;
  /** Wallpaper the card bleeds, or a gradient in the distro's palette when none ships. */
  image?: string;
  gradient: [string, string];
  /** USD, absent for the bundled free distros. */
  priceUsd?: number;
}

export interface Bundle {
  sku: string;
  title: string;
  summary: string;
  priceUsd: number;
  /** The all-distros bundle is the page's lead offer. */
  lead: boolean;
}

const WALLS = '/apps/g-launcher/distros';

/** Bundled in the APK, always free (engine/theme_registry.dart). */
const FREE: Distro[] = [
  { id: 'ubuntu-24-04', title: 'Ubuntu 24.04', note: 'GNOME, dock on the left', gradient: ['#77216f', '#2c001e'] },
  { id: 'kde-plasma-6', title: 'KDE Plasma 6', note: 'Panel and start menu', gradient: ['#1d99f3', '#0b2f52'] },
  { id: 'terminal', title: 'Terminal', note: 'Launch by typing', gradient: ['#0d130d', '#050705'] },
];

const PAID: Distro[] = [
  { id: 'kali-2026', title: 'Kali', note: 'Dragon wallpapers, its own boot log', image: `${WALLS}/kali.webp`, gradient: ['#1b3a63', '#0a1424'], priceUsd: 1.49 },
  { id: 'arch-hyprland', title: 'Arch + Hyprland', note: 'Tiling, waybar and gaps', image: `${WALLS}/arch.webp`, gradient: ['#1793d1', '#0b2233'], priceUsd: 1.49 },
  { id: 'garuda-dr460nized', title: 'Garuda Dr460nized', note: 'Blur and the dragon palette', image: `${WALLS}/garuda.webp`, gradient: ['#7a2bd1', '#1a0b2e'], priceUsd: 1.49 },
  { id: 'mint-22', title: 'Linux Mint', note: 'Cinnamon, bottom panel', image: `${WALLS}/mint.webp`, gradient: ['#87cf3e', '#1b2b12'], priceUsd: 1.49 },
  { id: 'pop-os-cosmic', title: 'Pop!_OS', note: 'COSMIC, tiling by default', image: `${WALLS}/pop.webp`, gradient: ['#48b9c7', '#1e2b2e'], priceUsd: 1.49 },
  { id: 'elementary-8', title: 'elementary OS', note: 'Pantheon, centred dock', gradient: ['#64676c', '#2b2d31'], priceUsd: 1.49 },
  { id: 'debian-13', title: 'Debian', note: 'The swirl, deep red', gradient: ['#a80030', '#3d0012'], priceUsd: 1.49 },
];

const BUNDLES: Bundle[] = [
  { sku: 'distro_pack_all', title: 'Every distro, forever', summary: 'All distro packs, including every one released in future.', priceUsd: 11.99, lead: true },
  { sku: 'bundle_tiling', title: 'Tiling collection', summary: 'Arch with Hyprland, Garuda Dr460nized, and any tiling distro added later.', priceUsd: 3.99, lead: false },
  { sku: 'bundle_classic', title: 'Classic desktops', summary: 'Linux Mint, elementary OS, Debian and Pop!_OS.', priceUsd: 3.99, lead: false },
];

const INDEX_URL = `${CDN_BASE}/g-launcher/index.json`;

/** Theme pack ids in the live index, or null when it cannot be read. */
async function liveThemeIds(): Promise<Set<string> | null> {
  try {
    const res = await fetch(INDEX_URL, { next: { revalidate: CDN_REVALIDATE_SECONDS } });
    if (!res.ok) return null;
    const idx = (await res.json()) as { packs?: { packId?: unknown; packType?: unknown }[] };
    if (!Array.isArray(idx.packs)) return null;
    return new Set(
      idx.packs.filter((p) => p.packType === 'theme' && typeof p.packId === 'string').map((p) => p.packId as string),
    );
  } catch {
    return null;
  }
}

export const readStorefront = cache(async () => {
  const live = await liveThemeIds();
  const paid = live && live.size > 0 ? PAID.filter((d) => live.has(d.id)) : PAID;
  return { free: FREE, paid, bundles: BUNDLES };
});

export function usd(n: number): string {
  return `USD ${n.toFixed(2)}`;
}
