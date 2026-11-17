/**
 * Fills the Firebase emulators with test data that matches the app's old
 * sample data, so the screens look the same once they read from Firestore.
 *
 * Emulators only. Run it through tool/emulators.sh, which sets the
 * *_EMULATOR_HOST variables this script insists on.
 */
if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  console.error('Refusing to seed: the Firestore and Auth emulators are not configured.');
  process.exit(1);
}

import { GeoPoint, Timestamp } from 'firebase-admin/firestore';
import { auth, db, lagosMonth } from './common';

const now = Date.now();
const hours = (h: number) => Timestamp.fromMillis(now + h * 3600 * 1000);
const audit = { createdAt: hours(-24 * 30), createdBy: 'system', updatedAt: hours(-24 * 30), updatedBy: 'system' };
const PASSWORD = 'test1234';

const people = {
  admin: { role: 'admin', name: 'Ada Admin', email: 'admin@thickservices.com', locationId: null },
  sarah: { role: 'supervisor', name: 'Sarah James', email: 'sarah@thickservices.com', locationId: 'marina', designation: 'Facility supervisor', phone: '+234 809 555 0119' },
  emeka: { role: 'staff', name: 'Emeka Okafor', email: 'emeka@thickservices.com', locationId: 'marina', designation: 'HVAC technician', phone: '+234 806 555 0187' },
  tunde: { role: 'staff', name: 'Tunde Bakare', email: 'tunde@thickservices.com', locationId: 'marina', designation: 'Electrician' },
  david: { role: 'staff', name: 'David Adeyemi', email: 'david@thickservices.com', locationId: 'marina', designation: 'General maintenance' },
  grace: { role: 'staff', name: 'Grace Eze', email: 'grace@thickservices.com', locationId: 'marina', designation: 'Safety officer' },
  // Client sign-in codes go to real inboxes through the company mail API.
  daniel: { role: 'client', name: 'Daniel Clarke', email: 'wilson+client1@dbestdev.com', locationId: 'marina', companyId: 'acme', phone: '+234 803 555 0142' },
  ngozi: { role: 'client', name: 'Ngozi Obi', email: 'wilson+client2@dbestdev.com', locationId: 'marina', companyId: 'acme' },
  // Clocks in at the developer's own location (see TEST_LOCATION below).
  tester: { role: 'staff', name: 'Field Tester', email: 'tester@thickservices.com', locationId: 'test-site', designation: 'Test technician' },
} as const;

/**
 * "lat,lng" of a real place to put a Test Facility, so GPS clock-in can be
 * tried for real. tool/emulators.sh passes it from the untracked
 * .emulator-test-location file; without it the facility sits in Lagos.
 */
const testGeo = (() => {
  const [lat, lng] = (process.env.TEST_LOCATION ?? '').split(',').map(Number);
  return Number.isFinite(lat) && Number.isFinite(lng) ? new GeoPoint(lat, lng) : new GeoPoint(6.5244, 3.3792);
})();

const locations = {
  marina: { name: 'Marina Towers, Lagos', address: '12 Marina Road, Lagos Island', geo: new GeoPoint(6.4515, 3.3886) },
  cedar: { name: 'Cedar Court, Abuja', address: '4 Aguiyi Ironsi Street, Maitama', geo: new GeoPoint(9.0812, 7.4951) },
  harbour: { name: 'Harbour Point, Lekki', address: '1 Admiralty Way, Lekki Phase 1', geo: new GeoPoint(6.4474, 3.4723) },
  'test-site': { name: 'Test Facility', address: 'Your current location', geo: testGeo },
};

const zones: Record<string, [string, string][]> = {
  marina: [
    ['marina-a2', 'Tower A · Floor 2'], ['marina-a3', 'Tower A · Floor 3'], ['marina-a4', 'Tower A · Floor 4'],
    ['marina-reception', 'Reception'], ['marina-carpark', 'Car park'], ['marina-plant', 'Plant room'],
    ['marina-pump', 'Pump room'], ['marina-all', 'All floors'],
  ],
  cedar: [['cedar-hall', 'Main hall'], ['cedar-basement', 'Basement plant room'], ['cedar-carpark', 'Car park']],
  harbour: [['harbour-lobby', 'Lobby'], ['harbour-f2', 'Floor 2 offices'], ['harbour-roof', 'Rooftop']],
  'test-site': [['test-main', 'Main building']],
};
const zoneName = (id: string) => Object.values(zones).flat().find(([z]) => z === id)![1];

type Event = [kind: string, status: string, actor: keyof typeof people | 'system', at: number, note?: string];

interface SeedOrder {
  id: string; ref: string; title: string; description: string; type: 'client' | 'sla';
  status: string; zoneId: string; due: number; assignee: keyof typeof people;
  priority?: string; client?: boolean; workNote?: string; submittedAt?: number; events: Event[];
}

const orders: SeedOrder[] = [
  { id: 'seed1048', ref: 'WO-1048', title: 'AHU-02 cooling fault', type: 'client', status: 'in_progress', zoneId: 'marina-a3', due: 3, assignee: 'emeka', priority: 'high', client: true,
    description: 'No cold air reaching the east office wing. Check condenser, filter and refrigerant pressure.',
    events: [['reported', 'open', 'daniel', -4], ['assigned', 'open', 'sarah', -4, 'Assigned to Emeka Okafor'], ['started', 'in_progress', 'emeka', -3, 'Checking refrigerant pressure']] },
  { id: 'seed1047', ref: 'WO-1047', title: 'Monthly generator service', type: 'sla', status: 'open', zoneId: 'marina-plant', due: 5, assignee: 'emeka',
    description: 'Scheduled monthly service for the plant room generator.', events: [['reported', 'open', 'system', -24, 'Scheduled by SLA plan']] },
  { id: 'seed1045', ref: 'WO-1045', title: 'Fire extinguisher inspection', type: 'sla', status: 'open', zoneId: 'marina-all', due: -2, assignee: 'emeka',
    description: 'Inspect and tag all fire extinguishers on every floor.', events: [['reported', 'open', 'system', -48, 'Scheduled by SLA plan']] },
  { id: 'seed1043', ref: 'WO-1043', title: 'Pump room leak check', type: 'sla', status: 'pending_review', zoneId: 'marina-pump', due: 2, assignee: 'emeka',
    description: 'Check the pump room seals for any sign of leakage.', workNote: 'Replaced the worn seal on pump 2. No further leaks.', submittedAt: -1,
    events: [['reported', 'open', 'system', -30, 'Scheduled by SLA plan'], ['submitted', 'pending_review', 'emeka', -1]] },
  { id: 'seed1040', ref: 'WO-1040', title: 'Office door lock repair', type: 'client', status: 'completed', zoneId: 'marina-a2', due: -72, assignee: 'david', client: true,
    description: 'The lock on the east office door is sticking.', workNote: 'Lubricated and realigned the strike plate.', submittedAt: -74,
    events: [['reported', 'open', 'daniel', -96], ['assigned', 'open', 'sarah', -95, 'Assigned to David Adeyemi'], ['confirmed', 'completed', 'sarah', -73]] },
  { id: 'seed1039', ref: 'WO-1039', title: 'Washroom tap leakage', type: 'client', status: 'open', zoneId: 'marina-a3', due: 24, assignee: 'tunde', client: true,
    description: 'The tap in the Floor 3 washroom keeps dripping.',
    events: [['reported', 'open', 'daniel', -2], ['assigned', 'open', 'sarah', -1, 'Assigned to Tunde Bakare']] },
  { id: 'seed1037', ref: 'WO-1037', title: 'Corridor lighting', type: 'client', status: 'pending_review', zoneId: 'marina-a4', due: 4, assignee: 'tunde', client: true,
    description: 'Lights are flickering along the Floor 4 corridor.', workNote: 'Replaced two LED drivers.', submittedAt: -0.2,
    events: [['reported', 'open', 'daniel', -20], ['assigned', 'open', 'sarah', -19, 'Assigned to Tunde Bakare'], ['submitted', 'pending_review', 'tunde', -0.2]] },
];

async function main() {
  const batch = db.batch();

  for (const [uid, p] of Object.entries(people)) {
    await auth.createUser({
      uid,
      email: p.email,
      displayName: p.name,
      ...(p.role === 'client' ? {} : { password: PASSWORD }),
    }).catch((e) => { if (e.code !== 'auth/uid-already-exists') throw e; });
    batch.set(db.doc(`users/${uid}`), {
      status: 'active', phone: null, designation: null, companyId: null, companyName: null,
      ...p,
      locationName: p.locationId ? locations[p.locationId as keyof typeof locations].name : null,
      ...(p.role === 'client' ? { companyName: 'Acme Corp Nigeria' } : {}),
      onShift: false, lastLoginAt: null, ...audit,
    });
  }

  batch.set(db.doc('companies/acme'), {
    name: 'Acme Corp Nigeria', status: 'active', monthlyWorkOrderLimit: 20,
    locationIds: ['marina', 'cedar', 'harbour', 'test-site'], contactEmail: 'facilities@acmecorp.ng', contactPhone: null, ...audit,
  });

  for (const [id, l] of Object.entries(locations)) {
    batch.set(db.doc(`locations/${id}`), {
      ...l, type: 'office', radiusM: 100, timeZone: 'Africa/Lagos',
      siteManagerId: id === 'marina' ? 'sarah' : null, siteManagerName: id === 'marina' ? 'Sarah James' : null,
      zoneCount: zones[id].length, assetCount: id === 'marina' ? 2 : 0, status: 'active', ...audit,
    });
    for (const [zoneId, name] of zones[id]) {
      batch.set(db.doc(`zones/${zoneId}`), { locationId: id, name, description: null, status: 'active', ...audit });
    }
  }

  batch.set(db.doc('assets/generator'), { ref: 'AST-000001', locationId: 'marina', zoneId: 'marina-plant', zoneName: 'Plant room', equipmentName: '500kVA backup generator', nextServiceAt: hours(5), status: 'active', ...audit });
  batch.set(db.doc('assets/ahu02'), { ref: 'AST-000002', locationId: 'marina', zoneId: 'marina-a3', zoneName: 'Tower A · Floor 3', equipmentName: 'AHU-02 air handling unit', nextServiceAt: hours(24 * 20), status: 'maintenance', ...audit });

  const stock: [string, string, number, number][] = [['filters', 'HVAC air filter', 24, 5], ['led', 'LED panel', 8, 3], ['oil', 'Generator oil', 6, 2]];
  stock.forEach(([id, itemName, quantity, alertThreshold], i) =>
    batch.set(db.doc(`inventory/${id}`), {
      ref: `SKU-00000${i + 1}`, locationId: 'marina', itemName, quantity, alertThreshold,
      stockStatus: quantity === 0 ? 'out' : quantity <= alertThreshold ? 'low' : 'ok', photoPath: null, status: 'active', ...audit,
    }));

  batch.set(db.doc('requisitions/req081'), {
    ref: 'REQ-1001', type: 'out', inventoryId: 'led', itemName: 'LED panel', locationId: 'marina', workOrderId: 'seed1037', workOrderRef: 'WO-1037',
    quantity: 2, reason: 'Corridor lighting on floor 4', requestedById: 'tunde', requestedByName: 'Tunde Bakare', requestedAt: hours(-24),
    status: 'approved', actionedById: 'admin', actionedByName: 'Ada Admin', actionedAt: hours(-20), rejectionReason: null, ...audit,
  });

  for (const o of orders) {
    const assignee = people[o.assignee];
    batch.set(db.doc(`workOrders/${o.id}`), {
      ref: o.ref, type: o.type, title: o.title, description: o.description, priority: o.priority ?? 'medium', status: o.status,
      locationId: 'marina', locationName: locations.marina.name, zoneId: o.zoneId, zoneName: zoneName(o.zoneId),
      assetId: null, assetName: null,
      companyId: o.client ? 'acme' : null, companyName: o.client ? 'Acme Corp Nigeria' : null,
      clientId: o.client ? 'daniel' : null, clientName: o.client ? 'Daniel Clarke' : null, slaId: null,
      assignedToId: o.assignee, assignedToName: assignee.name, supervisorId: 'sarah', supervisorName: 'Sarah James', assignmentNote: null,
      dueAt: hours(o.due), reportPhotos: [], startedAt: o.status === 'in_progress' ? hours(-3) : null,
      workNote: o.workNote ?? null, workPhotos: o.workNote ? [`workOrders/${o.id}/work/after.jpg`] : [],
      submittedAt: o.submittedAt != null ? hours(o.submittedAt) : null,
      returnReason: null, returnFeedback: null, returnPhotos: [], returnedAt: null,
      inspectionChecks: o.status === 'completed' ? ['Unit operating correctly', 'Area clean and safe', 'Evidence meets requirements'] : [],
      inspectionNote: null, inspectionPhotos: [], completedAt: o.status === 'completed' ? hours(-73) : null,
      lastMessageAt: null, lastMessagePreview: null, ...audit, createdAt: hours(o.events[0][3]),
    });
    o.events.forEach(([kind, status, actor, at, note], i) => {
      const who = actor === 'system' ? undefined : people[actor];
      batch.set(db.doc(`workOrders/${o.id}/events/e${i}`), {
        kind, statusAfter: status, actorId: actor, actorName: who?.name ?? 'System', actorRole: who?.role ?? 'system',
        note: note ?? null, photos: [], createdAt: hours(at),
      });
    });
  }

  const message = (id: string, text: string, sender: keyof typeof people, at: number) => ({
    id, text, senderId: sender, senderName: people[sender].name, senderRole: people[sender].role, sentAt: hours(at),
  });
  const chats: Record<string, ReturnType<typeof message>[]> = {
    seed1048: [
      message('m1', 'Hello Daniel, Emeka is on his way to inspect the unit.', 'sarah', -3.6),
      message('m2', 'Thank you. The east wing is accessible.', 'daniel', -3.5),
      message('m3', 'We have identified low refrigerant pressure. We’ll update you shortly.', 'emeka', -2.8),
    ],
    seed1039: [message('m1', 'Tunde will look at the washroom tap tomorrow morning.', 'sarah', -1)],
  };
  for (const [orderId, messages] of Object.entries(chats)) {
    for (const { id, ...m } of messages) batch.set(db.doc(`workOrders/${orderId}/messages/${id}`), m);
    const last = messages[messages.length - 1];
    batch.update(db.doc(`workOrders/${orderId}`), { lastMessageAt: last.sentAt, lastMessagePreview: last.text });
  }

  batch.set(db.doc('counters/workOrders'), { next: 1049 });
  batch.set(db.doc('counters/requisitions'), { next: 1002 });
  batch.set(db.doc('counters/assets'), { next: 3 });
  batch.set(db.doc('counters/inventory'), { next: 4 });
  batch.set(db.doc(`companies/acme/usage/${lagosMonth()}`), { workOrderCount: 4 });

  await batch.commit();
  console.log(`Seeded ${Object.keys(people).length} users, ${orders.length} work orders. Staff password: ${PASSWORD}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
