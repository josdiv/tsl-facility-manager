import { onDocumentCreated, onDocumentUpdated } from 'firebase-functions/v2/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { DATABASE_ID, db, nextNumber, REGION, requireUser, serverTime, text } from './common';
import { notify } from './notify';

const stockStatus = (quantity: number, threshold: number) =>
  quantity <= 0 ? 'out' : quantity <= threshold ? 'low' : 'ok';

/** Numbers a new request (REQ-1001, …) and tells the facility's supervisors. */
export const onRequisitionCreated = onDocumentCreated(
  { document: 'requisitions/{id}', database: DATABASE_ID, region: REGION },
  async (event) => {
    const request = event.data?.data();
    if (!request || request.ref) return;
    const ref = await db.runTransaction(async (tx) => {
      const number = await nextNumber(tx, 'requisitions', 1001);
      const value = `REQ-${number}`;
      tx.update(event.data!.ref, { ref: value });
      return value;
    });
    if (request.type !== 'out') return;
    const supervisors = await db
      .collection('users')
      .where('locationId', '==', request.locationId)
      .where('role', '==', 'supervisor')
      .where('status', '==', 'active')
      .get();
    await notify(
      supervisors.docs.map((d) => d.id),
      {
        kind: 'requisition',
        title: 'Parts requested',
        body: `${request.requestedByName} asked for ${request.quantity} × ${request.itemName} (${ref})`,
        workOrderId: request.workOrderId ?? null,
        workOrderRef: request.workOrderRef ?? null,
      },
      request.requestedById,
    );
  },
);

/**
 * Admin only: approves or rejects a request. Approving changes the stock in
 * the same transaction, and refuses if there isn't enough.
 */
export const actionRequisition = onCall({ region: REGION }, async (request) => {
  const { uid, user } = await requireUser(request, ['admin']);
  const requisitionId = text(request.data?.requisitionId, 'Request', 1, 128);
  const decision = request.data?.decision;
  if (decision !== 'approve' && decision !== 'reject') {
    throw new HttpsError('invalid-argument', 'Choose approve or reject.');
  }
  const reason = decision === 'reject' ? text(request.data?.reason, 'Reason', 1, 1000) : null;

  const outcome = await db.runTransaction(async (tx) => {
    const reqRef = db.doc(`requisitions/${requisitionId}`);
    const req = (await tx.get(reqRef)).data();
    if (!req) throw new HttpsError('not-found', 'That request doesn’t exist.');
    if (req.status !== 'pending') throw new HttpsError('failed-precondition', 'That request was already handled.');

    const now = serverTime();
    const actioned = { actionedById: uid, actionedByName: user.name, actionedAt: now, updatedAt: now, updatedBy: uid };
    if (decision === 'reject') {
      tx.update(reqRef, { status: 'rejected', rejectionReason: reason, ...actioned });
      return { req, status: 'rejected' as const };
    }

    const itemRef = db.doc(`inventory/${req.inventoryId}`);
    const item = (await tx.get(itemRef)).data();
    if (!item) throw new HttpsError('not-found', 'That stock item no longer exists.');
    const change = req.type === 'in' ? req.quantity : -req.quantity;
    const quantity = item.quantity + change;
    if (quantity < 0) {
      throw new HttpsError('failed-precondition', `Only ${item.quantity} in stock.`);
    }
    tx.update(itemRef, {
      quantity,
      stockStatus: stockStatus(quantity, item.alertThreshold),
      updatedAt: now,
      updatedBy: uid,
    });
    tx.update(reqRef, { status: 'approved', ...actioned });
    return { req, status: 'approved' as const };
  });

  const { req } = outcome;
  if (req.type === 'out') {
    await notify([req.requestedById], {
      kind: 'requisition',
      title: outcome.status === 'approved' ? 'Parts approved' : 'Parts request declined',
      body:
        outcome.status === 'approved'
          ? `${req.quantity} × ${req.itemName} (${req.ref}) is ready to collect`
          : `${req.ref}: ${reason}`,
      workOrderId: req.workOrderId ?? null,
      workOrderRef: req.workOrderRef ?? null,
    });
  }
  return { status: outcome.status };
});

/** Numbers new assets (AST-000001) and stock items (SKU-000001). */
function refFor(collection: 'assets' | 'inventory', prefix: string) {
  return onDocumentCreated(
    { document: `${collection}/{id}`, database: DATABASE_ID, region: REGION },
    async (event) => {
      if (!event.data || event.data.data().ref) return;
      await db.runTransaction(async (tx) => {
        const number = await nextNumber(tx, collection, 1);
        tx.update(event.data!.ref, { ref: `${prefix}-${String(number).padStart(6, '0')}` });
      });
    },
  );
}

export const assignAssetRef = refFor('assets', 'AST');
export const assignInventoryRef = refFor('inventory', 'SKU');

/** Keeps copied names in step when someone's name changes. */
export const onUserNameChange = onDocumentUpdated(
  { document: 'users/{uid}', database: DATABASE_ID, region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (!before || !after || before.name === after.name) return;
    const uid = event.params.uid;
    const copies: [string, string, string][] = [
      ['workOrders', 'assignedToId', 'assignedToName'],
      ['workOrders', 'clientId', 'clientName'],
      ['workOrders', 'supervisorId', 'supervisorName'],
      ['locations', 'siteManagerId', 'siteManagerName'],
      ['requisitions', 'requestedById', 'requestedByName'],
    ];
    for (const [collection, idField, nameField] of copies) {
      const snap = await db.collection(collection).where(idField, '==', uid).get();
      // Batches hold at most 500 writes.
      for (let i = 0; i < snap.docs.length; i += 450) {
        const batch = db.batch();
        for (const doc of snap.docs.slice(i, i + 450)) batch.update(doc.ref, { [nameField]: after.name });
        await batch.commit();
      }
    }
  },
);
