import { ButtonLink, Display } from '@/components/ui';

export default function NotFound() {
  return (
    <section className="mx-auto flex min-h-[60vh] max-w-[1360px] flex-col items-start justify-center gap-8 px-6 py-24">
      <Display as="h1" size="hero">
        Nothing here.
      </Display>
      <ButtonLink href="/">All apps</ButtonLink>
    </section>
  );
}
