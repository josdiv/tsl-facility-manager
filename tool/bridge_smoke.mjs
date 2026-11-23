/**
 * End-to-end check of the admin → app bridge on the local emulators. Writes
 * dashboard-style records into (default), waits for the bridge, and checks
 * tsl-app and sign-in. Never touches the live project.
 *
 *   firebase emulators:exec --only auth,firestore,functions \
 *     "node tool/bridge_smoke.mjs"
 *
 * Needs PHP, to make password hashes exactly like the dashboard's.
 */
import { execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';

if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error('Run inside firebase emulators:exec; refusing to touch the live project.');
  process.exit(1);
}
const require = createRequire(new URL('../functions/package.json', import.meta.url));
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');

const PROJECT = process.env.GCLOUD_PROJECT || 'tsl-facility-manager';
const app = initializeApp({ projectId: PROJECT });
const admin = getFirestore(app);
const tsl = getFirestore(app, 'tsl-app');
const auth = getAuth(app);

const bcrypt = (password) =>
  execFileSync('php', ['-r', 'echo password_hash($argv[1], PASSWORD_BCRYPT);', password]).toString();

async function until(what, check, ms = 30000) {
  const end = Date.now() + ms;
  for (;;) {
    const value = await check();
    if (value) return value;
    if (Date.now() > end) throw new Error(`timed out waiting for ${what}`);
    await new Promise((r) => setTimeout(r, 500));
  }
}
const appDoc = (path) => tsl.doc(path).get().then((s) => s.data());

async function _signIn(email, password) {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const res = await fetch(`http://${host}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, returnSecureToken: true }),
  });
  return res.ok;
}

const now = Timestamp.now();
let passed = 0;
const ok = (label) => { passed++; console.log(`  ✓ ${label}`); };

// Dashboard-style records, with its quirks.
await admin.doc('location/loc_t1').set({ locationId: 'loc_t1', name: 'Bridge Plaza', latitude: 9.07, longitute: 7.4, radius: '120', type: 'Office', siteManager: 'staff_t1', status: 'Active', zonesTotal: '1', assetTotal: '1', address: '1 Test Way', createdAt: now, createdBy: 'admin' });
await admin.doc('zone/zone_t1').set({ zoneId: 'zone_t1', name: 'Plant room', locationId: 'loc_t1', description: 'Generators', createdAt: now });
await admin.doc('staff/staff_t1').set({ staffId: 'staff_t1', name: 'Bridge Supervisor', email: 'Bridge.Sup@Example.com', role: 'Supervisor', status: 'Active', phone: '08031234501', designation: 'Facility Supervisor', assignedFacility: 'loc_t1', password: bcrypt('First-pass1'), createdAt: now });
await admin.doc('staff/staff_t2').set({ staffId: 'staff_t2', name: 'Bridge Tech', email: 'bridge.tech@example.com', role: 'Staff', status: 'Active', phone: '', designation: 'Technician', assignedFacility: null, password: '', createdAt: now });
await admin.doc('client/client_t1').set({ clientID: 'client_t1', clientName: 'Bridge Client Ltd.', clientEmail: 'contact@bridgeclient.ng', clientPhone: '+2348000000001', clientOTP: null, createdAt: now });
await admin.doc('assets/asset_t1').set({ assetId: 'AST-123456', equipmentName: 'Generator', zoneId: 'zone_t1', status: 'Active', nextService: '2026-12-15', createdAt: now });
await admin.doc('inventory/inv_t1').set({ inventoryId: 'inv_t1', itemName: 'Air filter', quantity: '4', alertThreshold: '5', locationId: 'loc_t1', status: 'Active', itemPhoto: null, createdAt: now });
await admin.doc('documents/DOC_t1').set({ docId: 'DOC_t1', title: 'Manual', category: 'Manuals', locationId: 'loc_t1', documentFile: 'https://thickservices.com/x/manual.pdf', createdAt: now });
await admin.doc('sla_schedules/sla_t1').set({ slaId: 'sla_t1', task: 'Weed the grasses', locationId: 'loc_t1', frequency: 'Weekday', dueTime: '09:00:00', startDate: '2026-11-20', priority: 'Medium', assignedTo: 'staff_t2', supervisedBy: 'staff_t1', status: 'Active', createdAt: now });

console.log('Admin → app copies');
const sup = await until('supervisor in tsl-app', () => appDoc('users/staff_t1'));
assert.equal(sup.role, 'supervisor');
assert.equal(sup.email, 'bridge.sup@example.com');
assert.equal(sup.phone, '+2348031234501');
assert.equal(sup.locationId, 'loc_t1');
assert.equal(sup.locationName, 'Bridge Plaza');
ok('staff → users, with facility and phone fixed up');

const loc = await until('facility', () => appDoc('locations/loc_t1'));
assert.equal(loc.radiusM, 120);
assert.equal(loc.geo.latitude, 9.07);
assert.equal(loc.geo.longitude, 7.4);
assert.equal(loc.siteManagerName, 'Bridge Supervisor');
ok('location → locations, despite "longitute" and a text radius');

const asset = await until('asset', () => appDoc('assets/asset_t1'));
assert.equal(asset.locationId, 'loc_t1');
assert.equal(asset.ref, 'AST-123456');
ok('asset gets its facility from its zone');

const stock = await until('stock', () => appDoc('inventory/inv_t1'));
assert.equal(stock.quantity, 4);
assert.equal(stock.stockStatus, 'low');
ok('stock, with status worked out from the quantity');

const sla = await until('SLA', () => appDoc('slaSchedules/sla_t1'));
assert.equal(sla.frequency, 'weekdays');
assert.equal(sla.createsJobs, false);
ok('SLA schedule, display only until the dashboard stops making its jobs');

const doc = await until('document', () => appDoc('documents/DOC_t1'));
assert.equal(doc.contentType, 'application/pdf');
assert.equal(doc.category, 'manual');
ok('document keeps its dashboard file link');

const company = await until('company', () => appDoc('companies/client_t1'));
const contact = await until('client user', () => appDoc('users/client_t1'));
assert.equal(company.name, 'Bridge Client Ltd.');
assert.deepEqual(company.locationIds, []);
assert.equal(contact.role, 'client');
assert.equal(contact.companyId, 'client_t1');
ok('client → company and a contact who signs in with a code');

console.log('Sign-in');
// The Auth emulator stores imported bcrypt hashes but can't check them at
// sign-in. Live Firebase does: checked on 22 Nov 2026 with PHP "$2y$" hashes
// (right password signs in, wrong one is refused).
const firstHash = await until('imported password', async () => (await auth.getUser('staff_t1')).passwordHash);
ok('the dashboard password is copied to the app sign-in');
const claims = await until('claims', async () => (await auth.getUser('staff_t1')).customClaims?.role && (await auth.getUser('staff_t1')).customClaims);
assert.deepEqual(claims.locs, ['loc_t1']);
ok('Storage claims set after the password import');
await until('technician', () => appDoc('users/staff_t2'));
assert.equal((await auth.getUser('staff_t2')).passwordHash, undefined);
ok('a staff member with an empty password gets an account without one');

await admin.doc('staff/staff_t1').update({ password: bcrypt('Second-pass2') });
await until('new password', async () => (await auth.getUser('staff_t1')).passwordHash !== firstHash);
ok('a password change in the dashboard reaches the app');

console.log('Changes');
const before = (await tsl.doc('users/staff_t1').get()).updateTime;
await admin.doc('staff/staff_t1').update({ lastLogin: now }); // a field the app doesn't use
await new Promise((r) => setTimeout(r, 3000));
assert.ok((await tsl.doc('users/staff_t1').get()).updateTime.isEqual(before));
ok('a change to nothing the app uses writes nothing (no loops)');

await admin.doc('staff/staff_t1').update({ name: 'Renamed Supervisor' });
await until('rename', async () => (await appDoc('users/staff_t1')).name === 'Renamed Supervisor');
await until('rename reaches the facility', async () => (await appDoc('locations/loc_t1')).siteManagerName === 'Renamed Supervisor');
ok('a rename reaches the user and the facility’s manager name');

await admin.doc('location/loc_t1').delete();
await until('facility retired', async () => (await appDoc('locations/loc_t1')).status === 'inactive');
ok('a deleted facility is marked inactive, not removed');
await admin.doc('staff/staff_t2').update({ status: 'Inactive' });
await until('account disabled', async () => (await auth.getUser('staff_t2')).disabled);
ok('a deactivated staff member’s sign-in is disabled');

console.log(`\nAll ${passed} bridge checks passed.`);
process.exit(0);
