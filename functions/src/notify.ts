import { logger } from 'firebase-functions';
import { db, serverTime } from './common';
import { sendPush } from './push';

export interface Notice {
  kind: 'assigned' | 'returned' | 'sla_due' | 'submitted' | 'completed' | 'message' | 'requisition' | 'system';
  title: string;
  body: string;
  workOrderId?: string | null;
  workOrderRef?: string | null;
}

/**
 * Gives each person an in-app notification and a push to each of their
 * devices. [except] is left out (usually whoever caused it). Push delivery
 * is best effort: the in-app notification is what counts.
 */
export async function notify(uids: (string | null | undefined)[], notice: Notice, except?: string) {
  const people = [...new Set(uids.filter((uid): uid is string => !!uid && uid !== except))];
  await Promise.all(
    people.map(async (uid) => {
      await db.collection(`users/${uid}/notifications`).add({
        kind: notice.kind,
        title: notice.title,
        body: notice.body,
        workOrderId: notice.workOrderId ?? null,
        workOrderRef: notice.workOrderRef ?? null,
        requisitionId: null,
        createdAt: serverTime(),
        readAt: null,
      });
      const tokens = (await db.collection(`users/${uid}/fcmTokens`).get()).docs.map((d) => d.id);
      if (tokens.length === 0) {
        logger.info(`no push devices for ${uid}; in-app notification only`);
        return;
      }
      await sendPush(uid, tokens, {
        title: notice.title,
        body: notice.body,
        data: {
          kind: notice.kind,
          ...(notice.workOrderId ? { workOrderId: notice.workOrderId } : {}),
          ...(notice.workOrderRef ? { workOrderRef: notice.workOrderRef } : {}),
        },
      });
    }),
  );
}

/** The supervisors to tell about work at a location. */
export async function supervisorsOf(order: FirebaseFirestore.DocumentData): Promise<string[]> {
  if (order.supervisorId) return [order.supervisorId];
  const snap = await db
    .collection('users')
    .where('locationId', '==', order.locationId)
    .where('role', '==', 'supervisor')
    .where('status', '==', 'active')
    .get();
  return snap.docs.map((d) => d.id);
}
