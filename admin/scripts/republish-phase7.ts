/**
 * Phase 7 republish: each distro's default clock face.
 *
 * Mirrors `republishDistroAction`: reads the LIVE draft, sets only
 * `desklets.skins.clock.face` (merged, so every other skin key survives),
 * saves the draft, then publishes through `publishDistro` with
 * `distroSku: null` so entitlements are untouched.
 *
 * Older builds ignore the key: a skin prop they do not read changes nothing.
 *
 *   cd admin
 *   npx tsx --env-file=.env.local --conditions=react-server scripts/republish-phase7.ts          # dry run
 *   npx tsx --env-file=.env.local --conditions=react-server scripts/republish-phase7.ts --apply
 */
import { publishDistro } from '@/lib/g-launcher/distro-publish';
import { readDraft, writeDraft } from '@/lib/g-launcher/themes';
import { readDraftAssetBytes } from '@/lib/g-launcher/distro-draft-assets';
import { readPlayBuild } from '@/lib/g-launcher/distro-io';
import { canonicalThemeJson, type ThemeSpecJson } from '@/lib/g-launcher/theme-spec';

const APP = 'g-launcher' as const;
const APPLY = process.argv.includes('--apply');

/** The face each distro's clock wears until its user picks another. */
const FACES: Record<string, 'analog' | 'binary' | 'digits'> = {
  'kde-plasma-6': 'analog',
  'pocket-theme': 'analog',
  'garuda-dr460nized-theme': 'binary',
  terminal: 'digits',
  'arch-linux-theme': 'digits',
  'endeavouros-theme': 'digits',
};

type Obj = Record<string, unknown>;
const obj = (v: unknown): Obj => (v && typeof v === 'object' && !Array.isArray(v) ? (v as Obj) : {});

/** The spec with only `desklets.skins.clock.face` changed. */
function withFace(spec: ThemeSpecJson, face: string): ThemeSpecJson {
  const desklets = obj(spec.desklets);
  const skins = obj(desklets.skins);
  return {
    ...spec,
    desklets: { ...desklets, skins: { ...skins, clock: { ...obj(skins.clock), face } } },
  };
}

async function main(): Promise<void> {
  const play = await readPlayBuild(APP);
  for (const [id, face] of Object.entries(FACES)) {
    const draft = await readDraft(APP, id);
    if (!draft) {
      console.log(`${id}: NO DRAFT, skipped`);
      continue;
    }
    const min = draft.spec.minAppVersion ?? 0;
    const next = withFace(draft.spec, face);
    const canon = JSON.parse(canonicalThemeJson(next));
    const before = obj(obj(obj(draft.spec.desklets).skins).clock).face;
    console.log(
      `${id}: packVersion=${draft.packVersion} min=${min} play=${play}` +
        ` face ${String(before)} -> ${canon.desklets?.skins?.clock?.face}`,
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
