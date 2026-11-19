'use client';

import { useState, type FormEvent } from 'react';

/**
 * The contact and enquiry form.
 *
 * Posts JSON to /api/contact. A 503 means delivery is not configured yet, and
 * the form turns into a prefilled mailto link instead of failing. Labels are
 * real <label>s and every field has an autocomplete hint.
 */

interface Topic {
  id: string;
  name: string;
}

interface Props {
  contactEmail: string;
  /** Topics for the "About" select. Ignored when `fixedApp` is set. */
  topics?: Topic[];
  /** Business pages pin the form to their product and ask business questions. */
  fixedApp?: Topic;
  /** Choices for the business "I am" select, from the page's audiences. */
  roles?: string[];
  submitLabel?: string;
  /** Visual skin: the default surface, or a tinted panel on a business page. */
  tone?: 'default' | 'tinted';
}

type State = { kind: 'idle' } | { kind: 'sending' } | { kind: 'sent' } | { kind: 'error'; message: string } | { kind: 'mailto'; href: string };

const field =
  'h-[52px] w-full rounded-[14px] border border-line-strong bg-surface px-4 text-base text-ink placeholder:text-ink-muted';
const tintedField = 'h-[52px] w-full rounded-[14px] border border-white/20 bg-black/25 px-4 text-base text-white';

export function ContactForm({ contactEmail, topics = [], fixedApp, roles, submitLabel = 'Send', tone = 'default' }: Props) {
  const [state, setState] = useState<State>({ kind: 'idle' });
  const input = tone === 'tinted' ? tintedField : field;
  const label = `flex flex-col gap-2 text-sm ${tone === 'tinted' ? 'text-white/80' : 'text-ink-2'}`;

  async function onSubmit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    const data = Object.fromEntries(new FormData(e.currentTarget)) as Record<string, string>;
    const payload: Record<string, string> = { ...data, app: fixedApp?.id ?? data.app ?? 'general' };
    setState({ kind: 'sending' });

    try {
      const res = await fetch('/api/contact', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(payload),
      });
      if (res.ok) return setState({ kind: 'sent' });
      if (res.status === 503) {
        const subject = encodeURIComponent(`${fixedApp?.name ?? 'Enquiry'} from ${payload.name ?? 'the website'}`);
        const body = encodeURIComponent(payload.message ?? '');
        return setState({ kind: 'mailto', href: `mailto:${contactEmail}?subject=${subject}&body=${body}` });
      }
      const { error } = (await res.json().catch(() => ({}))) as { error?: string };
      setState({ kind: 'error', message: error ?? 'The message could not be sent.' });
    } catch {
      setState({ kind: 'error', message: 'The message could not be sent.' });
    }
  }

  if (state.kind === 'sent') {
    return (
      <p role="status" className="m-0 font-display text-2xl font-semibold">
        Thanks. We will reply by email.
      </p>
    );
  }

  return (
    <form onSubmit={onSubmit} className="grid grid-cols-1 gap-4 sm:grid-cols-2" noValidate={false}>
      <label className={label}>
        Name
        <input name="name" required maxLength={120} autoComplete="name" className={input} />
      </label>
      <label className={label}>
        Email
        <input name="email" type="email" required maxLength={200} autoComplete="email" className={input} />
      </label>

      {fixedApp ? (
        <>
          <label className={label}>
            Company
            <input name="company_name" maxLength={160} autoComplete="organization" className={input} />
          </label>
          <label className={label}>
            Phone
            <input name="phone" type="tel" maxLength={40} autoComplete="tel" className={input} />
          </label>
          {roles && roles.length > 1 ? (
            <label className={`${label} sm:col-span-2`}>
              I am
              <select name="role" className={input} defaultValue={roles[0]}>
                {roles.map((r) => (
                  <option key={r}>{r}</option>
                ))}
              </select>
            </label>
          ) : null}
        </>
      ) : topics.length > 0 ? (
        <label className={`${label} sm:col-span-2`}>
          About
          <select name="app" className={input} defaultValue="general">
            {topics.map((t) => (
              <option key={t.id} value={t.id}>
                {t.name}
              </option>
            ))}
            <option value="general">Something else</option>
          </select>
        </label>
      ) : null}

      <label className={`${label} sm:col-span-2`}>
        Message
        <textarea name="message" required maxLength={5000} rows={5} className={`${input} h-auto resize-y py-3.5`} />
      </label>

      {/* Honeypot: off-screen and skipped by keyboard and screen readers. */}
      <div aria-hidden="true" className="absolute -left-[9999px] h-0 w-0 overflow-hidden">
        <label>
          Leave empty
          <input name="company" tabIndex={-1} autoComplete="off" />
        </label>
      </div>

      <div className="flex flex-wrap items-center gap-4 sm:col-span-2">
        <button
          type="submit"
          disabled={state.kind === 'sending'}
          className={`h-[52px] rounded-full px-7 font-semibold disabled:opacity-60 ${tone === 'tinted' ? 'bg-white text-[#0a0b0d]' : 'bg-inverse text-on-inverse'}`}
        >
          {state.kind === 'sending' ? 'Sending' : submitLabel}
        </button>
        {state.kind === 'error' ? (
          <p role="alert" className="m-0 text-sm">
            {state.message}{' '}
            <a href={`mailto:${contactEmail}`} className="underline underline-offset-4">
              {contactEmail}
            </a>
          </p>
        ) : null}
        {state.kind === 'mailto' ? (
          <a href={state.href} className="font-semibold underline underline-offset-4">
            Send it from your email app
          </a>
        ) : null}
      </div>
    </form>
  );
}
