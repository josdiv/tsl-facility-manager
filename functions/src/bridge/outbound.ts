/**
 * Converts the app's records (tsl-app) into the admin dashboard's format
 * ((default)), for step 2 of docs/admin-db-integration-plan.md, and back for
 * the changes the dashboard is allowed to make. Pure functions.
 */
import { Timestamp } from 'firebase-admin/firestore';
import { AdminDoc, Converted } from './convert';

const LAGOS_MS = 60 * 60 * 1000;
const pad = (n: number) => String(n).padStart(2, '0');

/** A moment as Lagos date "2026-11-23" and time "14:05:09". */
export function lagosParts(t: Timestamp | null | undefined) {
  if (!t) return { date: null, time: null, hhmm: null };
  const d = new Date(t.toMillis() + LAGOS_MS);
  const date = `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
  const hhmm = `${pad(d.getUTCHours())}:${pad(d.getUTCMinutes())}`;
  return { date, time: `${hhmm}:${pad(d.getUTCSeconds())}`, hhmm };
}

/** Lagos "2026-11-23" + "14:05" back to a moment. */
export function fromLagos(date: unknown, time: unknown): Timestamp | null {
  if (typeof date !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(date.trim())) return null;
  const m = /^(\d{1,2}):(\d{2})/.exec(typeof time === 'string' ? time : '');
  const clock = m ? `${m[1].padStart(2, '0')}:${m[2]}` : '00:00';
  const ms = Date.parse(`${date.trim()}T${clock}:00+01:00`);
  return Number.isFinite(ms) ? Timestamp.fromMillis(ms) : null;
}

const title = (s: string) => s.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());

export const STATUS_TO_ADMIN: Record<string, string> = {
  open: 'Open',
  in_progress: 'In Progress',
  pending_review: 'Pending Review',
  // The dashboard's word for work sent back for correction.
  returned: 'Rejected',
  completed: 'Completed',
  cancelled: 'Cancelled',
};

const ROLE_TO_ADMIN: Record<string, string> = {
  admin: 'Admin', supervisor: 'Supervisor', staff: 'Staff', client: 'Client', system: 'System',
};

// ----------------------------------------------------------- work orders

/**
 * An app work order as the dashboard's `work_order/{ref}`. [fields] are kept
 * in step on every change; [onCreate] only when the dashboard copy is made,
 * so a job the dashboard created keeps its own attachments and author.
 */
export function toAdminWorkOrder(o: AdminDoc, reportPhotoUrls: string[]): Converted {
  const ref = String(o.ref);
  const due = lagosParts(o.dueAt as Timestamp);
  return {
    collection: 'work_order',
    id: ref,
    fields: {
      title: o.title ?? '',
      description: o.description ?? '',
      type: o.type === 'sla' ? 'SLA' : 'Client',
      priority: title(String(o.priority ?? 'medium')),
      status: STATUS_TO_ADMIN[String(o.status)] ?? 'Open',
      locationId: o.locationId ?? '',
      assetId: o.assetId ?? '',
      assignedTo: o.assignedToId ?? '',
      supervisedBy: o.supervisorId ?? '',
      dueDate: due.date ?? '',
      dueTime: due.hhmm ?? '',
    },
    onCreate: {
      workOrderId: ref,
      attachments: reportPhotoUrls,
      createdAt: o.createdAt ?? Timestamp.now(),
      createdBy: o.type === 'sla' ? 'System' : 'Client',
      source: 'app',
    },
  };
}

const KIND_TO_ADMIN: Record<string, string> = {
  reported: 'Reported',
  assigned: 'assigned',
  reassigned: 'assigned',
  started: 'In Progress',
  submitted: 'Pending Review',
  returned: 'Returned',
  confirmed: 'Completed',
  cancelled: 'Cancelled',
};

/** A timeline event as the dashboard's `workorder_status`, photos as links. */
export function toAdminStatus(eventId: string, e: AdminDoc, ref: string, photoUrls: string[]): Converted {
  const [p1 = '', p2 = '', p3 = '', p4 = ''] = photoUrls;
  return {
    collection: 'workorder_status',
    id: `STAT_app_${eventId}`,
    fields: {
      statusId: `STAT_app_${eventId}`,
      workOrderId: ref,
      staffId: e.actorId ?? 'system',
      statusDescription: KIND_TO_ADMIN[String(e.kind)] ?? String(e.kind),
      statusComment: e.note ?? '',
      others: e.actorName ?? '',
      photo1: p1,
      photo2: p2,
      photo3: p3,
      photo4: p4,
      createdAt: e.createdAt ?? Timestamp.now(),
      createdBy: ROLE_TO_ADMIN[String(e.actorRole)] ?? 'System',
    },
    onCreate: {},
  };
}

// ------------------------------------------------------------------ chat

export function toAdminMessage(messageId: string, m: AdminDoc, ref: string): Converted {
  return {
    collection: 'workorder_message',
    id: `msg_app_${messageId}`,
    fields: {
      msgId: `msg_app_${messageId}`,
      workOrderId: ref,
      senderId: m.senderId ?? '',
      senderType: m.senderRole ?? 'staff',
      message: m.text ?? '',
      sendDateTime: m.sentAt ?? Timestamp.now(),
    },
    onCreate: {},
  };
}

const SENDER_ROLES = ['admin', 'supervisor', 'staff', 'client'];

/** A dashboard chat message as the app's message on that job. */
export function fromAdminMessage(msgId: string, m: AdminDoc, senderName: string | null): Converted | null {
  const text = typeof m.message === 'string' ? m.message.trim().slice(0, 2000) : '';
  if (!text) return null;
  const role = String(m.senderType ?? '').toLowerCase();
  return {
    collection: 'messages',
    id: `admin_${msgId}`,
    fields: {
      text,
      senderId: m.senderId ?? 'admin',
      senderName: senderName ?? 'Admin',
      senderRole: SENDER_ROLES.includes(role) ? role : 'admin',
      sentAt: m.sendDateTime instanceof Timestamp ? m.sendDateTime : Timestamp.now(),
    },
    onCreate: {},
  };
}

// ------------------------------------------------------------ attendance

const ATTENDANCE_TO_ADMIN: Record<string, string> = { present: 'Present', absent: 'Absent', off_duty: 'Off Duty' };

export function toAdminAttendance(id: string, a: AdminDoc): Converted {
  const inAt = lagosParts(a.clockInAt as Timestamp);
  const outAt = lagosParts(a.clockOutAt as Timestamp | null);
  return {
    collection: 'attendance',
    id: `att_app_${id}`,
    fields: {
      attendanceId: `att_app_${id}`,
      staffId: a.userId ?? '',
      locationId: a.locationId ?? '',
      clockInDate: inAt.date,
      clockInTime: inAt.time,
      clockOutDate: outAt.date,
      clockOutTime: outAt.time,
      status: a.status === 'clocked_in' ? 'Clocked In' : 'Clock Out',
      attendanceStatus: ATTENDANCE_TO_ADMIN[String(a.attendanceStatus)] ?? 'Present',
      gpsDistance: typeof a.clockInDistanceM === 'number' ? a.clockInDistanceM : 0,
    },
    onCreate: { createdAt: a.createdAt ?? Timestamp.now(), createdBy: 'Staff', source: 'app' },
  };
}

// ------------------------------------------------------- parts requests

export function toAdminRequisition(id: string, r: AdminDoc): Converted {
  return {
    collection: 'requisition',
    id: `req_app_${id}`,
    fields: {
      requisitionId: r.ref ?? `req_app_${id}`,
      inventoryId: r.inventoryId ?? '',
      quantity: r.quantity ?? 0,
      reason: r.reason ?? '',
      requestBy: r.requestedById ?? '',
      requestDate: r.requestedAt ?? r.createdAt ?? Timestamp.now(),
      requisitionType: r.type === 'in' ? 'In' : 'Out',
      status: title(String(r.status ?? 'pending')),
      workOrderId: r.workOrderRef ?? '',
    },
    onCreate: {
      actionBy: null,
      actionDate: null,
      createdAt: r.createdAt ?? Timestamp.now(),
      createdBy: r.requestedById ?? '',
      source: 'app',
    },
  };
}

/**
 * The dashboard's decision on a request the app sent: the app's status and
 * who decided. Stock stays with the dashboard (plan, question 5).
 */
export function fromAdminRequisitionDecision(r: AdminDoc, deciderName: string | null) {
  const status = String(r.status ?? '').toLowerCase();
  if (status !== 'approved' && status !== 'rejected') return null;
  return {
    status,
    actionedById: typeof r.actionBy === 'string' ? r.actionBy : null,
    actionedByName: deciderName,
    actionedAt: r.actionDate instanceof Timestamp ? r.actionDate : typeof r.actionDate === 'string' ? fromLagos(r.actionDate, '00:00') : null,
    rejectionReason: status === 'rejected' && typeof r.rejectionReason === 'string' ? r.rejectionReason : null,
  };
}

// ------------------------------------------- dashboard work order edits

/** The dashboard's status names in the app's terms. */
export const STATUS_FROM_ADMIN: Record<string, string> = {
  'open': 'open',
  'assigned': 'open',
  'in progress': 'in_progress',
  'pending review': 'pending_review',
  'completed': 'completed',
  'rejected': 'returned',
  'returned': 'returned',
  'cancelled': 'cancelled',
  'canceled': 'cancelled',
};

/** When the app's job entered each status, set when the dashboard moves it. */
export const STATUS_TIMESTAMP: Record<string, string> = {
  in_progress: 'startedAt',
  pending_review: 'submittedAt',
  returned: 'returnedAt',
  completed: 'completedAt',
};

/**
 * The fields of an app work order the dashboard may change, from its copy:
 * wording, priority, due time, people, asset and status. The dashboard's
 * status menu moves the job in the app too (agreed 23 Nov 2026).
 */
export function fromAdminWorkOrder(w: AdminDoc) {
  const priority = String(w.priority ?? '').toLowerCase();
  return {
    title: typeof w.title === 'string' && w.title.trim() ? w.title.trim() : null,
    description: typeof w.description === 'string' ? w.description : '',
    priority: ['low', 'medium', 'high', 'critical'].includes(priority) ? priority : 'medium',
    dueAt: fromLagos(w.dueDate, w.dueTime),
    assignedToId: typeof w.assignedTo === 'string' && w.assignedTo ? w.assignedTo : null,
    supervisorId: typeof w.supervisedBy === 'string' && w.supervisedBy ? w.supervisedBy : null,
    locationId: typeof w.locationId === 'string' && w.locationId ? w.locationId : null,
    assetId: typeof w.assetId === 'string' && w.assetId ? w.assetId : null,
    type: String(w.type ?? '').toLowerCase() === 'sla' ? ('sla' as const) : ('client' as const),
    status: STATUS_FROM_ADMIN[String(w.status ?? '').trim().toLowerCase()] ?? null,
    attachments: Array.isArray(w.attachments) ? w.attachments.filter((x): x is string => typeof x === 'string') : [],
  };
}

/** Whether two due times are the same to the minute (the dashboard keeps minutes). */
export const sameMinute = (a: Timestamp | null | undefined, b: Timestamp | null | undefined) =>
  !!a && !!b && Math.floor(a.toMillis() / 60000) === Math.floor(b.toMillis() / 60000);
