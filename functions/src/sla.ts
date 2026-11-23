import { Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { DATABASE_ID, db, nextNumber, REGION, requireUser, text, UserDoc } from './common';

/** Africa/Lagos is UTC+1 all year (no daylight saving). */
const LAGOS_OFFSET_MS = 60 * 60 * 1000;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Work orders appear this long before they're due. */
export const LEAD_TIME_MS = 12 * 60 * 60 * 1000;

export type Frequency =
  | 'daily' | 'weekdays' | 'weekends' | 'weekly' | 'fortnightly'
  | 'monthly' | 'quarterly' | 'biannually' | 'annually';

/** A Lagos calendar day at "HH:mm" Lagos time, as a UTC instant. */
function atLagos(dayUtcMidnight: number, dueTime: string): number {
  const [h, m] = dueTime.split(':').map(Number);
  return dayUtcMidnight + (h * 60 + m) * 60 * 1000 - LAGOS_OFFSET_MS;
}

/** The Lagos calendar day containing [instant], as midnight UTC of that date. */
function lagosDay(instant: number): number {
  const local = instant + LAGOS_OFFSET_MS;
  return local - (local % DAY_MS);
}

function addMonths(dayUtcMidnight: number, months: number, anchorDate: number): number {
  const d = new Date(dayUtcMidnight);
  const target = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + months, 1));
  const lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  return Date.UTC(target.getUTCFullYear(), target.getUTCMonth(), Math.min(anchorDate, lastDay));
}

const isWeekend = (day: number) => [0, 6].includes(new Date(day).getUTCDay());

/** Whether a schedule runs on a Lagos day at all. */
function runsOn(frequency: Frequency, day: number): boolean {
  if (frequency === 'weekdays') return !isWeekend(day);
  if (frequency === 'weekends') return isWeekend(day);
  return true;
}

/**
 * The first run at or after [from]: on a day the schedule runs, at its due
 * time.
 */
export function firstRun(frequency: Frequency, startAt: number, dueTime: string, from = startAt): number {
  let day = lagosDay(Math.max(startAt, from));
  for (let i = 0; i < 8; i++, day += DAY_MS) {
    const run = atLagos(day, dueTime);
    if (run >= from && runsOn(frequency, day)) return run;
  }
  return atLagos(day, dueTime);
}

/** The run after [current]. Monthly schedules keep the start date's day. */
export function nextRun(frequency: Frequency, current: number, dueTime: string, startAt: number): number {
  const day = lagosDay(current);
  const anchor = new Date(lagosDay(startAt)).getUTCDate();
  switch (frequency) {
    case 'daily': return atLagos(day + DAY_MS, dueTime);
    case 'weekly': return atLagos(day + 7 * DAY_MS, dueTime);
    case 'fortnightly': return atLagos(day + 14 * DAY_MS, dueTime);
    case 'monthly': return atLagos(addMonths(day, 1, anchor), dueTime);
    case 'quarterly': return atLagos(addMonths(day, 3, anchor), dueTime);
    case 'biannually': return atLagos(addMonths(day, 6, anchor), dueTime);
    case 'annually': return atLagos(addMonths(day, 12, anchor), dueTime);
    case 'weekdays':
    case 'weekends':
      return firstRun(frequency, startAt, dueTime, atLagos(day + DAY_MS, '00:00'));
  }
}

/** Sets the first run when a schedule is created or switched back on. */
export const onSlaScheduleWrite = onDocumentWritten(
  { document: 'slaSchedules/{id}', database: DATABASE_ID, region: REGION },
  async (event) => {
    const after = event.data?.after.data();
    if (!after || after.status !== 'active' || after.nextRunAt) return;
    const run = firstRun(after.frequency, after.startAt.toMillis(), after.dueTime, Date.now());
    await event.data!.after.ref.update({ nextRunAt: Timestamp.fromMillis(run) });
  },
);

export interface NewOrder {
  /** Document ID and reference to use; otherwise new ones. */
  docId?: string;
  ref?: string;
  reportPhotos?: string[];
  /** Defaults to open. */
  status?: string;
  type: 'client' | 'sla';
  title: string;
  description: string;
  priority: string;
  locationId: string;
  zoneId?: string | null;
  assetId?: string | null;
  assignedToId?: string | null;
  supervisorId?: string | null;
  clientId?: string | null;
  slaId?: string | null;
  dueAt: Timestamp;
  createdBy: string;
}

/**
 * Creates a work order with the next WO- reference, copying names next to
 * IDs. Runs inside [tx]; every read happens before the first write.
 */
export async function createOrder(tx: FirebaseFirestore.Transaction, order: NewOrder) {
  const read = async (path: string | null | undefined) => (path ? (await tx.get(db.doc(path))).data() : undefined);
  const location = await read(`locations/${order.locationId}`);
  if (!location) throw new HttpsError('not-found', 'That location doesn’t exist.');
  const asset = await read(order.assetId ? `assets/${order.assetId}` : null);
  const zoneId = order.zoneId ?? asset?.zoneId ?? null;
  const zone = await read(zoneId ? `zones/${zoneId}` : null);
  const assignee = (await read(order.assignedToId ? `users/${order.assignedToId}` : null)) as UserDoc | undefined;
  const supervisorId = order.supervisorId ?? location.siteManagerId ?? null;
  const supervisor = (await read(supervisorId ? `users/${supervisorId}` : null)) as UserDoc | undefined;
  const client = (await read(order.clientId ? `users/${order.clientId}` : null)) as UserDoc | undefined;

  const ref = order.docId ? db.doc(`workOrders/${order.docId}`) : db.collection('workOrders').doc();
  const woRef = order.ref ?? `WO-${await nextNumber(tx, 'workOrders', 1001)}`;
  const now = Timestamp.now();
  const stamped = STAMP_FOR_STATUS[order.status ?? 'open'];
  tx.set(ref, {
    ...(stamped ? { [stamped]: now } : {}),
    ref: woRef,
    type: order.type,
    title: order.title,
    description: order.description,
    priority: order.priority,
    status: order.status ?? 'open',
    locationId: order.locationId,
    locationName: location.name,
    zoneId,
    zoneName: zone?.name ?? asset?.zoneName ?? null,
    assetId: order.assetId ?? null,
    assetName: asset?.equipmentName ?? null,
    companyId: client?.companyId ?? null,
    companyName: client?.companyName ?? null,
    clientId: order.clientId ?? null,
    clientName: client?.name ?? null,
    slaId: order.slaId ?? null,
    assignedToId: assignee ? order.assignedToId : null,
    assignedToName: assignee?.name ?? null,
    supervisorId: supervisor?.role === 'supervisor' ? supervisorId : null,
    supervisorName: supervisor?.role === 'supervisor' ? supervisor.name : null,
    assignmentNote: null,
    dueAt: order.dueAt,
    reportPhotos: order.reportPhotos ?? [],
    workPhotos: [],
    returnPhotos: [],
    inspectionChecks: [],
    inspectionPhotos: [],
    lastMessageAt: null,
    lastMessagePreview: null,
    createdAt: now,
    createdBy: order.createdBy,
    updatedAt: now,
    updatedBy: order.createdBy,
  });
  return { id: ref.id, ref: woRef };
}

/** When a job entered a status, for jobs created already past "open". */
const STAMP_FOR_STATUS: Record<string, string> = {
  in_progress: 'startedAt',
  pending_review: 'submittedAt',
  returned: 'returnedAt',
  completed: 'completedAt',
};

/** Admin only: a work order raised from the dashboard. */
export const createWorkOrder = onCall({ region: REGION }, async (request) => {
  const { uid } = await requireUser(request, ['admin']);
  const data = request.data ?? {};
  const priority = data.priority ?? 'medium';
  if (!['low', 'medium', 'high', 'critical'].includes(priority)) {
    throw new HttpsError('invalid-argument', 'Choose a priority.');
  }
  const dueAt = Date.parse(data.dueAt);
  if (!Number.isFinite(dueAt)) throw new HttpsError('invalid-argument', 'Give a due date.');
  return db.runTransaction((tx) =>
    createOrder(tx, {
      type: data.type === 'sla' ? 'sla' : 'client',
      title: text(data.title, 'Title', 1, 200),
      description: text(data.description, 'Description', 1, 4000),
      priority,
      locationId: text(data.locationId, 'Location', 1, 128),
      zoneId: data.zoneId ?? null,
      assetId: data.assetId ?? null,
      assignedToId: data.assignedToId ?? null,
      supervisorId: data.supervisorId ?? null,
      clientId: data.clientId ?? null,
      dueAt: Timestamp.fromMillis(dueAt),
      createdBy: uid,
    }),
  );
});

/**
 * Turns due SLA schedules into work orders, LEAD_TIME_MS before each run,
 * and moves each schedule on to its next run.
 */
export async function runDueSchedules(now = Date.now()): Promise<number> {
  const due = await db
    .collection('slaSchedules')
    .where('status', '==', 'active')
    .where('nextRunAt', '<=', Timestamp.fromMillis(now + LEAD_TIME_MS))
    .get();
  let created = 0;
  for (const doc of due.docs) {
    try {
      await db.runTransaction(async (tx) => {
        const sla = (await tx.get(doc.ref)).data();
        if (!sla || sla.status !== 'active' || sla.nextRunAt.toMillis() > now + LEAD_TIME_MS) return;
        // A dashboard schedule whose jobs the dashboard creates itself.
        if (sla.createsJobs === false) return;
        const run = sla.nextRunAt.toMillis();
        // An asset reference goes in assetId; a plain location in locationId.
        await createOrder(tx, {
          type: 'sla',
          title: sla.task,
          description: sla.description ?? sla.task,
          priority: sla.priority ?? 'high',
          locationId: sla.locationId,
          assetId: sla.assetId ?? null,
          assignedToId: sla.assignedToId,
          supervisorId: sla.supervisorId,
          slaId: doc.id,
          dueAt: Timestamp.fromMillis(run),
          createdBy: 'system',
        });
        tx.update(doc.ref, {
          lastRunAt: Timestamp.fromMillis(run),
          nextRunAt: Timestamp.fromMillis(nextRun(sla.frequency, run, sla.dueTime, sla.startAt.toMillis())),
        });
        created++;
      });
    } catch (error) {
      logger.error(`SLA schedule ${doc.id} failed`, error);
    }
  }
  return created;
}

export const runSlaSchedules = onSchedule(
  { schedule: 'every 15 minutes', timeZone: 'Africa/Lagos', region: REGION },
  async () => {
    const created = await runDueSchedules();
    if (created) logger.info(`created ${created} SLA work orders`);
  },
);
