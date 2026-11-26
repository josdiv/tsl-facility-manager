import { GeoPoint, Timestamp } from 'firebase-admin/firestore';
import { onDocumentCreated, onDocumentWritten } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { readPosition, requireOnSite } from './geofence';
import { notify, supervisorsOf } from './notify';
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

/** Up to [max] Storage paths, all under locations/{locationId}/workOrders/{id}/{kind}/. */
function photoPaths(value: unknown, locationId: string, workOrderId: string, kind: string, max: number): string[] {
  if (value == null) return [];
  if (!Array.isArray(value) || value.length > max) {
    throw new HttpsError('invalid-argument', `Add up to ${max} photos.`);
  }
  const prefix = `locations/${locationId}/workOrders/${workOrderId}/${kind}/`;
  for (const path of value) {
    if (typeof path !== 'string' || !path.startsWith(prefix) || path.slice(prefix.length).includes('/')) {
      throw new HttpsError('invalid-argument', 'A photo is in the wrong place.');
    }
  }
  return value as string[];
}

/**
 * A client reports an issue from the facility they're at. Checks their
 * position, their company's status and monthly limit,
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
  // Optional: many facilities have no zones set up in the dashboard yet.
  let zoneId = data.zoneId == null || data.zoneId === '' ? null : text(data.zoneId, 'Zone', 1, 128);
  // Optional: the equipment at fault. Its zone comes from the asset itself.
  const assetId = data.assetId == null || data.assetId === '' ? null : text(data.assetId, 'Asset', 1, 128);
  const reportPhotos = photoPaths(data.photos, locationId, workOrderId, 'report', 4);
  // Clients report from the facility itself, which keeps out spam reports.
  const position = readPosition(data.position);

  const companyRef = db.doc(`companies/${user.companyId}`);
  const usageRef = companyRef.collection('usage').doc(lagosMonth());

  return db.runTransaction(async (tx) => {
    const asset = assetId ? await tx.get(db.doc(`assets/${assetId}`)) : null;
    if (asset) {
      const a = asset.data();
      if (!a || a.locationId !== locationId || a.status === 'inactive') {
        throw new HttpsError('invalid-argument', 'That equipment isn’t at this facility.');
      }
      zoneId = typeof a.zoneId === 'string' && a.zoneId ? a.zoneId : zoneId;
    }
    const [company, location, zone, usage, existing] = await Promise.all([
      tx.get(companyRef),
      tx.get(db.doc(`locations/${locationId}`)),
      zoneId ? tx.get(db.doc(`zones/${zoneId}`)) : Promise.resolve(null),
      tx.get(usageRef),
      tx.get(db.doc(`workOrders/${workOrderId}`)),
    ]);
    if (existing.exists) throw new HttpsError('already-exists', 'That request was already sent.');
    const companyData = company.data()!;
    // Clients see every facility but can only report from the one they're at.
    if (!location.exists || location.data()!.status !== 'active') {
      throw new HttpsError('permission-denied', 'You can’t report issues for that facility.');
    }
    // The App Review demo facility only takes reports from review accounts.
    const settings = (await tx.get(db.doc('settings/public'))).data();
    const reviewOnly = (settings?.reviewFacilityIds as string[] | undefined) ?? [];
    const reviewers = (settings?.reviewAccountIds as string[] | undefined) ?? [];
    if (reviewOnly.includes(locationId) && !reviewers.includes(uid)) {
      throw new HttpsError('permission-denied', 'You can’t report issues for that facility.');
    }
    if (zone && zone.data()?.locationId !== locationId) {
      throw new HttpsError('invalid-argument', 'That zone isn’t at this facility.');
    }
    const used = (usage.data()?.workOrderCount as number | undefined) ?? 0;
    const limit = companyData.monthlyWorkOrderLimit as number | null;
    if (limit != null && used >= limit) {
      throw new HttpsError('resource-exhausted', 'monthly-limit');
    }

    // Transactions must finish every read before the first write.
    const locationData = location.data()!;
    // Without a position the facility can't confirm the client is there.
    const geo = locationData.geo as GeoPoint | null;
    if (!geo) throw new HttpsError('failed-precondition', 'no-site-position');
    const distanceM = requireOnSite(geo, locationData.radiusM, position, data.position?.isMocked);
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
      zoneName: zone ? zone.data()!.name : null,
      assetId: asset ? asset.id : null,
      assetName: asset ? (asset.data()!.equipmentName ?? asset.id) : null,
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
      reportGeo: new GeoPoint(position.latitude, position.longitude),
      reportDistanceM: distanceM,
      reportAccuracyM: Math.round(position.accuracyM),
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
    const fromDashboard = actorId === 'admin-sync';
    const base = {
      statusAfter: after.status,
      actorId,
      actorName: actor?.name ?? (fromDashboard ? 'Admin dashboard' : 'System'),
      actorRole: actor?.role ?? (fromDashboard ? 'admin' : 'system'),
      createdAt: serverTime(),
    };
    const events = db.collection(`workOrders/${event.params.id}/events`);

    const id = event.params.id;
    const about = { workOrderId: id, workOrderRef: after.ref as string };

    if (!before) {
      await events.add({
        ...base,
        kind: 'reported',
        note: after.type === 'sla' ? 'Scheduled by SLA plan' : null,
        photos: after.reportPhotos ?? [],
      });
      if (after.type === 'sla') {
        await notify([after.assignedToId], {
          kind: 'sla_due',
          title: 'SLA task due',
          body: `${after.ref} ${after.title} · ${after.locationName}`,
          ...about,
        });
      } else {
        await notify(await supervisorsOf(after), {
          kind: 'system',
          title: 'New request',
          body: `${after.ref} ${after.title} · ${after.zoneName ?? after.locationName}`,
          ...about,
        });
      }
      return;
    }
    if (before.status !== after.status && EVENT_FOR_STATUS[after.status]) {
      const kind = EVENT_FOR_STATUS[after.status];
      await events.add({
        ...base,
        kind,
        note:
          // A step taken in the dashboard has no note.
          (kind === 'returned'
            ? after.returnFeedback
            : kind === 'confirmed'
              ? after.inspectionNote
              : kind === 'submitted'
                ? after.workNote
                : null) ?? null,
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
      await notify([after.assignedToId], {
        kind: 'assigned',
        title: 'New assignment',
        body: [`${after.ref} ${after.title} was assigned to you`, after.assignmentNote].filter(Boolean).join(' · '),
        ...about,
      }, actorId);
      if (!before.assignedToId) {
        await notify([after.clientId], {
          kind: 'assigned',
          title: 'Technician assigned',
          body: `${after.assignedToName} is working on ${after.ref}`,
          ...about,
        });
      }
    }

    if (before.status !== after.status) {
      switch (after.status) {
        case 'pending_review':
          await notify(await supervisorsOf(after), {
            kind: 'submitted',
            title: 'Work ready for review',
            body: `${base.actorName} submitted ${after.ref} ${after.title}`,
            ...about,
          }, actorId);
          break;
        case 'returned':
          await notify([after.assignedToId], {
            kind: 'returned',
            title: 'Task returned for correction',
            body: `${after.ref} · ${after.returnFeedback ?? after.title}`,
            ...about,
          }, actorId);
          break;
        case 'completed':
          await notify([after.clientId], {
            kind: 'completed',
            title: 'Request resolved',
            body: `${after.ref} ${after.title} is complete`,
            ...about,
          });
          await notify([after.assignedToId], {
            kind: 'completed',
            title: 'Work confirmed',
            body: `${base.actorName} confirmed ${after.ref} ${after.title}`,
            ...about,
          }, actorId);
          break;
      }
    }
  },
);

/** Keeps the work order's latest-message preview up to date. */
export const onWorkOrderMessage = onDocumentCreated(
  { document: 'workOrders/{id}/messages/{messageId}', database: DATABASE_ID, region: REGION },
  async (event) => {
    const message = event.data?.data();
    if (!message) return;
    const ref = db.doc(`workOrders/${event.params.id}`);
    await ref.update({
      lastMessageAt: message.sentAt ?? serverTime(),
      lastMessagePreview: String(message.text).slice(0, 120),
    });
    const order = (await ref.get()).data();
    if (!order) return;
    await notify(
      [order.clientId, order.assignedToId, order.supervisorId],
      {
        kind: 'message',
        title: `New message on ${order.ref}`,
        body: `${message.senderName}: ${String(message.text).slice(0, 120)}`,
        workOrderId: event.params.id,
        workOrderRef: order.ref,
      },
      message.senderId,
    );
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
