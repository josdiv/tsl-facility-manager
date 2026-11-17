import { Timestamp } from 'firebase-admin/firestore';
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import {
  DATABASE_ID,
  db,
  lagosMonth,
  nextNumber,
  REGION,
  requireUser,
  serverTime,
  text,
  UserDoc,
} from './common';

const DAY_MS = 24 * 60 * 60 * 1000;

/** Up to [max] Storage paths, all under workOrders/{id}/{kind}/. */
function photoPaths(value: unknown, workOrderId: string, kind: string, max: number): string[] {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > max) {
    throw new HttpsError('invalid-argument', `Add up to ${max} photos.`);
  }
  const prefix = `workOrders/${workOrderId}/${kind}/`;
  for (const path of value) {
    if (typeof path !== 'string' || !path.startsWith(prefix) || path.slice(prefix.length).includes('/')) {
      throw new HttpsError('invalid-argument', 'A photo is in the wrong place.');
    }
  }
  return value as string[];
}

/**
 * A client reports an issue. Checks their company's status and monthly limit,
 * assigns the next WO- reference, and creates the work order.
 *
 * The app picks the document ID first, so it can upload photos to
 * workOrders/{id}/report/ before calling this.
 */
export const reportIssue = onCall({ region: REGION }, async (request) => {
  const { uid, user } = await requireUser(request, ['client']);
  const data = request.data ?? {};
  const workOrderId = text(data.workOrderId, 'Work order ID', 10, 40);
  if (!/^[A-Za-z0-9]+$/.test(workOrderId)) throw new HttpsError('invalid-argument', 'Bad work order ID.');
  const title = text(data.title, 'Title', 1, 200);
  const description = text(data.description, 'Description', 1, 4000);
  const locationId = text(data.locationId, 'Location', 1, 128);
  const zoneId = text(data.zoneId, 'Zone', 1, 128);
  const reportPhotos = photoPaths(data.photos, workOrderId, 'report', 4);

  const companyRef = db.doc(`companies/${user.companyId}`);
  const usageRef = companyRef.collection('usage').doc(lagosMonth());

  return db.runTransaction(async (tx) => {
    const [company, location, zone, usage, existing] = await Promise.all([
      tx.get(companyRef),
      tx.get(db.doc(`locations/${locationId}`)),
      tx.get(db.doc(`zones/${zoneId}`)),
      tx.get(usageRef),
      tx.get(db.doc(`workOrders/${workOrderId}`)),
    ]);
    if (existing.exists) throw new HttpsError('already-exists', 'That request was already sent.');
    const companyData = company.data()!;
    if (!(companyData.locationIds as string[]).includes(locationId) || !location.exists) {
      throw new HttpsError('permission-denied', 'You can’t report issues for that facility.');
    }
    if (zone.data()?.locationId !== locationId) {
      throw new HttpsError('invalid-argument', 'That zone isn’t at this facility.');
    }
    const used = (usage.data()?.workOrderCount as number | undefined) ?? 0;
    const limit = companyData.monthlyWorkOrderLimit as number | null;
    if (limit != null && used >= limit) {
      throw new HttpsError('resource-exhausted', 'monthly-limit');
    }

    // Transactions must finish every read before the first write.
    const locationData = location.data()!;
    const supervisor = locationData.siteManagerId
      ? (await tx.get(db.doc(`users/${locationData.siteManagerId}`))).data()
      : undefined;
    const number = await nextNumber(tx, 'workOrders', 1001);
    const ref = `WO-${number}`;
    const now = Timestamp.now();

    tx.set(usageRef, { workOrderCount: used + 1 }, { merge: true });
    tx.set(db.doc(`workOrders/${workOrderId}`), {
      ref,
      type: 'client',
      title,
      description,
      priority: 'medium',
      status: 'open',
      locationId,
      locationName: locationData.name,
      zoneId,
      zoneName: zone.data()!.name,
      assetId: null,
      assetName: null,
      companyId: user.companyId,
      companyName: companyData.name,
      clientId: uid,
      clientName: user.name,
      slaId: null,
      assignedToId: null,
      assignedToName: null,
      supervisorId: supervisor?.role === 'supervisor' ? locationData.siteManagerId : null,
      supervisorName: supervisor?.role === 'supervisor' ? supervisor.name : null,
      assignmentNote: null,
      dueAt: Timestamp.fromMillis(now.toMillis() + DAY_MS),
      reportPhotos,
      workPhotos: [],
      returnPhotos: [],
      inspectionChecks: [],
      inspectionPhotos: [],
      lastMessageAt: null,
      lastMessagePreview: null,
      createdAt: now,
      createdBy: uid,
      updatedAt: now,
      updatedBy: uid,
    });
    return { id: workOrderId, ref };
  });
});

const EVENT_FOR_STATUS: Record<string, string> = {
  in_progress: 'started',
  pending_review: 'submitted',
  returned: 'returned',
  completed: 'confirmed',
  cancelled: 'cancelled',
};

/** Writes the timeline entry for each status or assignee change. */
export const onWorkOrderWrite = onDocumentWritten(
  { document: 'workOrders/{id}', database: DATABASE_ID, region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!after) return;

    const actorId: string = after.updatedBy ?? 'system';
    const actor =
      actorId === 'system'
        ? undefined
        : ((await db.doc(`users/${actorId}`).get()).data() as UserDoc | undefined);
    const base = {
      statusAfter: after.status,
      actorId,
      actorName: actor?.name ?? 'System',
      actorRole: actor?.role ?? 'system',
      createdAt: serverTime(),
    };
    const events = db.collection(`workOrders/${event.params.id}/events`);

    if (!before) {
      await events.add({
        ...base,
        kind: 'reported',
        note: after.type === 'sla' ? 'Scheduled by SLA plan' : null,
        photos: after.reportPhotos ?? [],
      });
      return;
    }
    if (before.status !== after.status && EVENT_FOR_STATUS[after.status]) {
      const kind = EVENT_FOR_STATUS[after.status];
      await events.add({
        ...base,
        kind,
        note:
          kind === 'returned'
            ? after.returnFeedback
            : kind === 'confirmed'
              ? after.inspectionNote ?? null
              : kind === 'submitted'
                ? after.workNote
                : null,
        photos:
          kind === 'returned'
            ? after.returnPhotos ?? []
            : kind === 'confirmed'
              ? after.inspectionPhotos ?? []
              : kind === 'submitted'
                ? after.workPhotos ?? []
                : [],
      });
    }
    if (before.assignedToId !== after.assignedToId && after.assignedToId) {
      await events.add({
        ...base,
        kind: before.assignedToId ? 'reassigned' : 'assigned',
        note: [`Assigned to ${after.assignedToName}`, after.assignmentNote].filter(Boolean).join(' · '),
        photos: [],
      });
    }
  },
);

/** Keeps the work order's latest-message preview up to date. */
export const onWorkOrderMessage = onDocumentCreated(
  { document: 'workOrders/{id}/messages/{messageId}', database: DATABASE_ID, region: REGION },
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    await db.doc(`workOrders/${event.params.id}`).update({
      lastMessageAt: message.sentAt ?? serverTime(),
      lastMessagePreview: String(message.text).slice(0, 120),
    });
  },
);

/** Keeps the support thread summary up to date for the admin inbox. */
export const onSupportMessage = onDocumentCreated(
  { document: 'supportThreads/{uid}/messages/{messageId}', database: DATABASE_ID, region: REGION },
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    const owner = (await db.doc(`users/${event.params.uid}`).get()).data() as UserDoc | undefined;
    await db.doc(`supportThreads/${event.params.uid}`).set(
      {
        userId: event.params.uid,
        userName: owner?.name ?? 'Unknown',
        userRole: owner?.role ?? 'client',
        lastMessageAt: message.sentAt ?? serverTime(),
        lastMessagePreview: String(message.text).slice(0, 120),
        unreadByAdmin: message.senderRole !== 'admin',
      },
      { merge: true },
    );
  },
);
