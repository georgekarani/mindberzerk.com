import { CDN_BASE } from '@/lib/site';
import type { AppEntry } from './types';

/**
 * The registry the site renders when `site/registry.json` cannot be read.
 *
 * Public list agreed 19 Nov 2026: four flagships, five business products, two
 * games. Package ids and App Store ids are the real store records; an id that
 * is not confirmed is left out rather than guessed, because a wrong id links
 * to somebody else's app.
 */

/** Legal pages the panel publishes per app under `site/legal/<app>/`. */
const legal = (app: string) => ({
  privacyUrl: `${CDN_BASE}/site/legal/${app}/privacy.html`,
  termsUrl: `${CDN_BASE}/site/legal/${app}/terms.html`,
});

const GL = '/apps/g-launcher';

export const SEED_APPS: AppEntry[] = [
  // ── flagships ─────────────────────────────────────────────────────────────
  {
    id: 'tryst',
    name: 'Tryst',
    category: 'flagship',
    priority: 0,
    tile: 'large',
    tagline: 'Dating and live video social',
    tint: '#a78bfa',
    ground: '#16121a',
    platforms: ['android', 'web'],
    soon: ['ios'],
    playPackage: 'com.mindhunter.tryst',
    web: 'https://jointryst.com',
    cta: 'Open Tryst',
  },
  {
    id: 'g-launcher',
    name: 'G Launcher',
    category: 'flagship',
    priority: 1,
    tile: 'large',
    tagline: 'Your phone, as a Linux desktop.',
    summary:
      'Ubuntu, KDE Plasma and a full terminal, free. Kali, Arch with Hyprland, Garuda and more, yours for good with one purchase.',
    tint: '#e95420',
    ground: '#2a0e1e',
    icon: `${GL}/icon.webp`,
    cover: { src: `${GL}/screen-home.webp`, alt: 'G Launcher running the Ubuntu desktop' },
    screens: [
      { src: `${GL}/screen-home.webp`, alt: 'Ubuntu desktop with the dock' },
      { src: `${GL}/screen-distros.webp`, alt: 'The Distros screen' },
      { src: `${GL}/screen-drawer.webp`, alt: 'App drawer with the A to Z scrubber' },
      { src: `${GL}/screen-icons.webp`, alt: 'Icon packs and colours' },
      { src: `${GL}/screen-settings.webp`, alt: 'Settings, stored per distro' },
    ],
    features: [
      {
        title: 'Every icon, matched to the distro.',
        body: 'Each desktop brings its own icon set, colours and corner shape. Change size and roundness, or add a standalone pack.',
        image: { src: `${GL}/screen-icons.webp`, alt: 'Icons screen with Ubuntu Icons and colour variants' },
      },
      {
        title: 'Settings that stay with each desktop.',
        body: 'Appearance, dock and gestures are saved per distro, so switching from Ubuntu to Kali and back loses nothing.',
        image: { src: `${GL}/screen-settings.webp`, alt: 'Settings screen' },
      },
      {
        title: 'Find any app, A to Z.',
        body: 'Slide down the alphabet and land on the app.',
        image: { src: `${GL}/screen-drawer.webp`, alt: 'App drawer with the A to Z scrubber' },
      },
    ],
    platforms: ['android'],
    playPackage: 'com.mindhunter.g_launcher',
    cta: 'See distros',
    ...legal('g-launcher'),
  },
  {
    id: 'g-vpn',
    name: 'G VPN',
    category: 'flagship',
    priority: 2,
    tile: 'medium',
    tagline: 'WireGuard and OpenVPN, your own servers or ours, and the network tools to check either.',
    tint: '#2457f5',
    ground: '#0b1730',
    icon: '/apps/g-vpn/icon.webp',
    platforms: ['android'],
    soon: ['windows', 'macos', 'ios'],
    playPackage: 'com.mindberzerk.gvpn',
    cta: 'Open',
    ...legal('g-vpn'),
  },
  {
    id: 'g-recovery',
    name: 'G Recovery',
    category: 'flagship',
    priority: 3,
    tile: 'medium',
    tagline: 'Storage audit, permission review, and scheduled backup to your own home server.',
    tint: '#4c8dff',
    ground: '#121820',
    icon: '/apps/g-recovery/icon.webp',
    platforms: ['android'],
    playPackage: 'com.mindhunter.g_recovery',
    cta: 'Open',
    ...legal('g-recovery'),
  },

  // ── business products ─────────────────────────────────────────────────────
  {
    id: 'kenyahomeshub',
    name: 'KenyaHomesHub',
    category: 'business',
    priority: 0,
    tile: 'small',
    tagline: 'Houses, apartments and bedsitters to rent and buy.',
    tint: '#4cc1ea',
    ground: '#0f2430',
    platforms: ['android', 'ios', 'web'],
    playPackage: 'com.mindhunter.flicker',
    appStoreId: '6473903281',
    web: 'https://kenyahomeshub.com',
    cta: 'Visit site',
  },
  {
    id: 'fructa',
    name: 'Fructa',
    category: 'business',
    priority: 1,
    tile: 'small',
    tagline: 'Money market funds in one place.',
    tint: '#4ade80',
    ground: '#0f1f16',
    platforms: ['android', 'ios'],
    playPackage: 'com.mindberzerk.fructa',
    appStoreId: '6789087329',
    cta: 'For fund managers',
    business: {
      forWhom: 'fund managers',
      headline: 'Put your money market fund in front of savers.',
      audiences: [
        { title: 'Fund managers', body: 'List your fund and its yield where savers compare funds.' },
      ],
      cta: 'Talk to us',
    },
  },
  {
    id: 'culicars',
    name: 'CuliCars',
    category: 'business',
    priority: 2,
    tile: 'small',
    tagline: 'Car history checks before you buy.',
    tint: '#fbbf24',
    ground: '#1e1a10',
    platforms: ['android'],
    playPackage: 'com.mindberzerk.culicars',
    cta: 'For dealers',
    business: {
      forWhom: 'dealers and importers',
      headline: 'Show buyers the history behind every car you sell.',
      audiences: [
        { title: 'Dealers', body: 'Attach a history check to each car on your yard.' },
        { title: 'Importers', body: 'Give buyers the record of every unit you bring in.' },
      ],
      cta: 'Talk to us',
    },
  },
  {
    id: 'culimix',
    name: 'Culimix',
    category: 'business',
    priority: 3,
    tile: 'small',
    tagline: 'A marketplace with apps for shoppers, stores and delivery.',
    tint: '#f472b6',
    ground: '#1f1018',
    platforms: ['android', 'ios'],
    appStoreId: '6467224431',
    cta: 'For stores',
    business: {
      forWhom: 'stores and delivery partners',
      headline: 'Open your store on Culimix.',
      audiences: [
        { title: 'Stores', body: 'List products and take orders in the Culimix Store app.' },
        { title: 'Delivery partners', body: 'Pick up and drop off orders with the delivery app.' },
      ],
      cta: 'Talk to us',
    },
  },
  {
    id: 'kaaga-water-project',
    name: 'Kaaga Water Project',
    category: 'business',
    priority: 4,
    tile: 'small',
    tagline: 'The Kaaga Water Project app for its members.',
    tint: '#38bdf8',
    ground: '#0d1d26',
    platforms: ['android', 'ios'],
    playPackage: 'com.mindberzerk.kaagawaterproject',
    appStoreId: '6760460241',
    cta: 'For schemes',
    business: {
      forWhom: 'water schemes',
      headline: 'Collect scheme fees and keep member records in one app.',
      audiences: [{ title: 'Water schemes', body: 'Give members an app for fees, notices and records.' }],
      cta: 'Talk to us',
    },
  },

  // ── games ─────────────────────────────────────────────────────────────────
  {
    id: 'monkeyhide',
    name: 'MonkeyHide',
    category: 'game',
    priority: 0,
    tile: 'large',
    tagline: 'Hide and seek',
    tint: '#a3e635',
    ground: '#13190f',
    platforms: ['android', 'ios'],
    playPackage: 'com.mindberzerk.monkeyjump',
    appStoreId: '6761255749',
    cta: 'Play',
  },
  {
    id: 'sketji-tiles',
    name: 'Sketji Tiles',
    category: 'game',
    priority: 1,
    tile: 'small',
    tagline: 'A tile game.',
    tint: '#f0abfc',
    ground: '#1a121c',
    platforms: ['android'],
    playPackage: 'com.mindberzerk.sketji',
    cta: 'Play',
  },
];
