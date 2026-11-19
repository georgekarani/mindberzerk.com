import Image from 'next/image';
import Link from 'next/link';
import type { ReactNode } from 'react';
import type { ShownStat } from '@/lib/stats/read';

/** App icon, or nothing: an app without real art shows its name alone, never a letter mark. */
export function AppIcon({ src, size, className = '' }: { src?: string; size: number; className?: string }) {
  if (!src) return null;
  return (
    <Image
      src={src}
      alt=""
      width={size}
      height={size}
      className={`shrink-0 ${className}`}
      style={{ width: size, height: size, borderRadius: Math.round(size * 0.24) }}
    />
  );
}

/** Label over value, in a row that wraps. Absent stats are absent rows. */
export function StatList({ stats, size = 'md', tone = 'text-ink-muted' }: { stats: ShownStat[]; size?: 'md' | 'lg'; tone?: string }) {
  if (stats.length === 0) return null;
  const value = size === 'lg' ? 'text-[34px]' : 'text-[26px]';
  return (
    <dl className="flex flex-wrap gap-x-8 gap-y-3">
      {stats.map((s) => (
        <div key={s.label}>
          <dt className={`text-[13px] ${tone}`}>{s.label}</dt>
          <dd className={`m-0 font-display font-semibold leading-tight ${value}`}>{s.value}</dd>
        </div>
      ))}
    </dl>
  );
}

type Variant = 'solid' | 'ghost';

const VARIANTS: Record<Variant, string> = {
  solid: 'bg-inverse text-on-inverse font-semibold',
  ghost: 'border border-line-strong font-medium hover:bg-surface-2',
};

/** A link styled as a pill button. External hrefs open in place, as store links should. */
export function ButtonLink({ href, children, variant = 'solid', className = '' }: { href: string; children: ReactNode; variant?: Variant; className?: string }) {
  const cls = `inline-flex min-h-11 items-center rounded-full px-[22px] py-3 transition-opacity hover:opacity-90 ${VARIANTS[variant]} ${className}`;
  return /^https?:/.test(href) ? (
    <a href={href} className={cls}>
      {children}
    </a>
  ) : (
    <Link href={href} className={cls}>
      {children}
    </Link>
  );
}

export function Eyebrow({ children, className = '' }: { children: ReactNode; className?: string }) {
  return <p className={`m-0 text-sm uppercase tracking-[0.08em] text-ink-muted ${className}`}>{children}</p>;
}

/** The display heading every section uses, sized by role. */
export function Display({ as: Tag = 'h2', size = 'section', id, className = '', children }: { as?: 'h1' | 'h2' | 'h3'; size?: 'hero' | 'section' | 'block'; id?: string; className?: string; children: ReactNode }) {
  const sizes = {
    hero: 'text-[clamp(44px,7vw,100px)] leading-[0.97] tracking-[-0.03em]',
    section: 'text-[clamp(32px,4.4vw,60px)] leading-[1.02] tracking-[-0.025em]',
    block: 'text-[clamp(26px,3vw,40px)] leading-[1.05] tracking-[-0.015em]',
  };
  return (
    <Tag id={id} className={`m-0 font-display font-semibold ${sizes[size]} ${className}`}>
      {children}
    </Tag>
  );
}
