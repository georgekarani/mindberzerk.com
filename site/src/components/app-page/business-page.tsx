import { ContactForm } from '@/components/contact-form';
import { StoreBadges } from '@/components/store-badges';
import { AppIcon, ButtonLink, Display, StatList } from '@/components/ui';
import { platformLine } from '@/lib/catalog/links';
import type { AppEntry, BusinessPitch } from '@/lib/catalog/types';
import { inkOn } from '@/lib/color';
import { CONTACT_EMAIL } from '@/lib/site';
import { formatAsOf, type ShownStat } from '@/lib/stats/read';

/**
 * The business page template, for a product that sells to businesses
 * and has no site of its own. It says who the product serves, then asks for
 * an enquiry that is routed to the product's inbox.
 *
 * Plans and prices appear only once they exist in the registry: a page with
 * invented prices is worse than a page that asks the business to talk.
 */

interface Props {
  app: AppEntry & { business: BusinessPitch };
  stats: ShownStat[];
  statsSource: { source: string; asOf: string };
}

export function BusinessPage({ app, stats, statsSource }: Props) {
  const { business } = app;
  const ctaInk = inkOn(app.tint);

  return (
    <>
      <section
        className="relative overflow-hidden text-white"
        style={{ backgroundColor: app.ground, backgroundImage: `radial-gradient(110% 90% at 85% 0%, ${app.tint}38 0%, transparent 55%)` }}
      >
        <div className="mx-auto flex min-h-[620px] max-w-[1360px] flex-wrap items-end justify-between gap-12 px-6 pb-24 pt-28">
          <div className="flex-[1_1_620px]">
            <AppIcon src={app.icon} size={80} className="mb-7" />
            <p className="m-0 mb-4 text-sm uppercase tracking-[0.08em]" style={{ color: app.tint }}>
              {app.name} for {business.forWhom}
            </p>
            <Display as="h1" size="hero" className="max-w-[920px]">
              {business.headline}
            </Display>
            <div className="mt-9 flex flex-wrap gap-3.5">
              <a href="#enquire" className="rounded-full px-[26px] py-4 text-[17px] font-semibold" style={{ backgroundColor: app.tint, color: ctaInk }}>
                {business.cta}
              </a>
            </div>
          </div>
          <div className="flex flex-col gap-3">
            <StatList stats={stats} size="lg" tone="text-white/70" />
            {stats.length ? (
              <p className="m-0 text-[13px] text-white/60">
                Installs on {statsSource.source}, {formatAsOf(statsSource.asOf)}
              </p>
            ) : null}
            <p className="m-0 text-[15px] text-white/75">{platformLine(app.platforms)}</p>
          </div>
        </div>
      </section>

      {business.audiences.length ? (
        <section aria-label="Who it is for" className="mx-auto max-w-[1360px] px-6 pt-28">
          <div className="grid grid-cols-1 gap-4 md:grid-cols-3">
            {business.audiences.map((a) => (
              <article key={a.title} className="flex min-h-[220px] flex-col justify-between gap-8 rounded-3xl border border-line bg-surface p-8">
                <h2 className="m-0 font-display text-[30px] font-semibold">{a.title}</h2>
                <p className="m-0 text-ink-2">{a.body}</p>
              </article>
            ))}
          </div>
        </section>
      ) : null}

      <section aria-labelledby="product-h" className="mx-auto flex max-w-[1360px] flex-wrap items-end justify-between gap-8 px-6 pt-36">
        <div className="max-w-[640px]">
          <Display id="product-h" size="block">
            {app.tagline}
          </Display>
        </div>
        <StoreBadges app={app} />
      </section>

      <section id="enquire" aria-labelledby="enquire-h" className="mt-36 scroll-mt-20 text-white" style={{ backgroundColor: app.ground }}>
        <div className="mx-auto flex max-w-[1360px] flex-wrap gap-14 px-6 py-24">
          <div className="flex-[1_1_320px]">
            <Display id="enquire-h">{business.cta}</Display>
          </div>
          <div className="flex-[2_1_560px]">
            <ContactForm
              contactEmail={CONTACT_EMAIL}
              fixedApp={{ id: app.id, name: app.name }}
              roles={business.audiences.map((a) => a.title)}
              submitLabel="Send enquiry"
              tone="tinted"
            />
          </div>
        </div>
      </section>

      <div className="mx-auto flex max-w-[1360px] flex-wrap gap-5 px-6 py-10 text-sm">
        <ButtonLink href="/#business" variant="ghost">
          More for business
        </ButtonLink>
      </div>
    </>
  );
}
