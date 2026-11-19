import '@fontsource-variable/inter';
import '@fontsource-variable/space-grotesk';
import './globals.css';

import type { Metadata, Viewport } from 'next';
import Script from 'next/script';
import type { ReactNode } from 'react';
import { Footer } from '@/components/chrome/footer';
import { Header } from '@/components/chrome/header';
import { SITE_URL, STUDIO_NAME } from '@/lib/site';

const GA_ID = process.env.NEXT_PUBLIC_GA_MEASUREMENT_ID;

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: { default: STUDIO_NAME, template: `%s · ${STUDIO_NAME}` },
  description:
    'Mindberzerk Studio makes Tryst, G Launcher, G VPN and G Recovery, and apps for businesses.',
  icons: { icon: '/icon.png', apple: '/icon.png' },
  openGraph: { siteName: STUDIO_NAME, type: 'website', url: SITE_URL },
  twitter: { card: 'summary_large_image' },
};

export const viewport: Viewport = {
  themeColor: [
    { media: '(prefers-color-scheme: dark)', color: '#0a0b0d' },
    { media: '(prefers-color-scheme: light)', color: '#fbfbfa' },
  ],
};

/**
 * Replays the stored theme before first paint so a light-theme visitor never
 * sees a dark flash. Dark is the default; only an explicit choice switches.
 */
const THEME_BOOT = `try{var t=localStorage.getItem('theme');if(t==='light')document.documentElement.dataset.theme='light'}catch(e){}`;

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    // The boot script may set data-theme before React hydrates.
    <html lang="en" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOT }} />
      </head>
      <body className="min-h-dvh bg-bg text-ink">
        <a
          href="#main"
          className="sr-only focus:not-sr-only focus:fixed focus:left-4 focus:top-4 focus:z-50 focus:rounded-full focus:bg-inverse focus:px-4 focus:py-2 focus:text-on-inverse"
        >
          Skip to content
        </a>
        <Header />
        <main id="main">{children}</main>
        <Footer />
        {GA_ID ? (
          <>
            <Script src={`https://www.googletagmanager.com/gtag/js?id=${GA_ID}`} strategy="afterInteractive" />
            <Script id="ga" strategy="afterInteractive">
              {`window.dataLayer=window.dataLayer||[];function gtag(){dataLayer.push(arguments)}gtag('js',new Date());gtag('config','${GA_ID}');`}
            </Script>
          </>
        ) : null}
      </body>
    </html>
  );
}
