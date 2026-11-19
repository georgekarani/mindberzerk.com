import Image from 'next/image';
import type { CSSProperties } from 'react';
import { StoreBadges } from '@/components/store-badges';
import { AppIcon, StatList } from '@/components/ui';
import { appHref, platformLine, soonLine } from '@/lib/catalog/links';
import type { AppEntry } from '@/lib/catalog/types';
import type { ShownStat } from '@/lib/stats/read';

/**
 * Home tiles. Each tile sits on its app's own dark ground in both themes, so
 * the copy on it is drawn in fixed light inks rather than theme tokens.
 *
 * Each tile carries the official store badges where the app is listed, and
 * one link to its page or its own website.
 */

interface TileProps {
  app: AppEntry;
  stats: ShownStat[];
}

const groundStyle = (app: AppEntry): CSSProperties => ({
  backgroundColor: app.ground,
  backgroundImage: `radial-gradient(120% 90% at 100% 0%, ${app.tint}33 0%, transparent 60%)`,
});

const LINK_STYLES = {
  pill: 'min-h-11 rounded-full border border-white/30 px-[22px] py-3 text-white hover:bg-white/10',
  compact: 'min-h-11 rounded-full border border-white/30 px-[18px] py-2.5 text-[15px] text-white hover:bg-white/10',
  text: 'min-h-11 text-[15px] text-white underline decoration-white/40 underline-offset-4',
} as const;

function TileLink({ app, look = 'pill' }: { app: AppEntry; look?: keyof typeof LINK_STYLES }) {
  const { href, external } = appHref(app);
  const cls = `inline-flex items-center font-semibold ${LINK_STYLES[look]}`;
  return (
    <a href={href} className={cls} {...(external ? { rel: 'noopener' } : {})}>
      {app.cta}
      <span className="sr-only">, {app.name}</span>
    </a>
  );
}

function Platforms({ app }: { app: AppEntry }) {
  const soon = soonLine(app.soon);
  return (
    <p className="m-0 text-sm text-white/70">
      {platformLine(app.platforms)}
      {soon ? ` · ${soon}` : ''}
    </p>
  );
}

/** Large flagship tile. With a cover the screen bleeds off the right edge. */
export function LargeTile({ app, stats }: TileProps) {
  return (
    <article
      className="relative isolate flex min-h-[440px] overflow-hidden md:min-h-[560px] rounded-[28px] text-white md:col-span-2 lg:row-span-2"
      style={groundStyle(app)}
    >
      {app.cover ? (
        <Image
          src={app.cover.src}
          alt={app.cover.alt}
          width={540}
          height={1089}
          sizes="(min-width: 1024px) 340px, 50vw"
          className="absolute -right-6 top-10 -z-10 w-[56%] max-w-[360px] rounded-[28px] shadow-[0_30px_80px_rgba(0,0,0,0.55)]"
        />
      ) : null}
      <div className={`flex flex-col justify-between gap-10 p-8 ${app.cover ? 'w-[54%] min-w-[240px]' : 'w-full'}`}>
        <div>
          <AppIcon src={app.icon} size={64} className="mb-5" />
          <h3 className={`m-0 font-display font-semibold tracking-[-0.02em] ${app.cover ? 'text-[32px]' : 'text-[clamp(48px,6vw,88px)] leading-[0.95]'}`}>
            {app.name}
          </h3>
          <p className="m-0 mt-2 max-w-[440px] text-[17px] text-white/80">{app.tagline}</p>
        </div>
        <div className="flex flex-col gap-6">
          <StatList stats={stats} tone="text-white/70" />
          <Platforms app={app} />
          <div className="flex flex-wrap items-center gap-3">
            <StoreBadges app={app} size="sm" onDark />
            <TileLink app={app} />
          </div>
        </div>
      </div>
    </article>
  );
}

/** Medium flagship tile: icon, line, numbers, action. */
export function MediumTile({ app, stats }: TileProps) {
  return (
    <article className="relative isolate flex flex-col justify-between gap-6 overflow-hidden rounded-[28px] p-7 text-white md:col-span-1 lg:col-span-2" style={groundStyle(app)}>
      <div className="flex items-start gap-4">
        <AppIcon src={app.icon} size={56} />
        <div>
          <h3 className="m-0 font-display text-2xl font-semibold">{app.name}</h3>
          <p className="m-0 mt-1 text-[15px] text-white/75">{app.tagline}</p>
        </div>
      </div>
      <StatList stats={stats} tone="text-white/70" />
      <Platforms app={app} />
      <div className="flex flex-wrap items-center gap-3">
        <StoreBadges app={app} size="sm" onDark />
        <TileLink app={app} look="compact" />
      </div>
    </article>
  );
}

/** Business product tile: what it is and who the business page is for. */
export function BusinessTile({ app, stats }: TileProps) {
  return (
    <article className="relative isolate flex min-h-[240px] flex-col gap-5 overflow-hidden rounded-[22px] border border-white/10 p-6 text-white" style={groundStyle(app)}>
      <AppIcon src={app.icon} size={52} />
      <div className="flex-1">
        <h3 className="m-0 font-display text-[22px] font-semibold">{app.name}</h3>
        <p className="m-0 mt-1.5 text-[15px] text-white/75">{app.tagline}</p>
      </div>
      <div className="flex flex-wrap items-end justify-between gap-3">
        {stats[0] ? (
          <p className="m-0 text-sm text-white/70">
            {stats.at(-1)!.value} {stats.at(-1)!.label.toLowerCase()}
          </p>
        ) : (
          <Platforms app={app} />
        )}
        <TileLink app={app} look="text" />
      </div>
    </article>
  );
}

/** Game tile; the lead game takes two columns. */
export function GameTile({ app, lead }: { app: AppEntry; lead: boolean }) {
  return (
    <article
      className={`relative isolate flex min-h-[340px] flex-col justify-end gap-5 overflow-hidden rounded-[28px] p-8 text-white ${lead ? 'md:col-span-2' : ''}`}
      style={groundStyle(app)}
    >
      {app.cover ? (
        <Image src={app.cover.src} alt={app.cover.alt} fill sizes="(min-width: 768px) 66vw, 100vw" className="-z-10 object-cover opacity-80" />
      ) : null}
      <AppIcon src={app.icon} size={lead ? 72 : 56} />
      <div className="flex flex-wrap items-end justify-between gap-5">
        <div>
          <h3 className={`m-0 font-display font-semibold ${lead ? 'text-[clamp(36px,4vw,56px)] leading-none' : 'text-2xl'}`}>{app.name}</h3>
          <p className="m-0 mt-2 text-white/75">
            {app.tagline} · {platformLine(app.platforms)}
          </p>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-3">
        <StoreBadges app={app} size="sm" onDark />
        <TileLink app={app} look="compact" />
      </div>
    </article>
  );
}
