import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { AppPage } from '@/components/app-page/app-page';
import { BusinessPage } from '@/components/app-page/business-page';
import { GLauncherStore } from '@/components/app-page/g-launcher-store';
import { findApp, readRegistry } from '@/lib/catalog/read';
import { hasPage, platformLine, playUrl } from '@/lib/catalog/links';
import type { AppEntry, BusinessPitch } from '@/lib/catalog/types';
import { SITE_URL, STUDIO_NAME } from '@/lib/site';
import { readStats, shownStats } from '@/lib/stats/read';

/**
 * `/<app id>`: an app page for products sold to people, a business page for
 * Kenya products sold to businesses. Apps with their own website have no page
 * here; their tiles link out.
 */

export const revalidate = 300;

/** New registry rows render on first request without a deploy. */
export const dynamicParams = true;

export async function generateStaticParams() {
  return (await readRegistry()).filter(hasPage).map((a) => ({ slug: a.id }));
}

type Params = { params: Promise<{ slug: string }> };

async function pageApp(slug: string): Promise<AppEntry | null> {
  const app = await findApp(slug);
  return app && hasPage(app) ? app : null;
}

const isBusiness = (app: AppEntry): app is AppEntry & { business: BusinessPitch } =>
  app.category === 'kenya' && !!app.business;

export async function generateMetadata({ params }: Params): Promise<Metadata> {
  const app = await pageApp((await params).slug);
  if (!app) return {};
  const title = isBusiness(app) ? `${app.name} for ${app.business.forWhom}` : app.name;
  const description = isBusiness(app) ? app.business.headline : app.summary ?? app.tagline;
  const image = app.cover?.src ?? app.icon;
  return {
    title,
    description,
    alternates: { canonical: `/${app.id}` },
    openGraph: {
      title: `${title} · ${STUDIO_NAME}`,
      description,
      url: `/${app.id}`,
      ...(image ? { images: [{ url: image }] } : {}),
    },
  };
}

export default async function SlugPage({ params }: Params) {
  const app = await pageApp((await params).slug);
  if (!app) notFound();

  const stats = await readStats();
  const shown = shownStats(stats.apps[app.id]);
  const source = { source: stats.source, asOf: stats.asOf };
  const play = playUrl(app);

  /** Structured data so search can show the listing as an app. */
  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': app.category === 'game' ? 'VideoGame' : 'MobileApplication',
    name: app.name,
    description: app.summary ?? app.tagline,
    url: `${SITE_URL}/${app.id}`,
    operatingSystem: platformLine(app.platforms),
    ...(app.icon ? { image: new URL(app.icon, SITE_URL).toString() } : {}),
    ...(play ? { installUrl: play } : {}),
    publisher: { '@type': 'Organization', name: STUDIO_NAME, url: SITE_URL },
  };

  return (
    <>
      <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd).replace(/</g, '\\u003c') }} />
      {isBusiness(app) ? (
        <BusinessPage app={app} stats={shown} statsSource={source} />
      ) : (
        <AppPage
          app={app}
          stats={shown}
          statsSource={source}
          extra={app.id === 'g-launcher' && play ? <GLauncherStore playHref={play} /> : undefined}
        />
      )}
    </>
  );
}
