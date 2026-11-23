import assert from 'node:assert/strict';
import { test } from 'node:test';
import { Timestamp } from 'firebase-admin/firestore';
import {
  fromAdminMessage,
  fromAdminRequisitionDecision,
  fromAdminWorkOrder,
  fromLagos,
  lagosParts,
  toAdminAttendance,
  toAdminRequisition,
  toAdminStatus,
  toAdminWorkOrder,
} from '../bridge/outbound';
import { fingerprint, isAppEcho } from '../bridge/shared';

// 23 Nov 2026, 14:05:09 in Lagos.
const at = Timestamp.fromDate(new Date('2026-11-23T13:05:09Z'));

test('Lagos dates and times both ways', () => {
  assert.deepEqual(lagosParts(at), { date: '2026-11-23', time: '14:05:09', hhmm: '14:05' });
  assert.equal(fromLagos('2026-11-23', '14:05')!.toMillis(), Date.parse('2026-11-23T13:05:00Z'));
  assert.equal(fromLagos('2026-11-23', '9:00:00')!.toMillis(), Date.parse('2026-11-23T08:00:00Z'));
  assert.equal(fromLagos('tomorrow', '09:00'), null);
});

const order = {
  ref: 'WO-1004', type: 'client', title: 'Leak', description: 'Under the sink', priority: 'medium',
  status: 'pending_review', locationId: 'loc_1', assetId: null, assignedToId: 'staff_1',
  supervisorId: 'staff_2', dueAt: at, reportPhotos: [], createdAt: at,
};

test('an app work order in the dashboard’s format', () => {
  const c = toAdminWorkOrder(order, ['https://x/1.jpg']);
  assert.equal(c.id, 'WO-1004');
  assert.deepEqual(c.fields, {
    title: 'Leak', description: 'Under the sink', type: 'Client', priority: 'Medium',
    status: 'Pending Review', locationId: 'loc_1', assetId: '', assignedTo: 'staff_1',
    supervisedBy: 'staff_2', dueDate: '2026-11-23', dueTime: '14:05',
  });
  assert.deepEqual(c.onCreate.attachments, ['https://x/1.jpg']);
  assert.equal(c.onCreate.source, 'app');
});

test('the dashboard’s work order read back for the app', () => {
  const w = fromAdminWorkOrder({ ...toAdminWorkOrder(order, []).fields, status: 'Cancelled', priority: 'High' });
  assert.equal(w.priority, 'high');
  assert.equal(w.status, 'cancelled');
  assert.equal(fromAdminWorkOrder({ status: 'In Progress' }).status, 'in_progress');
  assert.equal(fromAdminWorkOrder({ status: 'Pending Review' }).status, 'pending_review');
  assert.equal(fromAdminWorkOrder({ status: 'Rejected' }).status, 'returned');
  assert.equal(fromAdminWorkOrder({ status: 'Something else' }).status, null);
  assert.equal(w.assetId, null);
  assert.equal(w.dueAt!.toMillis(), Date.parse('2026-11-23T13:05:00Z'));
  assert.equal(fromAdminWorkOrder({ type: 'SLA' }).type, 'sla');
});

test('the app’s own writes are recognised, dashboard edits are not', () => {
  const fields = toAdminWorkOrder(order, []).fields;
  const written = { ...fields, appSync: fingerprint(fields), attachments: ['x'] };
  assert.equal(isAppEcho(written), true);
  assert.equal(isAppEcho({ ...written, assignedTo: 'staff_9' }), false, 'dashboard reassigned');
  assert.equal(isAppEcho({ ...fields }), false, 'never written by the app');
});

test('timeline, attendance, requests and chat', () => {
  const s = toAdminStatus('e1', { kind: 'submitted', actorId: 'staff_1', actorName: 'Tech', actorRole: 'staff', note: 'Done', createdAt: at }, 'WO-1004', ['a', 'b']);
  assert.equal(s.id, 'STAT_app_e1');
  assert.equal(s.fields.statusDescription, 'Pending Review');
  assert.equal(s.fields.photo2, 'b');
  assert.equal(s.fields.photo3, '');
  assert.equal(s.fields.createdBy, 'Staff');

  const a = toAdminAttendance('x1', { userId: 'staff_1', locationId: 'loc_1', status: 'clocked_in', attendanceStatus: 'present', clockInAt: at, clockOutAt: null, clockInDistanceM: 16 });
  assert.equal(a.id, 'att_app_x1');
  assert.equal(a.fields.clockInTime, '14:05:09');
  assert.equal(a.fields.clockOutDate, null);
  assert.equal(a.fields.status, 'Clocked In');

  const r = toAdminRequisition('r1', { ref: 'REQ-1001', inventoryId: 'inv_1', quantity: 2, reason: 'Tube', requestedById: 'staff_1', type: 'out', status: 'pending', workOrderRef: 'WO-1004' });
  assert.equal(r.id, 'req_app_r1');
  assert.equal(r.fields.status, 'Pending');
  assert.equal(r.fields.requisitionType, 'Out');
  assert.deepEqual(fromAdminRequisitionDecision({ status: 'Approved', actionBy: 'admin_001', actionDate: at }, 'Admin')!.status, 'approved');
  assert.equal(fromAdminRequisitionDecision({ status: 'Pending' }, null), null);

  const m = fromAdminMessage('msg_9', { message: ' On my way ', senderId: 'staff_2', senderType: 'supervisor', sendDateTime: at }, 'Sup')!;
  assert.equal(m.id, 'admin_msg_9');
  assert.equal(m.fields.text, 'On my way');
  assert.equal(m.fields.senderRole, 'supervisor');
  assert.equal(fromAdminMessage('m', { message: '  ' }, null), null);
});
