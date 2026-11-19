import Image from 'next/image';
import { Display, Eyebrow } from '@/components/ui';
import { readStorefront, usd, type Distro } from '@/lib/g-launcher/distros';

/**
 * G Launcher's storefront: the free distros, every paid distro that is live
 * in the catalogue, and the bundles. Purchases happen in the app through Play
 * billing, so each offer links to the Play listing.
 */

function DistroCard({ distro, href }: { distro: Distro; href: string }) {
  const free = distro.priceUsd === undefined;
  return (
    <li
      className={`relative isolate flex flex-col justify-end overflow-hidden rounded-[22px] text-white ${free ? 'min-h-[200px]' : 'aspect-[9/14]'}`}
      style={{ backgroundImage: `linear-gradient(165deg, ${distro.gradient[0]}, ${distro.gradient[1]})` }}
    >
      {distro.image ? (
        <Image src={distro.image} alt="" fill sizes="(min-width: 1024px) 200px, 45vw" className="-z-10 object-cover" />
      ) : null}
      <div className="bg-gradient-to-t from-black/85 to-transparent p-5 pt-16">
        <p className="m-0 text-[13px] text-white/75">{distro.note}</p>
        <div className="mt-1 flex flex-wrap items-end justify-between gap-2">
          <h4 className="m-0 font-display text-xl font-semibold">{distro.title}</h4>
          {free ? (
            <span className="font-semibold">Free</span>
          ) : (
            <a href={href} className="relative rounded-full bg-white px-4 py-2 text-sm font-semibold text-[#0a0b0d]">
              {usd(distro.priceUsd!)}
              <span className="sr-only">, buy {distro.title}</span>
            </a>
          )}
        </div>
      </div>
    </li>
  );
}

export async function GLauncherStore({ playHref }: { playHref: string }) {
  const { free, paid, bundles } = await readStorefront();
  const lead = bundles.find((b) => b.lead);
  const rest = bundles.filter((b) => !b.lead);
  const priceSet = new Set(paid.map((d) => d.priceUsd));
  const eachPrice = priceSet.size === 1 ? ` · ${usd(paid[0].priceUsd!)} each` : '';

  return (
    <>
      <section id="distros" aria-labelledby="distros-h" className="mx-auto max-w-[1360px] scroll-mt-20 px-6 pt-36">
        <Display id="distros-h">
          {free.length} free. {paid.length} to own.
        </Display>

        <Eyebrow className="mb-4 mt-14">Included</Eyebrow>
        <ul className="m-0 grid list-none grid-cols-1 gap-4 p-0 sm:grid-cols-3">
          {free.map((d) => (
            <DistroCard key={d.id} distro={d} href={playHref} />
          ))}
        </ul>

        {paid.length ? (
          <>
            <Eyebrow className="mb-4 mt-14">One-time purchase{eachPrice}</Eyebrow>
            <ul className="m-0 grid list-none grid-cols-2 gap-4 p-0 md:grid-cols-4 lg:grid-cols-7">
              {paid.map((d) => (
                <DistroCard key={d.id} distro={d} href={playHref} />
              ))}
            </ul>
          </>
        ) : null}
      </section>

      <section id="bundles" aria-labelledby="bundles-h" className="mx-auto max-w-[1360px] scroll-mt-20 px-6 pt-36">
        <Display id="bundles-h" className="mb-10">
          Bundles
        </Display>
        <div className="grid grid-cols-1 gap-4 md:grid-cols-2">
          {lead ? (
            <article
              className="flex min-h-[420px] flex-col justify-between gap-10 rounded-[28px] p-9 text-white md:row-span-2"
              style={{ backgroundImage: 'radial-gradient(120% 120% at 100% 0%, #e95420 0%, #7a1f2e 55%, #2c0b1f 100%)' }}
            >
              <div>
                <h3 className="m-0 font-display text-[40px] font-semibold leading-[1.05]">{lead.title}</h3>
                <p className="m-0 mt-3.5 text-[17px] text-white/85">{lead.summary}</p>
              </div>
              <div className="flex flex-wrap items-center justify-between gap-4">
                <span className="font-display text-[44px] font-semibold">{usd(lead.priceUsd)}</span>
                <a href={playHref} className="rounded-full bg-white px-6 py-3.5 font-semibold text-[#0a0b0d]">
                  Get it on Google Play
                </a>
              </div>
            </article>
          ) : null}
          {rest.map((b) => (
            <article key={b.sku} className="flex flex-col justify-between gap-6 rounded-[28px] border border-line bg-surface p-7">
              <div>
                <h3 className="m-0 font-display text-2xl font-semibold">{b.title}</h3>
                <p className="m-0 mt-2 text-ink-2">{b.summary}</p>
              </div>
              <div className="flex items-center justify-between">
                <span className="font-display text-[26px] font-semibold">{usd(b.priceUsd)}</span>
                <a href={playHref} className="rounded-full border border-line-strong px-[18px] py-[11px] font-medium hover:bg-surface-2">
                  Get<span className="sr-only"> {b.title}</span>
                </a>
              </div>
            </article>
          ))}
        </div>
      </section>
    </>
  );
}
