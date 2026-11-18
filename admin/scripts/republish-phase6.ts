/**
 * Phase 6 republish of Terminal and KDE Plasma 6.
 *
 * Mirrors `republishDistroAction`: reads the LIVE draft (the repo theme.json can
 * be stale), sets only the two Phase 6 fields, saves the draft, then publishes
 * through `publishDistro` with `distroSku: null` so entitlements are untouched.
 *
 *   cd admin
 *   npx tsx --env-file=.env.local --conditions=react-server scripts/republish-phase6.ts          # dry run
 *   npx tsx --env-file=.env.local --conditions=react-server scripts/republish-phase6.ts --apply
 */
import { publishDistro } from '@/lib/g-launcher/distro-publish';
import { readDraft, writeDraft } from '@/lib/g-launcher/themes';
import { readDraftAssetBytes } from '@/lib/g-launcher/distro-draft-assets';
import { readPlayBuild } from '@/lib/g-launcher/distro-io';
import { canonicalThemeJson, type ThemeSpecJson } from '@/lib/g-launcher/theme-spec';

const APP = 'g-launcher' as const;
const APPLY = process.argv.includes('--apply');

/** The Phase 6 values per pack id. Only these keys change. */
const CHANGES: Record<string, (spec: ThemeSpecJson) => ThemeSpecJson> = {
  terminal: (s) => ({ ...s, layout: { ...s.layout, launchAnimation: 'none' } }),
  'kde-plasma-6': (s) => ({
    ...s,
    accentFromWallpaper: true,
    layout: { ...s.layout, launchAnimation: 'fade' },
  }),
};

async function main(): Promise<void> {
  const play = await readPlayBuild(APP);
  for (const [id, change] of Object.entries(CHANGES)) {
    const draft = await readDraft(APP, id);
    if (!draft) {
      console.log(`${id}: NO DRAFT, skipped`);
      continue;
    }
    const min = draft.spec.minAppVersion ?? 0;
    const next = change(draft.spec);
    const json = JSON.parse(canonicalThemeJson(next));
    console.log(
      `${id}: packVersion=${draft.packVersion} min=${min} play=${play} sku=${draft.sku}` +
        ` before={launch:${draft.spec.layout.launchAnimation}, wall:${draft.spec.accentFromWallpaper}}` +
        ` canon={launch:${json.layout?.launchAnimation}, wall:${json.accentFromWallpaper}}`,
    );
    if (play != null && min > play) {
      console.log(`  refused: needs build ${min}, Play serves ${play}`);
      continue;
    }
    const { assets, missing } = await readDraftAssetBytes(APP, id);
    if (missing.length) {
      console.log(`  refused: assets missing ${missing.join(', ')}`);
      continue;
    }
    if (!APPLY) continue;

    await writeDraft(APP, { ...draft, spec: next });
    const published = await publishDistro({
      app: APP,
      theme: {
        packId: draft.id,
        minAppVersion: min,
        sku: draft.sku,
        title: draft.title,
        summary: draft.summary,
        spec: next,
        assets: assets.map((a) => ({ file: a.name, bytes: a.bytes })),
      },
      icons: null,
      // Null keeps the live entitlement exactly as published.
      distroSku: null,
      distroTitle: draft.title,
      distroSummary: draft.summary,
    });
    console.log(`  publish: ${published.ok ? 'ok' : `FAILED ${published.error}`}`);
    if (published.ok) console.log(`  ${JSON.stringify(published).slice(0, 400)}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
