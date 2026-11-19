import Image from 'next/image';
import type { ReactNode } from 'react';
import { StoreBadges } from '@/components/store-badges';
import { AppIcon, Display, StatList } from '@/components/ui';
import { platformLine, playUrl, soonLine } from '@/lib/catalog/links';
import type { AppEntry } from '@/lib/catalog/types';
import { inkOn } from '@/lib/color';
import { formatAsOf, type ShownStat } from '@/lib/stats/read';

/**
 * The app page template: one page per app the studio sells to people.
 *
 * Content first. The hero sits on the app's own ground and lets its real
 * screens bleed off the bottom edge; everything after it is the product, its
 * offers and its legal links. `extra` is where an app with a storefront (G
 * Launcher's distros) puts it, between the screens and the features.
 */

interface Props {
  app: AppEntry;
  stats: ShownStat[];
  statsSource: { source: string; asOf: string };
  extra?: ReactNode;
}

export function AppPage({ app, stats, statsSource, extra }: Props) {
  const heroScreens = app.screens?.slice(0, 2) ?? [];
  const soon = soonLine(app.soon);
  const play = playUrl(app);
  const ctaInk = inkOn(app.tint);

  return (
    <>
      <section
        className="relative overflow-hidden text-white"
        style={{ backgroundColor: app.ground, backgroundImage: `radial-gradient(120% 90% at 80% 10%, ${app.tint}40 0%, transparent 55%)` }}
      >
        <div className="mx-auto flex max-w-[1360px] flex-wrap items-end gap-12 px-6 pt-24">
          <div className={`flex-[1_1_460px] ${heroScreens.length ? 'pb-24' : 'pb-28'}`}>
            <AppIcon src={app.icon} size={88} className="mb-7" />
            <p className="m-0 mb-4 text-sm uppercase tracking-[0.08em] text-white/70">{app.name}</p>
            <Display as="h1" size="hero">
              {app.tagline}
            </Display>
            {app.summary ? <p className="m-0 mt-7 max-w-[540px] text-[19px] text-white/80">{app.summary}</p> : null}
            <div className="mt-9 flex flex-wrap items-center gap-4">
              <StoreBadges app={app} />
              <span className="text-[15px] text-white/75">
                {platformLine(app.platforms)}
                {soon ? ` · ${soon}` : ''}
              </span>
            </div>
            {stats.length ? (
              <div className="mt-12 flex flex-col gap-3">
                <StatList stats={stats} size="lg" tone="text-white/70" />
                <p className="m-0 text-[13px] text-white/60">
                  {statsSource.source}, updated {formatAsOf(statsSource.asOf)}
                </p>
              </div>
            ) : null}
          </div>
          {heroScreens.length ? (
            <div className="flex min-h-[520px] flex-[1_1_440px] items-end justify-center gap-6">
              {heroScreens.map((s, i) => (
                <Image
                  key={s.src}
                  src={s.src}
                  alt={s.alt}
                  width={540}
                  height={1089}
                  priority
                  sizes="(min-width: 1024px) 300px, 45vw"
                  className={`w-[46%] max-w-[300px] rounded-t-[32px] shadow-[0_-20px_80px_rgba(0,0,0,0.45)] ${i === 0 ? 'translate-y-10' : ''}`}
                />
              ))}
            </div>
          ) : null}
        </div>
      </section>

      {app.screens && app.screens.length > 2 ? (
        <section aria-label={`${app.name} screens`} className="pt-24">
          <ul className="rail m-0 flex list-none snap-x snap-mandatory gap-5 overflow-x-auto px-6 pb-2" tabIndex={0}>
            {app.screens.map((s) => (
              <li key={s.src} className="shrink-0 snap-start">
                <Image src={s.src} alt={s.alt} width={540} height={1089} sizes="280px" className="w-[280px] rounded-[28px]" />
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {extra}

      {app.features?.length ? (
        <section aria-label="Features" className="mx-auto flex max-w-[1360px] flex-col gap-28 px-6 pt-40">
          {app.features.map((f, i) => (
            <div key={f.title} className={`flex items-center gap-16 ${i % 2 ? 'flex-wrap-reverse md:flex-row-reverse' : 'flex-wrap'}`}>
              {f.image ? (
                <Image src={f.image.src} alt={f.image.alt} width={540} height={1089} sizes="320px" className="w-[320px] max-w-full shrink rounded-[32px]" />
              ) : null}
              <div className="flex-[1_1_400px]">
                <Display size="block">{f.title}</Display>
                <p className="m-0 mt-5 max-w-[480px] text-lg text-ink-2">{f.body}</p>
              </div>
            </div>
          ))}
        </section>
      ) : null}

      {play ? (
        <section className="mt-40" style={{ backgroundColor: app.tint, color: ctaInk }}>
          <div className="mx-auto flex max-w-[1360px] flex-wrap items-center justify-between gap-8 px-6 py-24">
            <Display className="max-w-[760px]">Get {app.name}.</Display>
            <a
              href={play}
              className="rounded-full px-8 py-[18px] text-lg font-semibold"
              style={{ backgroundColor: ctaInk, color: ctaInk === '#ffffff' ? '#0a0b0d' : '#ffffff' }}
            >
              Get it on Google Play
            </a>
          </div>
        </section>
      ) : null}

      {app.privacyUrl || app.termsUrl ? (
        <nav aria-label={`${app.name} legal`} className="mx-auto flex max-w-[1360px] flex-wrap gap-5 px-6 py-10 text-sm">
          {app.privacyUrl ? (
            <a href={app.privacyUrl} className="text-ink-2 hover:text-ink">
              {app.name} privacy policy
            </a>
          ) : null}
          {app.termsUrl ? (
            <a href={app.termsUrl} className="text-ink-2 hover:text-ink">
              {app.name} terms
            </a>
          ) : null}
        </nav>
      ) : (
        <div className="h-24" />
      )}
    </>
  );
}
