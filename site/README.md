# mindberzerk.com

The public studio site: a live dashboard of every app Mindberzerk Studio lists,
one page per app sold to people, and one business page per product sold
to businesses. Next.js 16 on its own Firebase App Hosting backend, separate
from the panel in `admin/`, holding no credential of any kind.

## What renders from where

| Object on the CDN | What it drives | Without it |
| --- | --- | --- |
| `site/registry.json` | Every app: order, tile size, copy, icons, screens, store ids, own website, business pitch | `src/lib/catalog/seed.ts` |
| `site/stats.json` | Installs, monthly devices and rating per app, with a date and a source | Dated seed from 19 Nov 2026 |
| `site/home.json` | Home eyebrow, headline (accent after the first comma) and lede | Seed in `src/lib/home/read.ts` |
| `g-launcher/index.json` | Which paid distros are live on the G Launcher page | Every priced distro shows |

Each read revalidates every 5 minutes, so a panel publish shows without a
deploy. Every document is validated row by row: a row that fails a required
field is dropped, and a document that yields nothing falls back to the seed.

Rules the renderers keep:

- An app with `web` set (Tryst, KenyaHomesHub) has no page here; its tile links
  to its own site.
- A stat below 50 is withheld, and no number is ever shown without its source
  and date.
- An app without real icon art shows its name alone, never a letter mark.
- Business pages show plans only once real plans exist in the registry.

## Routes

- `/` home
- `/<id>` app page or business page, from the registry
- `/api/contact` contact and enquiry relay, routed per product
- `/gvpn` temporarily redirects to `/g-vpn` until the G VPN landing is ported
  from the panel

## Contact delivery

Five Secret Manager values, listed in `apphosting.yaml`. Until they exist the
route answers 503 and the forms offer a prefilled mailto link. A product whose
registry row has `business.inbox` gets its enquiries there; everything else
goes to `SITE_CONTACT_TO`.

## Local

```
npm install
npm run dev
npm run typecheck && npm run lint && npm run build
```
