/** Site-wide constants. Everything here is public by design. */

export const SITE_URL = (process.env.NEXT_PUBLIC_SITE_URL ?? 'https://mindberzerk.com').replace(/\/$/, '');

export const CDN_BASE = (process.env.CDN_BASE_URL ?? 'https://cdn.mindberzerk.com').replace(/\/$/, '');

export const CONTACT_EMAIL = process.env.NEXT_PUBLIC_CONTACT_EMAIL ?? 'info@mindberzerk.com';

export const STUDIO_NAME = 'Mindberzerk Studio';

export const PLAY_DEVELOPER_URL = 'https://play.google.com/store/apps/dev?id=8965127905950081681';

export const APP_STORE_DEVELOPER_URL = 'https://apps.apple.com/us/developer/george-gakuubi/id1701828476';

/** How long a CDN read is reused before the next request refetches it. */
export const CDN_REVALIDATE_SECONDS = 300;
