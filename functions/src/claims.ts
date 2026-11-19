import { logger } from 'firebase-functions';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { auth, DATABASE_ID, db, REGION, UserDoc } from './common';

/**
 * Cloud Storage rules can only read the (default) Firestore database, not
 * tsl-app, so what they need about a person travels in their sign-in token
 * instead:
 *
 *   role    admin | supervisor | staff | client
 *   active  the account is active (and, for a client, so is their company)
 *   locs    location IDs whose files they may use: a staff member's or
 *           supervisor's own location, or every location of a client's company
 *
 * The app refreshes its token before uploading, so changes reach Storage then.
 */
export interface StorageClaims {
  role: string | null;
  active: boolean;
  locs: string[];
}

export async function claimsFor(user: UserDoc | undefined): Promise<StorageClaims> {
  if (!user) return { role: null, active: false, locs: [] };
  if (user.role !== 'client') {
    return {
      role: user.role,
      active: user.status === 'active',
      locs: user.locationId ? [user.locationId] : [],
    };
  }
  const company = user.companyId
    ? (await db.doc(`companies/${user.companyId}`).get()).data()
    : undefined;
  return {
    role: 'client',
    active: user.status === 'active' && company?.status === 'active',
    locs: Array.isArray(company?.locationIds) ? (company.locationIds as string[]) : [],
  };
}

/** Writes a person's claims from their users document. */
export async function syncClaims(uid: string, user?: UserDoc): Promise<void> {
  const data = user ?? ((await db.doc(`users/${uid}`).get()).data() as UserDoc | undefined);
  try {
    await auth.setCustomUserClaims(uid, { ...(await claimsFor(data)) });
  } catch (error) {
    // No Auth account (e.g. a document written by hand), or claims too big.
    logger.warn(`couldn't set claims for ${uid}: ${(error as Error).message}`);
  }
}

const same = (a: unknown, b: unknown) => JSON.stringify(a ?? null) === JSON.stringify(b ?? null);

export const onUserAccessChange = onDocumentWritten(
  { document: 'users/{uid}', database: DATABASE_ID, region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data() as UserDoc | undefined;
    const keys = ['role', 'status', 'locationId', 'companyId'] as const;
    if (before && after && keys.every((k) => same(before[k], after[k]))) return;
    await syncClaims(event.params.uid, after);
  },
);

export const onCompanyAccessChange = onDocumentWritten(
  { document: 'companies/{id}', database: DATABASE_ID, region: REGION },
  async (event) => {
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    if (before && after && same(before.status, after.status) && same(before.locationIds, after.locationIds)) return;
    const clients = await db.collection('users').where('companyId', '==', event.params.id).get();
    for (const doc of clients.docs) await syncClaims(doc.id, doc.data() as UserDoc);
  },
);
