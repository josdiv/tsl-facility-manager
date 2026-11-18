/**
 * One-off copy of the first-draft records in the live (default) database into
 * the app's tsl-app database, converted to docs/firestore-schema.md.
 *
 * Reads (default), never writes it. Uses the Firebase CLI's login.
 *
 *   node tool/migrate_default_to_tsl_app.cjs             dry run: prints the plan
 *   node tool/migrate_default_to_tsl_app.cjs --apply     writes tsl-app
 *
 * Left out on purpose: work orders, messages and status logs (test entries),
 * and people, whose sign-in accounts need real email addresses. Facilities
 * are copied without a GPS position until one is known.
 */
const path = require('node:path');
// Firebase Admin comes from the functions project.
const req = require('node:module').createRequire(path.join(__dirname, '../functions/package.json'));
const { initializeApp, applicationDefault } = req('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue } = req('firebase-admin/firestore');
const cli = require('/opt/homebrew/lib/node_modules/firebase-tools/lib/auth.js');
const api = require('/opt/homebrew/lib/node_modules/firebase-tools/lib/api.js');

const PROJECT = 'tsl-facility-manager';
const APPLY = process.argv.includes('--apply');

// The CLI's login, as application default credentials in an owner-only
// temporary file that is deleted when the script ends.
const fs = require('node:fs');
const os = require('node:os');
const account = cli.getGlobalDefaultAccount();
const credentialsFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'tsl-migrate-')), 'adc.json');
fs.writeFileSync(credentialsFile, JSON.stringify({
  type: 'authorized_user',
  client_id: api.clientId(),
  client_secret: api.clientSecret(),
  refresh_token: account.tokens.refresh_token,
}), { mode: 0o600 });
process.env.GOOGLE_APPLICATION_CREDENTIALS = credentialsFile;
process.on('exit', () => fs.rmSync(path.dirname(credentialsFile), { recursive: true, force: true }));
const app = initializeApp({ projectId: PROJECT, credential: applicationDefault() });
const source = getFirestore(app); // (default): read only
const target = getFirestore(app, 'tsl-app');

const lower = (s, fallback) => (typeof s === 'string' && s.trim() ? s.trim().toLowerCase().replace(/\s+/g, '_') : fallback);
const when = (v) => (v instanceof Timestamp ? v : Timestamp.now());
/** "2026-12-15" as Lagos midnight (UTC+1). */
const lagosDate = (s) => (typeof s === 'string' && /^\d{4}-\d{2}-\d{2}/.test(s) ? Timestamp.fromMillis(Date.parse(`${s.slice(0, 10)}T00:00:00+01:00`)) : null);
const audit = (d) => ({ createdAt: when(d.createdAt), createdBy: 'migration', updatedAt: Timestamp.now(), updatedBy: 'migration' });

async function main() {
  const all = async (name) => (await source.collection(name).get()).docs;
  const writes = [];
  const put = (p, data) => writes.push([p, data]);

  const locations = await all('location');
  const zones = await all('zone');
  const assets = await all('assets');
  const locationIds = new Set(locations.map((d) => d.id));

  for (const doc of zones) {
    const d = doc.data();
    if (!locationIds.has(d.locationId)) { console.log(`skip zone ${doc.id}: unknown location`); continue; }
    put(`zones/${doc.id}`, { locationId: d.locationId, name: d.name, description: d.description ?? null, status: 'active', ...audit(d) });
  }
  const zoneLocation = Object.fromEntries(zones.map((z) => [z.id, z.data().locationId]));
  const zoneName = Object.fromEntries(zones.map((z) => [z.id, z.data().name]));

  for (const doc of locations) {
    const d = doc.data();
    put(`locations/${doc.id}`, {
      name: d.name,
      type: ['office', 'warehouse', 'shopping_mall', 'residential', 'industrial'].includes(lower(d.type)) ? lower(d.type) : 'other',
      address: d.address ?? d.addresss ?? '',
      geo: null, // Not known yet: clock-in stays off until the admin sets it.
      radiusM: Number(d.radius) > 0 ? Number(d.radius) : 100,
      timeZone: 'Africa/Lagos',
      siteManagerId: null,
      siteManagerName: null,
      zoneCount: zones.filter((z) => z.data().locationId === doc.id).length,
      assetCount: assets.filter((a) => zoneLocation[a.data().zoneId] === doc.id).length,
      status: lower(d.status, 'active') === 'inactive' ? 'inactive' : 'active',
      ...audit(d),
    });
  }

  for (const doc of assets) {
    const d = doc.data();
    const locationId = zoneLocation[d.zoneId];
    if (!locationId) { console.log(`skip asset ${doc.id}: its zone ${d.zoneId} wasn't found`); continue; }
    put(`assets/${doc.id}`, {
      // Keep a reference that's already in AST-000000 form; others get one
      // from the assignAssetRef function.
      ...(/^AST-\d{6}$/.test(doc.id) ? { ref: doc.id } : {}),
      locationId,
      zoneId: d.zoneId,
      zoneName: zoneName[d.zoneId] ?? null,
      equipmentName: d.equipmentName,
      nextServiceAt: lagosDate(d.nextService ?? d.nextServiceDate),
      status: ['active', 'maintenance', 'inactive'].includes(lower(d.status)) ? lower(d.status) : 'active',
      ...audit(d),
    });
  }

  for (const doc of await all('inventory')) {
    const d = doc.data();
    if (!locationIds.has(d.locationId)) { console.log(`skip stock ${doc.id}: unknown location`); continue; }
    const quantity = Number(d.quantity) || 0;
    const threshold = Number(d.alertThreshold) || 0;
    put(`inventory/${doc.id}`, {
      locationId: d.locationId,
      itemName: d.itemName,
      quantity,
      alertThreshold: threshold,
      stockStatus: quantity === 0 ? 'out' : quantity <= threshold ? 'low' : 'ok',
      photoPath: null,
      status: lower(d.status, 'active') === 'inactive' ? 'inactive' : 'active',
      ...audit(d),
    });
  }

  for (const doc of await all('sla_schedules')) {
    const d = doc.data();
    const locationId = locationIds.has(d.locationAsset) ? d.locationAsset : null;
    if (!locationId) { console.log(`skip SLA ${doc.id}: location ${d.locationAsset} not found`); continue; }
    put(`slaSchedules/${doc.id}`, {
      task: d.task,
      description: null,
      locationId,
      assetId: null,
      frequency: lower(d.frequency, 'weekly'),
      startAt: lagosDate(d.startDate) ?? Timestamp.now(),
      dueTime: String(d.dueTime ?? '09:00').slice(0, 5),
      priority: lower(d.priority, 'high'),
      // Staff accounts aren't copied yet, so nobody is assigned.
      assignedToId: null,
      supervisorId: null,
      nextRunAt: null,
      lastRunAt: null,
      // Paused: its name says weekly but it's set to daily. Check, assign
      // and switch it on from the dashboard.
      status: 'inactive',
      ...audit(d),
    });
  }

  for (const doc of await all('client')) {
    const d = doc.data();
    const id = String(d.clientName ?? doc.id).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 40);
    put(`companies/${id}`, {
      name: d.clientName,
      status: 'active',
      monthlyWorkOrderLimit: null,
      locationIds: [], // Which facilities this client uses isn't recorded yet.
      contactEmail: d.clientEmail ?? null,
      contactPhone: d.clientPhone ?? null,
      ...audit(d),
    });
  }

  // Reference counters start fresh. AST-762600 is far from AST-000001.
  for (const [name, next] of [['workOrders', 1001], ['requisitions', 1001], ['assets', 1], ['inventory', 1]]) {
    put(`counters/${name}`, { next });
  }

  for (const [p, data] of writes) {
    const summary = data.name ?? data.equipmentName ?? data.itemName ?? data.task ?? JSON.stringify(data);
    console.log(`${APPLY ? 'write' : 'would write'}  tsl-app/${p}  ${summary}`);
  }
  if (!APPLY) { console.log(`\nDry run: ${writes.length} documents. Nothing was written.`); return; }

  // Never overwrite something already in tsl-app.
  const batch = target.batch();
  for (const [p, data] of writes) batch.create(target.doc(p), data);
  await batch.commit();
  console.log(`\nWrote ${writes.length} documents to tsl-app.`);
}

main().then(() => process.exit(0), (e) => { console.error(e.message ?? e); process.exit(1); });
