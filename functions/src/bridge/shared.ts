/**
 * Step 2 of docs/admin-db-integration-plan.md: records both sides use.
 *
 * App → dashboard: work orders, their timeline (as `workorder_status`), chat,
 * attendance and parts requests.
 * Dashboard → app: work orders created there, the dashboard's edits to any
 * work order (wording, priority, due time, people, cancelling), chat, and
 * decisions on parts requests.
 *
 * Every copy the app writes carries `appSync`, a fingerprint of what it
 * wrote. A dashboard change whose fields still match it is the app's own
 * write coming back and is ignored; otherwise only the fields the dashboard
 * changed are applied, so a late echo never undoes a newer change in the app.
 */
import { createHash } from 'node:crypto';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';
import { getDownloadURL, getStorage } from 'firebase-admin/storage';
import { logger } from 'firebase-functions';
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { db, DATABASE_ID, REGION } from '../common';
import { notify } from '../notify';
import { createOrder } from '../sla';
import { AdminDoc, Converted, sameValue } from './convert';
import {
  fromAdminMessage,
  fromAdminRequisitionDecision,
  fromAdminWorkOrder,
  sameMinute,
  STATUS_TIMESTAMP,
  toAdminAttendance,
  toAdminMessage,
  toAdminRequisition,
  toAdminStatus,
  toAdminWorkOrder,
} from './outbound';
import { adminDb, logSteps, Step, SyncOptions, write } from './sync';

const enabled = () => process.env.BRIDGE_ENABLED === 'true';
const APPLY: SyncOptions = { apply: true };

/** A stable fingerprint of the fields a copy holds. */
export function fingerprint(fields: Record<string, unknown>): string {
  const plain = (v: unknown): unknown =>
    v instanceof Timestamp ? v.toMillis()
      : Array.isArray(v) ? v.map(plain)
        : v && typeof v === 'object' ? Object.fromEntries(Object.keys(v).sort().map((k) => [k, plain((v as AdminDoc)[k])]))
          : v ?? null;
  return createHash('sha256').update(JSON.stringify(plain(fields))).digest('hex').slice(0, 16);
}

/** Writes an app record to the dashboard, with its fingerprint. */
function pushToAdmin(c: Converted, opts: SyncOptions) {
  return write(adminDb, c, opts, 'app-sync', () => ({ appSync: fingerprint(c.fields) }));
}

/** The fields the app keeps in step on a dashboard work order. */
const WORK_ORDER_FIELDS = Object.keys(toAdminWorkOrder({ ref: 'x' }, []).fields);

/**
 * Whether a dashboard record still holds exactly what the app wrote with its
 * fingerprint, i.e. this change is the app's own write, not the dashboard's.
 */
export function isAppEcho(after: AdminDoc, keys: string[] = WORK_ORDER_FIELDS) {
  if (typeof after.appSync !== 'string') return false;
  return after.appSync === fingerprint(Object.fromEntries(keys.map((k) => [k, after[k]])));
}

/** Storage paths as links the dashboard can open; web links stay as they are. */
async function photoLinks(paths: unknown): Promise<string[]> {
  const out: string[] = [];
  for (const p of Array.isArray(paths) ? paths : []) {
    if (typeof p !== 'string' || !p) continue;
    if (/^https?:\/\//.test(p)) { out.push(p); continue; }
    try {
      out.push(await getDownloadURL(getStorage().bucket().file(p)));
    } catch (e) {
      logger.warn(`no link for photo ${p}: ${(e as Error).message}`);
    }
  }
  return out;
}

async function appWorkOrderByRef(ref: string) {
  const snap = await db.collection('workOrders').where('ref', '==', ref).limit(1).get();
  return snap.docs[0];
}

async function userName(uid: string | null) {
  if (!uid) return null;
  return ((await db.doc(`users/${uid}`).get()).data()?.name as string | undefined) ?? null;
}

/** A dashboard person's name: staff, the dashboard admin, or an app user. */
async function adminPersonName(id: unknown): Promise<string | null> {
  if (typeof id !== 'string' || !id) return null;
  const staff = (await adminDb.doc(`staff/${id}`).get()).data();
  if (staff?.name) return String(staff.name);
  const admin = (await adminDb.doc(`admin/${id}`).get()).data();
  if (admin?.fullName) return String(admin.fullName);
  return userName(id);
}

// =========================================================== app → admin

export async function pushWorkOrder(o: AdminDoc, opts: SyncOptions): Promise<Step[]> {
  if (typeof o.ref !== 'string') return [];
  const c = toAdminWorkOrder(o, []);
  if (!(await adminDb.doc(`work_order/${c.id}`).get()).exists) {
    c.onCreate.attachments = await photoLinks(o.reportPhotos);
  }
  return [await pushToAdmin(c, opts)];
}

export const pushWorkOrderToAdmin = onDocumentWritten(
  { document: 'workOrders/{id}', database: DATABASE_ID, region: REGION },
  async (event) => {
    if (!enabled() || !event.data?.after.exists) return;
    // The job as it is now, not as it was when this trigger fired: triggers
    // can run out of order, and an older copy must never reach the dashboard
    // last.
    const current = (await db.doc(`workOrders/${event.params.id}`).get()).data();
    if (!current) return;
    logSteps('workOrders', event.params.id, await pushWorkOrder(current, APPLY));
  },
);

export const pushEventToAdmin = onDocumentCreated(
  { document: 'workOrders/{id}/events/{eventId}', database: DATABASE_ID, region: REGION },
  async (event) => {
    const e = event.data?.data();
    if (!enabled() || !e) return;
    const order = (await db.doc(`workOrders/${event.params.id}`).get()).data();
    if (!order?.ref) return;
    const c = toAdminStatus(event.params.eventId, e, order.ref, await photoLinks(e.photos));
    logSteps('events', event.params.eventId, [await pushToAdmin(c, APPLY)]);
  },
);

export const pushMessageToAdmin = onDocumentCreated(
  { document: 'workOrders/{id}/messages/{messageId}', database: DATABASE_ID, region: REGION },
  async (event) => {
    const m = event.data?.data();
    // Messages that came from the dashboard are already there.
    if (!enabled() || !m || event.params.messageId.startsWith('admin_')) return;
    const order = (await db.doc(`workOrders/${event.params.id}`).get()).data();
    if (!order?.ref) return;
    const c = toAdminMessage(event.params.messageId, m, order.ref);
    logSteps('messages', event.params.messageId, [await pushToAdmin(c, APPLY)]);
  },
);

export const pushAttendanceToAdmin = onDocumentWritten(
  { document: 'attendance/{id}', database: DATABASE_ID, region: REGION },
  async (event) => {
    if (!enabled() || !event.data?.after.exists) return;
    const a = (await db.doc(`attendance/${event.params.id}`).get()).data(); // current, see above
    if (!a) return;
    logSteps('attendance', event.params.id, [await pushToAdmin(toAdminAttendance(event.params.id, a), APPLY)]);
  },
);

export const pushRequisitionToAdmin = onDocumentWritten(
  { document: 'requisitions/{id}', database: DATABASE_ID, region: REGION },
  async (event) => {
    if (!enabled() || !event.data?.after.exists) return;
    const r = (await db.doc(`requisitions/${event.params.id}`).get()).data(); // current, see above
    if (!r) return;
    logSteps('requisitions', event.params.id, [await pushToAdmin(toAdminRequisition(event.params.id, r), APPLY)]);
  },
);

// =========================================================== admin → app

const ACTIVE = ['open', 'in_progress', 'pending_review', 'returned'];

/** A dashboard work order: create the app's job, or apply the dashboard's edits. */
export async function pullWorkOrder(id: string, before: AdminDoc | undefined, after: AdminDoc, opts: SyncOptions): Promise<Step[]> {
  const ref = typeof after.workOrderId === 'string' && after.workOrderId ? after.workOrderId : id;
  const w = fromAdminWorkOrder(after);
  const existing = await appWorkOrderByRef(ref);

  if (!existing) {
    if (after.source === 'app') return [{ action: 'skip', target: `work_order/${id}`, detail: 'the app’s job is gone' }];
    if (!w.title || !w.locationId || !w.dueAt) {
      return [{ action: 'skip', target: `work_order/${id}`, detail: 'needs a title, facility and due date' }];
    }
    if (!(await db.doc(`locations/${w.locationId}`).get()).exists) {
      return [{ action: 'skip', target: `work_order/${id}`, detail: `facility ${w.locationId} isn’t in the app yet` }];
    }
    if (opts.apply) {
      await db.runTransaction((tx) => createOrder(tx, {
        docId: id,
        ref,
        type: w.type,
        title: w.title!,
        description: w.description,
        priority: w.priority,
        locationId: w.locationId!,
        assetId: w.assetId,
        assignedToId: w.assignedToId,
        supervisorId: w.supervisorId,
        dueAt: w.dueAt!,
        reportPhotos: w.attachments,
        // In its current status in one write, never open first.
        status: w.status ?? 'open',
        createdBy: 'admin-sync',
      }));
    }
    return [{ action: 'create', target: `workOrders/${id}`, detail: ref }];
  }

  // The app's own write coming back.
  if (isAppEcho(after)) {
    return [{ action: 'unchanged', target: `workOrders/${existing.id}` }];
  }
  // Only what the dashboard changed this time.
  const was = before ? fromAdminWorkOrder(before) : undefined;
  const moved = <K extends keyof typeof w>(k: K) => !was || !sameValue(was[k], w[k]);
  const o = existing.data();
  const changes: Record<string, unknown> = {};
  if (moved('title') && w.title && w.title !== o.title) changes.title = w.title;
  if (moved('description') && w.description !== o.description) changes.description = w.description;
  if (moved('priority') && w.priority !== o.priority) changes.priority = w.priority;
  if (moved('dueAt') && w.dueAt && !sameMinute(w.dueAt, o.dueAt)) changes.dueAt = w.dueAt;
  // The dashboard's status menu: the app's job follows.
  if (moved('status') && w.status && w.status !== o.status) {
    changes.status = w.status;
    const stamp = STATUS_TIMESTAMP[w.status];
    if (stamp) changes[stamp] = FieldValue.serverTimestamp();
  }
  if (ACTIVE.includes(o.status)) {
    if (moved('assignedToId') && w.assignedToId !== (o.assignedToId ?? null)) {
      changes.assignedToId = w.assignedToId;
      changes.assignedToName = await userName(w.assignedToId);
      changes.assignmentNote = null;
    }
    if (moved('supervisorId') && w.supervisorId !== (o.supervisorId ?? null)) {
      changes.supervisorId = w.supervisorId;
      changes.supervisorName = await userName(w.supervisorId);
    }
  }
  if (moved('assetId') && w.assetId !== (o.assetId ?? null)) {
    const asset = w.assetId ? (await db.doc(`assets/${w.assetId}`).get()).data() : undefined;
    changes.assetId = asset ? w.assetId : null;
    changes.assetName = asset?.equipmentName ?? null;
  }
  const target = `workOrders/${existing.id}`;
  if (Object.keys(changes).length === 0) return [{ action: 'unchanged', target }];
  if (opts.apply) {
    await existing.ref.update({ ...changes, updatedAt: FieldValue.serverTimestamp(), updatedBy: 'admin-sync' });
  }
  return [{ action: 'update', target, detail: Object.keys(changes).join(', ') }];
}

export const pullWorkOrderFromAdmin = onDocumentWritten(
  { document: 'work_order/{id}', database: '(default)', region: REGION, retry: false },
  async (event) => {
    const after = event.data?.after.data();
    if (!enabled() || !after) return;
    logSteps('work_order', event.params.id, await pullWorkOrder(event.params.id, event.data?.before.data(), after, APPLY));
  },
);

export async function pullMessage(msgId: string, m: AdminDoc, opts: SyncOptions): Promise<Step[]> {
  const order = typeof m.workOrderId === 'string' ? await appWorkOrderByRef(m.workOrderId) : undefined;
  if (!order) return [{ action: 'skip', target: `workorder_message/${msgId}`, detail: 'its job isn’t in the app' }];
  const c = fromAdminMessage(msgId, m, await adminPersonName(m.senderId));
  if (!c) return [{ action: 'skip', target: `workorder_message/${msgId}`, detail: 'empty' }];
  c.collection = `workOrders/${order.id}/messages`;
  // Messages are only ever created, so write them as they are.
  const ref = db.doc(`${c.collection}/${c.id}`);
  if ((await ref.get()).exists) return [{ action: 'unchanged', target: ref.path }];
  if (opts.apply) await ref.set(c.fields);
  return [{ action: 'create', target: ref.path }];
}

export const pullMessageFromAdmin = onDocumentCreated(
  { document: 'workorder_message/{id}', database: '(default)', region: REGION, retry: false },
  async (event) => {
    const m = event.data?.data();
    // Messages the app sent are already in the app.
    if (!enabled() || !m || event.params.id.startsWith('msg_app_')) return;
    logSteps('workorder_message', event.params.id, await pullMessage(event.params.id, m, APPLY));
  },
);

export async function pullRequisitionDecision(id: string, r: AdminDoc, opts: SyncOptions): Promise<Step[]> {
  const appId = id.replace(/^req_app_/, '');
  const ref = db.doc(`requisitions/${appId}`);
  const current = (await ref.get()).data();
  const decision = fromAdminRequisitionDecision(r, await adminPersonName(r.actionBy));
  if (!current || !decision || current.status !== 'pending') return [{ action: 'unchanged', target: ref.path }];
  if (opts.apply) {
    await ref.update({ ...decision, actionedAt: decision.actionedAt ?? Timestamp.now(), updatedAt: FieldValue.serverTimestamp(), updatedBy: 'admin-sync' });
    await notify([current.requestedById], {
      kind: 'requisition',
      title: decision.status === 'approved' ? 'Parts request approved' : 'Parts request rejected',
      body: `${current.ref ?? 'Your request'} · ${current.quantity} × ${current.itemName}${decision.rejectionReason ? ` · ${decision.rejectionReason}` : ''}`,
      workOrderId: current.workOrderId ?? null,
      workOrderRef: current.workOrderRef ?? null,
    });
  }
  return [{ action: 'update', target: ref.path, detail: decision.status }];
}

export const pullRequisitionFromAdmin = onDocumentWritten(
  { document: 'requisition/{id}', database: '(default)', region: REGION, retry: false },
  async (event) => {
    const r = event.data?.after.data();
    // Only decisions on requests that came from the app.
    if (!enabled() || !r || !event.params.id.startsWith('req_app_')) return;
    logSteps('requisition', event.params.id, await pullRequisitionDecision(event.params.id, r, APPLY));
  },
);
