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


console.log('Step 2: shared records');
await admin.doc('location/loc_t2').set({ locationId: 'loc_t2', name: 'Shared Tower', latitude: 9.1, longitude: 7.5, radius: 100, type: 'Office', siteManager: 'staff_t4', status: 'Active', createdAt: now });
for (const [id, name, role] of [['staff_t3', 'Tech Three', 'Staff'], ['staff_t4', 'Sup Four', 'Supervisor'], ['staff_t5', 'Tech Five', 'Staff'], ['staff_t6', 'Tech Six', 'Staff']]) {
  await admin.doc(`staff/${id}`).set({ staffId: id, name, email: `${id}@example.com`, role, status: 'Active', phone: '', designation: role, assignedFacility: 'loc_t2', password: '', createdAt: now });
}
await until('step 2 people', async () => (await appDoc('users/staff_t6')) && (await appDoc('locations/loc_t2')));

// A job made in the dashboard appears in the app.
await admin.doc('work_order/WO-777001').set({ workOrderId: 'WO-777001', title: 'Service the generator', description: 'Monthly service', type: 'SLA', priority: 'High', status: 'Open', locationId: 'loc_t2', assetId: '', assignedTo: 'staff_t3', supervisedBy: 'staff_t4', dueDate: '2026-12-01', dueTime: '10:30', attachments: ['https://thickservices.com/x/wo.jpg'], createdAt: now, createdBy: 'Admin' });
const job = await until('dashboard job in the app', () => appDoc('workOrders/WO-777001'));
assert.equal(job.ref, 'WO-777001');
assert.equal(job.type, 'sla');
assert.equal(job.priority, 'high');
assert.equal(job.assignedToName, 'Tech Three');
assert.equal(job.supervisorName, 'Sup Four');
assert.deepEqual(job.reportPhotos, ['https://thickservices.com/x/wo.jpg']);
assert.equal(job.dueAt.toMillis(), Date.parse('2026-12-01T09:30:00Z'));
ok('a job created in the dashboard appears in the app, with its people and photo');
await until('its timeline in the dashboard', async () => (await admin.collection('workorder_status').where('workOrderId', '==', 'WO-777001').get()).size > 0);
ok('the app’s timeline entries reach the dashboard’s job history');

// Progress in the app reaches the dashboard.
await tsl.doc('workOrders/WO-777001').update({ status: 'in_progress', startedAt: now, updatedBy: 'staff_t3' });
await until('In Progress in the dashboard', async () => (await admin.doc('work_order/WO-777001').get()).data().status === 'In Progress');
ok('starting the job in the app shows "In Progress" in the dashboard');

// A dashboard reassignment reaches the app.
await admin.doc('work_order/WO-777001').update({ assignedTo: 'staff_t5' });
await until('reassigned in the app', async () => (await appDoc('workOrders/WO-777001')).assignedToId === 'staff_t5');
assert.equal((await appDoc('workOrders/WO-777001')).assignedToName, 'Tech Five');
ok('reassigning in the dashboard reassigns in the app');

// Two quick changes in the app: the late echo of the first must not win.
await tsl.doc('workOrders/WO-777001').update({ assignedToId: 'staff_t3', assignedToName: 'Tech Three', updatedBy: 'staff_t4' });
await tsl.doc('workOrders/WO-777001').update({ assignedToId: 'staff_t6', assignedToName: 'Tech Six', updatedBy: 'staff_t4' });
await new Promise((r) => setTimeout(r, 6000));
assert.equal((await appDoc('workOrders/WO-777001')).assignedToId, 'staff_t6');
assert.equal((await admin.doc('work_order/WO-777001').get()).data().assignedTo, 'staff_t6');
ok('two quick reassignments in the app settle on the last, on both sides');

// A job reported in the app appears in the dashboard.
await tsl.doc('workOrders/appjob1').set({ ref: 'WO-9001', type: 'client', title: 'Leaking tap', description: 'Kitchen', priority: 'medium', status: 'open', locationId: 'loc_t2', locationName: 'Shared Tower', zoneId: null, zoneName: null, assetId: null, assetName: null, clientId: null, clientName: null, assignedToId: null, assignedToName: null, supervisorId: 'staff_t4', supervisorName: 'Sup Four', dueAt: now, reportPhotos: [], workPhotos: [], returnPhotos: [], inspectionChecks: [], inspectionPhotos: [], createdAt: now, createdBy: 'client_t1', updatedAt: now, updatedBy: 'client_t1' });
const copy = await until('app job in the dashboard', async () => (await admin.doc('work_order/WO-9001').get()).data());
assert.equal(copy.status, 'Open');
assert.equal(copy.source, 'app');
assert.equal(copy.createdBy, 'Client');
ok('a job reported in the app appears in the dashboard');

// Chat both ways, without copies bouncing back.
await tsl.collection('workOrders/WO-777001/messages').doc('m_app_1').set({ text: 'On site now', senderId: 'staff_t6', senderName: 'Tech Six', senderRole: 'staff', sentAt: now });
await until('app message in the dashboard', async () => (await admin.doc('workorder_message/msg_app_m_app_1').get()).exists);
await admin.doc('workorder_message/msg_d1').set({ msgId: 'msg_d1', workOrderId: 'WO-777001', senderId: 'staff_t4', senderType: 'supervisor', message: 'Thanks, send photos', sendDateTime: now });
const reply = await until('dashboard message in the app', () => appDoc('workOrders/WO-777001/messages/admin_msg_d1'));
assert.equal(reply.senderName, 'Sup Four');
await new Promise((r) => setTimeout(r, 3000));
assert.equal((await admin.doc('workorder_message/msg_app_admin_msg_d1').get()).exists, false);
ok('chat goes both ways, and nothing bounces back as a duplicate');

// Attendance and parts requests.
await tsl.doc('attendance/att1').set({ userId: 'staff_t6', userName: 'Tech Six', locationId: 'loc_t2', locationName: 'Shared Tower', status: 'clocked_in', attendanceStatus: 'present', clockInAt: now, clockInDistanceM: 12, clockInAccuracyM: 8, clockOutAt: null, source: 'app', createdAt: now });
const att = await until('attendance in the dashboard', async () => (await admin.doc('attendance/att_app_att1').get()).data());
assert.equal(att.status, 'Clocked In');
assert.equal(att.staffId, 'staff_t6');
ok('a clock-in in the app shows in the dashboard’s attendance');

await tsl.doc('requisitions/rq1').set({ ref: 'REQ-5001', type: 'out', inventoryId: 'inv_t1', itemName: 'Air filter', locationId: 'loc_t2', workOrderId: 'WO-777001', workOrderRef: 'WO-777001', quantity: 2, reason: 'Worn', requestedById: 'staff_t6', requestedByName: 'Tech Six', requestedAt: now, status: 'pending', createdAt: now });
await until('request in the dashboard', async () => (await admin.doc('requisition/req_app_rq1').get()).data()?.status === 'Pending');
await admin.doc('requisition/req_app_rq1').update({ status: 'Approved', actionBy: 'staff_t4', actionDate: now });
await until('approval in the app', async () => (await appDoc('requisitions/rq1')).status === 'approved');
assert.equal((await appDoc('requisitions/rq1')).actionedByName, 'Sup Four');
await until('requester told', async () => (await tsl.collection('users/staff_t6/notifications').where('kind', '==', 'requisition').get()).size > 0);
ok('a parts request goes to the dashboard, and its approval comes back with a notification');

// Cancelling in the dashboard.
await admin.doc('work_order/WO-777001').update({ status: 'Cancelled' });
await until('cancelled in the app', async () => (await appDoc('workOrders/WO-777001')).status === 'cancelled');
ok('cancelling in the dashboard cancels the job in the app');

console.log(`\nAll ${passed} bridge checks passed.`);
process.exit(0);
