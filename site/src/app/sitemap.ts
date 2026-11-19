import type { MetadataRoute } from 'next';
import { hasPage } from '@/lib/catalog/links';
import { readRegistry } from '@/lib/catalog/read';
import { SITE_URL } from '@/lib/site';

export const revalidate = 3600;

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const apps = (await readRegistry()).filter(hasPage);
  return [
    { url: SITE_URL, changeFrequency: 'weekly', priority: 1 },
    ...apps.map((a) => ({
      url: `${SITE_URL}/${a.id}`,
      changeFrequency: 'weekly' as const,
      priority: a.category === 'flagship' ? 0.9 : 0.7,
    })),
  ];
}
