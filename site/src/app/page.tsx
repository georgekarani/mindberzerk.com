import { ContactForm } from '@/components/contact-form';
import { BusinessTile, GameTile, LargeTile, MediumTile } from '@/components/home/tiles';
import { ButtonLink, Display, Eyebrow } from '@/components/ui';
import { readRegistry } from '@/lib/catalog/read';
import type { AppEntry } from '@/lib/catalog/types';
import { readHomeCopy, splitHeadline } from '@/lib/home/read';
import { CONTACT_EMAIL, SITE_URL, STUDIO_NAME } from '@/lib/site';
import { formatAsOf, readStats, shownStats } from '@/lib/stats/read';

/** Rebuilt at most every five minutes, matching the CDN reads underneath. */
export const revalidate = 300;

const PRINCIPLES = [
  { title: 'No ads', body: 'The G apps carry no advertising.' },
  { title: 'Pay once', body: 'Distros, server passes and Pro unlocks are one-time purchases.' },
  { title: 'Your data stays yours', body: 'It lives on your hardware, not ours.' },
];

export default async function Home() {
  const [apps, stats, copy] = await Promise.all([readRegistry(), readStats(), readHomeCopy()]);
  const { plain, accent } = splitHeadline(copy.headline);
  const statsFor = (a: AppEntry) => shownStats(stats.apps[a.id]);

  const flagships = apps.filter((a) => a.category === 'flagship');
  const kenya = apps.filter((a) => a.category === 'kenya');
  const games = apps.filter((a) => a.category === 'game');

  const jsonLd = {
    '@context': 'https://schema.org',
    '@type': 'Organization',
    name: STUDIO_NAME,
    url: SITE_URL,
    logo: `${SITE_URL}/icon.png`,
    email: CONTACT_EMAIL,
  };

  return (
    <>
      <script
        type="application/ld+json"
        dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd).replace(/</g, '\\u003c') }}
      />

      <section className="mx-auto max-w-[1360px] px-6 pb-14 pt-24">
        <Eyebrow className="mb-5">{copy.eyebrow}</Eyebrow>
        <Display as="h1" size="hero" className="max-w-[1000px]">
          {plain}
          {accent ? <span className="text-accent"> {accent}</span> : null}
        </Display>
        <p className="m-0 mt-7 max-w-[640px] text-[19px] text-ink-2">{copy.lede}</p>
      </section>

      <section id="apps" aria-labelledby="apps-h" className="mx-auto max-w-[1360px] scroll-mt-20 px-6">
        <div className="flex flex-wrap items-baseline justify-between gap-3 pb-5">
          <h2 id="apps-h" className="m-0 font-display text-[28px] font-semibold">
            Live now
          </h2>
          <p className="m-0 text-sm text-ink-muted">
            {stats.source}, updated {formatAsOf(stats.asOf)}
          </p>
        </div>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:auto-rows-[minmax(280px,auto)] lg:grid-cols-4">
          {flagships.map((a) =>
            a.tile === 'large' ? <LargeTile key={a.id} app={a} stats={statsFor(a)} /> : <MediumTile key={a.id} app={a} stats={statsFor(a)} />,
          )}
        </div>
      </section>

      {kenya.length > 0 ? (
        <section id="business" aria-labelledby="business-h" className="mt-28 scroll-mt-20 border-y border-line bg-bg-raised">
          <div className="mx-auto max-w-[1360px] px-6 py-24">
            <div className="mb-10 flex flex-wrap items-end justify-between gap-6">
              <div>
                <Eyebrow className="mb-3">For business in Kenya</Eyebrow>
                <Display id="business-h" className="max-w-[760px]">
                  Reach Kenyan customers through apps they already use.
                </Display>
              </div>
              <ButtonLink href="#contact" variant="ghost">
                Talk to us
              </ButtonLink>
            </div>
            <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-5">
              {kenya.map((a) => (
                <BusinessTile key={a.id} app={a} stats={statsFor(a)} />
              ))}
            </div>
          </div>
        </section>
      ) : null}

      {games.length > 0 ? (
        <section id="games" aria-labelledby="games-h" className="mx-auto max-w-[1360px] scroll-mt-20 px-6 pt-28">
          <h2 id="games-h" className="m-0 mb-8 font-display text-[28px] font-semibold">
            Games
          </h2>
          <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
            {games.map((a, i) => (
              <GameTile key={a.id} app={a} lead={i === 0} />
            ))}
          </div>
        </section>
      ) : null}

      <section id="studio" aria-labelledby="studio-h" className="mx-auto max-w-[1360px] scroll-mt-20 px-6 pt-36">
        <Display id="studio-h" className="max-w-[900px]">
          One independent studio, shipping to Google Play and the App Store.
        </Display>
        <div className="mt-12 grid grid-cols-1 gap-10 border-t border-line pt-8 md:grid-cols-3">
          {PRINCIPLES.map((p) => (
            <div key={p.title}>
              <h3 className="m-0 mb-2 text-[19px] font-semibold">{p.title}</h3>
              <p className="m-0 text-ink-2">{p.body}</p>
            </div>
          ))}
        </div>
      </section>

      <section id="contact" aria-labelledby="contact-h" className="mx-auto max-w-[1360px] scroll-mt-20 px-6 pb-32 pt-36">
        <div className="flex flex-wrap gap-12">
          <div className="flex-[1_1_320px]">
            <Display id="contact-h">Get in touch</Display>
            <p className="m-0 mt-4 text-ink-2">
              <a href={`mailto:${CONTACT_EMAIL}`} className="underline-offset-4 hover:underline">
                {CONTACT_EMAIL}
              </a>
            </p>
          </div>
          <div className="flex-[2_1_520px]">
            <ContactForm contactEmail={CONTACT_EMAIL} topics={apps.map((a) => ({ id: a.id, name: a.name }))} />
          </div>
        </div>
      </section>
    </>
  );
}
