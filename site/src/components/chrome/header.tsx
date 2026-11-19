import Image from 'next/image';
import Link from 'next/link';
import { ThemeToggle } from './theme-toggle';

const NAV = [
  { href: '/#apps', label: 'Apps' },
  { href: '/#business', label: 'For business' },
  { href: '/#games', label: 'Games' },
  { href: '/#studio', label: 'Studio' },
];

export function Header() {
  return (
    <header className="sticky top-0 z-40 border-b border-line bg-bg/80 backdrop-blur-xl">
      <nav aria-label="Main" className="mx-auto flex max-w-[1360px] flex-wrap items-center gap-x-6 gap-y-2 px-6 py-3">
        <Link href="/" className="flex items-center gap-2.5 font-display text-lg font-semibold">
          <Image src="/studio-mark.webp" alt="" width={28} height={28} className="rounded-lg" priority />
          Mindberzerk
        </Link>
        <ul className="hidden flex-1 flex-wrap gap-1 md:flex">
          {NAV.map((n) => (
            <li key={n.href}>
              <Link href={n.href} className="block rounded-full px-3.5 py-2.5 text-[15px] text-ink-2 transition-colors hover:bg-surface-2 hover:text-ink">
                {n.label}
              </Link>
            </li>
          ))}
        </ul>
        <span className="flex-1 md:hidden" />
        <ThemeToggle />
        <Link href="/#contact" className="rounded-full bg-inverse px-[18px] py-[11px] text-[15px] font-semibold text-on-inverse">
          Contact
        </Link>
      </nav>
    </header>
  );
}
