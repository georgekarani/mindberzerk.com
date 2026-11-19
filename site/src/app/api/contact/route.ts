import { NextResponse } from 'next/server';
import nodemailer from 'nodemailer';
import { readRegistry } from '@/lib/catalog/read';

/**
 * Contact and business enquiry relay over the studio's Plesk SMTP.
 *
 * Routing: the `app` field picks the product. A product with a business inbox
 * in the registry gets its enquiries delivered there; everything else goes to
 * SITE_CONTACT_TO. The subject always names the product so one shared inbox
 * can still filter.
 *
 * Degrades rather than breaks: with any SMTP secret missing the route answers
 * 503 and the form offers a mailto link. Spam defences are a honeypot and a
 * per-instance rate limit, which is what a marketing form needs.
 */
export const runtime = 'nodejs';

const WINDOW_MS = 10 * 60 * 1000;
const MAX_PER_WINDOW = 5;
const hits = new Map<string, number[]>();

function limited(ip: string): boolean {
  const now = Date.now();
  const recent = (hits.get(ip) ?? []).filter((t) => now - t < WINDOW_MS);
  const blocked = recent.length >= MAX_PER_WINDOW;
  if (!blocked) recent.push(now);
  hits.set(ip, recent);
  // Keep the map bounded on a long-lived instance.
  if (hits.size > 5000) hits.delete(hits.keys().next().value!);
  return blocked;
}

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

/** Trims, strips control characters and caps length; header-safe for subjects. */
function clean(v: unknown, max: number): string {
  return String(v ?? '')
    .replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, '')
    .trim()
    .slice(0, max);
}

export async function POST(request: Request) {
  const host = process.env.SITE_SMTP_HOST;
  const port = Number(process.env.SITE_SMTP_PORT ?? '465');
  const user = process.env.SITE_SMTP_USER;
  const pass = process.env.SITE_SMTP_PASS;
  const defaultTo = process.env.SITE_CONTACT_TO;

  if (!host || !user || !pass || !defaultTo || !Number.isFinite(port)) {
    return NextResponse.json({ configured: false }, { status: 503 });
  }

  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: 'Expected JSON.' }, { status: 400 });
  }

  // A filled honeypot gets a success so the bot moves on, and no email.
  if (clean(body.company, 200)) return NextResponse.json({ ok: true });

  const name = clean(body.name, 120).replace(/[\r\n]/g, ' ');
  const email = clean(body.email, 200);
  const message = clean(body.message, 5000);
  const company = clean(body.company_name, 160);
  const phone = clean(body.phone, 40);
  const role = clean(body.role, 80);
  const appId = clean(body.app, 60) || 'general';

  if (!name) return NextResponse.json({ error: 'A name is required.' }, { status: 400 });
  if (!EMAIL.test(email)) return NextResponse.json({ error: 'That email does not look right.' }, { status: 400 });
  if (!message) return NextResponse.json({ error: 'A message is required.' }, { status: 400 });

  const ip = request.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
  if (limited(ip)) {
    return NextResponse.json({ error: 'Too many messages. Try again in a few minutes.' }, { status: 429 });
  }

  // An unknown app id is not an error: it is filed as general.
  const app = (await readRegistry()).find((a) => a.id === appId);
  const to = app?.business?.inbox && EMAIL.test(app.business.inbox) ? app.business.inbox : defaultTo;
  const topic = app ? app.name : 'General';
  const kind = app?.business && (company || phone || role) ? 'Business enquiry' : 'Contact';

  const lines = [
    `Name: ${name}`,
    `Email: ${email}`,
    ...(company ? [`Company: ${company}`] : []),
    ...(phone ? [`Phone: ${phone}`] : []),
    ...(role ? [`Role: ${role}`] : []),
    `About: ${topic}`,
    '',
    message,
  ];

  try {
    await nodemailer
      .createTransport({ host, port, secure: port === 465, auth: { user, pass } })
      .sendMail({
        // From must be the authenticated mailbox or Plesk may refuse the send;
        // the visitor rides in replyTo so replying just works.
        from: `"mindberzerk.com" <${user}>`,
        replyTo: { name: name.replace(/"/g, ''), address: email },
        to,
        subject: `[${kind}] ${topic}: ${name}`,
        text: `${lines.join('\n')}\n`,
      });
  } catch {
    return NextResponse.json({ error: 'The message could not be sent.' }, { status: 502 });
  }

  return NextResponse.json({ ok: true });
}
