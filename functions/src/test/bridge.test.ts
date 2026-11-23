import assert from 'node:assert/strict';
import { test } from 'node:test';
import { GeoPoint, Timestamp } from 'firebase-admin/firestore';
import {
  AdminDoc,
  changedFields,
  convertAsset,
  convertClientUser,
  convertCompany,
  convertDocument,
  convertInventory,
  convertLocation,
  convertSla,
  convertStaff,
  convertZone,
  hhmm,
  lagosDate,
  Lookup,
  phone,
} from '../bridge/convert';

// Shaped like the dashboard's real records (22 Nov 2026).
const created = Timestamp.fromDate(new Date('2026-11-16T20:27:35Z'));
const locations: Record<string, AdminDoc> = {
  loc_001: { name: 'Central Operations Hub', latitude: 9.0765, longitute: 7.3986, radius: 100, type: 'office', siteManager: 'staff_001', status: 'Active', zonesTotal: '1', assetTotal: '1', address: '123 Central Business District, Abuja', createdAt: created },
};
const staff: Record<string, AdminDoc> = {
  staff_001: { name: 'Jane Doe', email: 'Supervisor@Example.com', role: 'Supervisor', status: 'Active', phone: '08031234501', designation: 'Facility Supervisor', assignedFacility: 'loc_001', createdAt: created },
};
const zones: Record<string, AdminDoc> = { zone_001: { name: 'Plant room', locationId: 'loc_001' } };
const look: Lookup = {
  location: (id) => (id ? locations[id] : undefined),
  staff: (id) => (id ? staff[id] : undefined),
  zone: (id) => (id ? zones[id] : undefined),
  client: () => undefined,
};

test('staff become app users with their facility', () => {
  const c = convertStaff('staff_001', staff.staff_001, look)!;
  assert.equal(c.collection, 'users');
  assert.equal(c.id, 'staff_001');
  assert.deepEqual(c.fields, {
    role: 'supervisor', status: 'active', name: 'Jane Doe', email: 'supervisor@example.com',
    phone: '+2348031234501', designation: 'Facility Supervisor', locationId: 'loc_001',
    locationName: 'Central Operations Hub', companyId: null, companyName: null,
  });
  assert.equal(c.onCreate.onShift, false);
});

test('staff with an unknown facility or role', () => {
  const early = convertStaff('s', { ...staff.staff_001, assignedFacility: 'loc_later' }, look)!;
  assert.equal(early.fields.locationId, 'loc_later', 'kept; the name follows when the facility is copied');
  assert.equal(early.fields.locationName, null);
  assert.equal(convertStaff('s', { ...staff.staff_001, role: 'Driver' }, look), null);
  assert.equal(convertStaff('s', { ...staff.staff_001, status: 'Exited' }, look)!.fields.status, 'exited');
});

test('a facility keeps its position despite the "longitute" spelling', () => {
  const c = convertLocation('loc_001', locations.loc_001, look);
  assert.ok((c.fields.geo as GeoPoint).isEqual(new GeoPoint(9.0765, 7.3986)));
  assert.equal(c.fields.radiusM, 100);
  assert.equal(c.fields.siteManagerName, 'Jane Doe');
  assert.equal(c.fields.zoneCount, 1);
  assert.equal(convertLocation('x', { name: 'No GPS', type: 'Warehouse' }, look).fields.geo, null);
  assert.equal(convertLocation('x', { name: 'No GPS', type: 'Warehouse' }, look).fields.type, 'warehouse');
});

test('zones, assets, stock and documents', () => {
  assert.equal(convertZone('z', { name: 'A', locationId: 'loc_001' })!.fields.status, 'active');
  const asset = convertAsset('asset_001', { equipmentName: '500kVA Generator', zoneId: 'zone_001', status: 'Active', nextService: '2026-12-15', assetId: 'asset_001' }, look)!;
  assert.equal(asset.fields.locationId, 'loc_001');
  assert.equal(asset.fields.zoneName, 'Plant room');
  assert.ok((asset.fields.nextServiceAt as Timestamp).isEqual(Timestamp.fromDate(new Date('2026-12-14T23:00:00Z'))));
  assert.equal(convertAsset('a', { zoneId: 'zone_gone' }, look), null);

  const stock = convertInventory('inv_001', { itemName: 'Air filter', quantity: '25', alertThreshold: '5', locationId: 'loc_001', status: 'Active', inventoryId: 'inv_001' })!;
  assert.equal(stock.fields.quantity, 25);
  assert.equal(stock.fields.stockStatus, 'ok');
  assert.equal(convertInventory('i', { quantity: '3', alertThreshold: '5', locationId: 'l' })!.fields.stockStatus, 'low');

  const doc = convertDocument('DOC_2008', { title: 'Safety', category: 'Warrantys', locationId: 'loc_001', documentFile: 'https://thickservices.com/TSLfacilitymanager/tsl/uploads/a7b0.jpg' })!;
  assert.equal(doc.fields.category, 'other');
  assert.equal(doc.fields.fileName, 'a7b0.jpg');
  assert.equal(doc.fields.contentType, 'image/jpeg');
  assert.equal(doc.fields.filePath, null);
});

test('client companies and their contact', () => {
  const d = { clientName: 'Acme Corp Nigeria Ltd.', clientEmail: 'Facilities@AcmeCorp.ng', clientPhone: '+2348000000099', clientID: 'client_001' };
  const company = convertCompany('client_001', d);
  assert.equal(company.fields.status, 'active');
  assert.equal('locationIds' in company.fields, false, 'keeps the app’s list until the dashboard has one');
  assert.deepEqual(company.onCreate.locationIds, []);
  assert.deepEqual(convertCompany('c', { ...d, locationIds: ['loc_001'] }).fields.locationIds, ['loc_001']);
  const user = convertClientUser('client_001', d)!;
  assert.equal(user.fields.role, 'client');
  assert.equal(user.fields.email, 'facilities@acmecorp.ng');
  assert.equal(user.fields.companyId, 'client_001');
});

test('SLA schedules', () => {
  const d = { task: 'Weed the grasses', locationId: 'loc_001', frequency: 'Weekday', dueTime: '23:00:00', startDate: '2026-11-20', priority: 'High', assignedTo: 'staff_6afb', supervisedBy: 'staff_001', status: 'Active' };
  const c = convertSla('sla_1', d, false)!;
  assert.equal(c.fields.frequency, 'weekdays');
  assert.equal(c.fields.dueTime, '23:00');
  assert.equal(c.fields.priority, 'high');
  assert.equal(c.fields.createsJobs, false);
  assert.equal(convertSla('s', { ...d, frequency: 'Every so often' }, false), null);
});

test('small conversions', () => {
  assert.equal(phone('08031234501'), '+2348031234501');
  assert.equal(phone('2348031234501'), '+2348031234501');
  assert.equal(phone('+2348031234501'), '+2348031234501');
  assert.equal(hhmm('9:05'), '09:05');
  assert.equal(hhmm('25:00'), null);
  assert.equal(lagosDate('not a date'), null);
});

test('only changed fields are written', () => {
  const ts = Timestamp.fromMillis(1000);
  const current = { name: 'A', geo: new GeoPoint(1, 2), at: ts, ids: ['x'] };
  assert.deepEqual(changedFields({ name: 'A', geo: new GeoPoint(1, 2), at: Timestamp.fromMillis(1000), ids: ['x'] }, current), {});
  assert.deepEqual(changedFields({ name: 'B', ids: ['x', 'y'] }, current), { name: 'B', ids: ['x', 'y'] });
});
