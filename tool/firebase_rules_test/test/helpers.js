import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, setDoc, GeoPoint, Timestamp } from 'firebase/firestore';

const root = fileURLToPath(new URL('../../../', import.meta.url));

export async function createEnv() {
  return initializeTestEnvironment({
    projectId: 'demo-tsl',
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules: readFileSync(`${root}firestore.rules`, 'utf8'),
    },
    storage: {
      host: '127.0.0.1',
      port: 9199,
      rules: readFileSync(`${root}storage.rules`, 'utf8'),
    },
  });
}

const past = Timestamp.fromDate(new Date('2026-11-01T09:00:00Z'));
const audit = { createdAt: past, createdBy: 'system', updatedAt: past, updatedBy: 'system' };

export const people = {
  admin: { role: 'admin', name: 'Ada Admin', locationId: null },
  sarah: { role: 'supervisor', name: 'Sarah James', locationId: 'marina' },
  musa: { role: 'supervisor', name: 'Musa Bello', locationId: 'cedar' },
  emeka: { role: 'staff', name: 'Emeka Okafor', locationId: 'marina' },
  tunde: { role: 'staff', name: 'Tunde Bakare', locationId: 'marina' },
  grace: { role: 'staff', name: 'Grace Eze', locationId: 'cedar' },
  gone: { role: 'staff', name: 'Former Staff', locationId: 'marina', status: 'exited' },
  daniel: { role: 'client', name: 'Daniel Clarke', locationId: 'marina', companyId: 'acme' },
  ngozi: { role: 'client', name: 'Ngozi Obi', locationId: 'marina', companyId: 'acme' },
  locked: { role: 'client', name: 'Locked Client', locationId: 'marina', companyId: 'shut' },
};

export function order(overrides = {}) {
  return {
    ref: 'WO-1001',
    type: 'client',
    title: 'Air conditioning not cooling',
    description: 'East wing unit blowing warm air.',
    priority: 'high',
    status: 'open',
    locationId: 'marina',
    locationName: 'Marina Towers',
    zoneId: 'tower-a',
    zoneName: 'Tower A · Floor 3',
    companyId: 'acme',
    clientId: 'daniel',
    clientName: 'Daniel Clarke',
    assignedToId: 'emeka',
    assignedToName: 'Emeka Okafor',
    supervisorId: 'sarah',
    supervisorName: 'Sarah James',
    dueAt: past,
    reportPhotos: [],
    workPhotos: [],
    returnPhotos: [],
    inspectionChecks: [],
    ...audit,
    ...overrides,
  };
}

export async function seed(env) {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    const put = (path, data) => setDoc(doc(db, path), data);

    for (const [uid, person] of Object.entries(people)) {
      await put(`users/${uid}`, {
        email: `${uid}@example.com`,
        phone: null,
        designation: null,
        locationName: null,
        companyId: null,
        onShift: false,
        status: 'active',
        ...person,
        ...audit,
      });
    }

    await put('companies/acme', {
      name: 'Acme Corp', status: 'active', monthlyWorkOrderLimit: 20,
      locationIds: ['marina', 'harbour'], ...audit,
    });
    await put('companies/shut', {
      name: 'Shut Ltd', status: 'locked', monthlyWorkOrderLimit: null,
      locationIds: ['marina'], ...audit,
    });

    for (const [id, name] of [['marina', 'Marina Towers'], ['harbour', 'Harbour Point'], ['cedar', 'Cedar Court']]) {
      await put(`locations/${id}`, {
        name, type: 'office', address: '1 Test Road', geo: new GeoPoint(6.45, 3.4),
        radiusM: 100, timeZone: 'Africa/Lagos', status: 'active', zoneCount: 0, assetCount: 0, ...audit,
      });
    }
    await put('zones/tower-a', { locationId: 'marina', name: 'Tower A', status: 'active', ...audit });
    await put('zones/cedar-hall', { locationId: 'cedar', name: 'Main hall', status: 'active', ...audit });

    await put('workOrders/open', order());
    await put('workOrders/working', order({ ref: 'WO-1002', status: 'in_progress' }));
    await put('workOrders/review', order({ ref: 'WO-1003', status: 'pending_review' }));
    await put('workOrders/done', order({ ref: 'WO-1004', status: 'completed' }));
    await put('workOrders/other-client', order({ ref: 'WO-1005', clientId: 'ngozi', clientName: 'Ngozi Obi' }));
    await put('workOrders/cedar', order({
      ref: 'WO-1006', locationId: 'cedar', clientId: null, companyId: null, type: 'sla',
      assignedToId: 'grace', assignedToName: 'Grace Eze', supervisorId: 'musa', supervisorName: 'Musa Bello',
    }));

    await put('inventory/filters', {
      ref: 'SKU-000001', locationId: 'marina', itemName: 'HVAC air filter', quantity: 24,
      alertThreshold: 5, stockStatus: 'ok', photoPath: null, status: 'active', ...audit,
    });
    await put('inventory/cedar-oil', {
      ref: 'SKU-000002', locationId: 'cedar', itemName: 'Generator oil', quantity: 6,
      alertThreshold: 2, stockStatus: 'ok', photoPath: null, status: 'active', ...audit,
    });

    await put('users/emeka/notifications/n1', {
      kind: 'assigned', title: 'New assignment', body: 'WO-1001', workOrderId: 'open',
      requisitionId: null, createdAt: past, readAt: null,
    });
    await put('attendance/a1', {
      userId: 'emeka', userName: 'Emeka Okafor', locationId: 'marina', locationName: 'Marina Towers',
      status: 'clocked_out', attendanceStatus: 'present', clockInAt: past, source: 'app', ...audit,
    });
    await put('counters/workOrders', { next: 1007 });
  });
}

export const as = (env, uid) => env.authenticatedContext(uid).firestore();
export const storageAs = (env, uid) => env.authenticatedContext(uid).storage();
