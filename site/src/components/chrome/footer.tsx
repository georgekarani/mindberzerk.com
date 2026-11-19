import Link from 'next/link';
import { APP_STORE_DEVELOPER_URL, CONTACT_EMAIL, PLAY_DEVELOPER_URL, STUDIO_NAME } from '@/lib/site';

export function Footer() {
  return (
    <footer className="border-t border-line">
      <div className="mx-auto flex max-w-[1360px] flex-wrap justify-between gap-4 px-6 py-8 text-sm text-ink-muted">
        <span>
          © {new Date().getFullYear()} {STUDIO_NAME}
        </span>
        <ul className="flex flex-wrap gap-5">
          <li><a href={PLAY_DEVELOPER_URL} className="text-ink-2 hover:text-ink">Google Play</a></li>
          <li><a href={APP_STORE_DEVELOPER_URL} className="text-ink-2 hover:text-ink">App Store</a></li>
          <li><a href={`mailto:${CONTACT_EMAIL}`} className="text-ink-2 hover:text-ink">{CONTACT_EMAIL}</a></li>
          <li><Link href="/#contact" className="text-ink-2 hover:text-ink">Contact</Link></li>
        </ul>
      </div>
    </footer>
  );
}
