/**
 * Phase 8 republish: Pocket's wallpaper follows its pages.
 *
 * Mirrors `republishDistroAction`: reads the LIVE draft, sets only
 * `wallpaperFollowsPages: true`, saves the draft, then publishes through
 * `publishDistro` with `distroSku: null` so entitlements are untouched.
 *
 * Older builds ignore the key, and the Linux distros never author it: no Linux
 * desktop pans its wallpaper between workspaces.
 *
 *   cd admin
 *   npx tsx --env-file=.env.local --conditions=react-server scripts/republish-phase8.ts          # dry run
 *   npx tsx --env-file=.env.local --conditions=react-server scripts/republish-phase8.ts --apply
 */
import { publishDistro } from '@/lib/g-launcher/distro-publish';
import { readDraft, writeDraft } from '@/lib/g-launcher/themes';
import { readDraftAssetBytes } from '@/lib/g-launcher/distro-draft-assets';
import { readPlayBuild } from '@/lib/g-launcher/distro-io';
import { canonicalThemeJson, type ThemeSpecJson } from '@/lib/g-launcher/theme-spec';

const APP = 'g-launcher' as const;
const APPLY = process.argv.includes('--apply');

/** The distros whose wallpaper follows their pages by default. */
const FOLLOWS = ['pocket-theme'];

async function main(): Promise<void> {
  const play = await readPlayBuild(APP);
  for (const id of FOLLOWS) {
    const draft = await readDraft(APP, id);
    if (!draft) {
      console.log(`${id}: NO DRAFT, skipped`);
      continue;
    }
    const min = draft.spec.minAppVersion ?? 0;
    const next: ThemeSpecJson = { ...draft.spec, wallpaperFollowsPages: true };
    const canon = JSON.parse(canonicalThemeJson(next));
    console.log(
      `${id}: packVersion=${draft.packVersion} min=${min} play=${play}` +
        ` wallpaperFollowsPages ${String(draft.spec.wallpaperFollowsPages)} -> ${canon.wallpaperFollowsPages}`,
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
    if (published.ok) console.log(`  ${JSON.stringify(published).slice(0, 200)}`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
