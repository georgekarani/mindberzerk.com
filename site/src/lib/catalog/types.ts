/**
 * The public app registry: one row per app the studio lists.
 *
 * The panel publishes this shape to `site/registry.json` on the CDN; the site
 * renders from it and falls back to the seed in `seed.ts`. Only public facts
 * belong here. Console ids, internal notes and admin state stay in the panel.
 */

export type Category = 'flagship' | 'kenya' | 'game';

export type Platform = 'android' | 'ios' | 'web' | 'windows' | 'macos';

/** Tile footprint on the home grid. */
export type TileSize = 'large' | 'medium' | 'small';

export interface Shot {
  src: string;
  alt: string;
}

export interface Feature {
  title: string;
  body: string;
  /** A screen showing the feature, drawn beside the copy. */
  image?: Shot;
}

export interface Audience {
  title: string;
  body: string;
}

/** What a Kenya product's business page says to the businesses it sells to. */
export interface BusinessPitch {
  /** Who the page is for, in a few words: "agents and landlords". */
  forWhom: string;
  headline: string;
  audiences: Audience[];
  /** Label of the primary call to action on the tile and the page. */
  cta: string;
  /**
   * Public inbox enquiries for this product are delivered to. Absent means the
   * studio's default inbox.
   */
  inbox?: string;
}

export interface AppEntry {
  /** URL slug: the app page lives at `/${id}` unless `web` or `href` is set. */
  id: string;
  name: string;
  category: Category;
  /** Order within the category, lowest first. */
  priority: number;
  tile: TileSize;
  /** One line under the name. */
  tagline: string;
  /** A short paragraph for the app page hero. */
  summary?: string;
  /** Accent colour, hex. Decoration only: never the sole carrier of meaning. */
  tint: string;
  /** Darker ground the tile and hero sit on, hex. */
  ground: string;
  icon?: string;
  /** Picture the home tile bleeds to its edge. */
  cover?: Shot;
  screens?: Shot[];
  features?: Feature[];
  platforms: Platform[];
  /** Platforms announced but not shipped. */
  soon?: Platform[];
  /** Android application id; the Play link is derived from it. */
  playPackage?: string;
  /** Numeric App Store id; the App Store link is derived from it. */
  appStoreId?: string;
  /** The product's own website. When set, the tile links there and no page is built here. */
  web?: string;
  /** A path on this site that replaces `/${id}`, for landings that predate the template. */
  href?: string;
  /** Label of the tile's primary action. */
  cta: string;
  privacyUrl?: string;
  termsUrl?: string;
  business?: BusinessPitch;
}

/** The published document. */
export interface RegistryDoc {
  formatVersion: 1;
  apps: AppEntry[];
}
