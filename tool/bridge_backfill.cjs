/**
 * Copies every record the dashboard manages from the admin database
 * ((default)) into the app's database (tsl-app) through the bridge
 * (functions/src/bridge), for the switch-over. After that the bridge
 * triggers keep them in step.
 *
 *   node tool/bridge_backfill.cjs            dry run: prints what would change
 *   node tool/bridge_backfill.cjs --apply    writes tsl-app and sign-in accounts
 *
 * Reads the admin database, never writes it. Uses the Firebase CLI's login.
 * Build the functions first (npm --prefix functions run build).
 */
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const req = require('node:module').createRequire(path.join(__dirname, '../functions/package.json'));
const { initializeApp, applicationDefault } = req('firebase-admin/app');
const cli = require('/opt/homebrew/lib/node_modules/firebase-tools/lib/auth.js');
const api = require('/opt/homebrew/lib/node_modules/firebase-tools/lib/api.js');

const PROJECT = 'tsl-facility-manager';
const APPLY = process.argv.includes('--apply');

// The CLI's login as application default credentials, in an owner-only
// temporary file deleted on exit.
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tsl-bridge-'));
const adc = path.join(dir, 'adc.json');
fs.writeFileSync(adc, JSON.stringify({
  type: 'authorized_user',
  client_id: api.clientId(),
  client_secret: api.clientSecret(),
  refresh_token: cli.getGlobalDefaultAccount().tokens.refresh_token,
  quota_project_id: PROJECT,
}), { mode: 0o600 });
process.env.GOOGLE_APPLICATION_CREDENTIALS = adc;
process.on('exit', () => fs.rmSync(dir, { recursive: true, force: true }));

// Set up the app before the functions code, which reuses it.
initializeApp({ projectId: PROJECT, credential: applicationDefault() });
const { adminDb, BRIDGED, syncAdminRecord } = require(path.join(__dirname, '../functions/lib/bridge/sync.js'));
const { pullWorkOrder } = require(path.join(__dirname, '../functions/lib/bridge/shared.js'));

// Facilities and staff first, so names can be filled in as records arrive.
const ORDER = ['location', 'staff', 'zone', 'assets', 'inventory', 'documents', 'client', 'sla_schedules'];

async function main() {
  const totals = {};
  for (const collection of ORDER.filter((c) => BRIDGED.includes(c))) {
    const snap = await adminDb.collection(collection).get();
    console.log(`\n## ${collection} (${snap.size})`);
    for (const doc of snap.docs) {
      const steps = await syncAdminRecord(collection, doc.id, undefined, doc.data(), { apply: APPLY, forcePassword: true });
      for (const s of steps) {
        totals[s.action] = (totals[s.action] ?? 0) + 1;
        if (s.action === 'unchanged') continue;
        const verb = APPLY ? s.action : `would ${s.action}`;
        console.log(`  ${verb.padEnd(16)} ${s.target}${s.detail ? `  (${s.detail})` : ''}`);
      }
    }
  }
  // Then the dashboard's existing work orders, now that people and places exist.
  const orders = await adminDb.collection('work_order').get();
  console.log(`\n## work_order (${orders.size})`);
  for (const doc of orders.docs) {
    for (const s of await pullWorkOrder(doc.id, undefined, doc.data(), { apply: APPLY })) {
      totals[s.action] = (totals[s.action] ?? 0) + 1;
      if (s.action === 'unchanged') continue;
      console.log(`  ${(APPLY ? s.action : `would ${s.action}`).padEnd(16)} ${s.target}${s.detail ? `  (${s.detail})` : ''}`);
    }
  }
  console.log(`\n${APPLY ? 'Done' : 'Dry run, nothing written'}: ${Object.entries(totals).map(([k, n]) => `${n} ${k}`).join(', ')}`);
}

main().then(() => process.exit(0), (e) => { console.error(e); process.exit(1); });
