import type { NextConfig } from 'next';

/**
 * The public studio site. It holds no credentials: every input is a public CDN
 * object or a file in this folder, and the only server-side side effect is the
 * contact relay.
 */
const nextConfig: NextConfig = {
  poweredByHeader: false,
  images: {
    // App icons and screens published by the panel live on the public CDN.
    remotePatterns: [{ protocol: 'https', hostname: 'cdn.mindberzerk.com', pathname: '/site/**' }],
  },
  async redirects() {
    // G VPN's landing lives at /gvpn on the panel today. Until it is ported here,
    // that address lands on the template page; temporary, so it can flip back.
    return [{ source: '/gvpn', destination: '/g-vpn', permanent: false }];
  },
};

export default nextConfig;
