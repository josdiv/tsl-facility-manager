import { initializeApp, getApps } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { FieldValue, Firestore, getFirestore } from 'firebase-admin/firestore';
import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';

if (getApps().length === 0) initializeApp();

/** The app's own database. The `(default)` database belongs to the admin
 * dashboard prototype and is never touched from here. */
export const DATABASE_ID = 'tsl-app';
export const REGION = 'europe-west1';
export const TIME_ZONE = 'Africa/Lagos';

export const db: Firestore = getFirestore(DATABASE_ID);
export const auth = getAuth();
export const serverTime = FieldValue.serverTimestamp;

export const isEmulator = process.env.FUNCTIONS_EMULATOR === 'true';

export type Role = 'admin' | 'supervisor' | 'staff' | 'client';

export interface UserDoc {
  role: Role;
  status: 'active' | 'inactive' | 'exited' | 'deleted';
  name: string;
  email: string;
  phone?: string | null;
  designation?: string | null;
  locationId?: string | null;
  locationName?: string | null;
  companyId?: string | null;
  companyName?: string | null;
}

/** The signed-in caller's active user document, or an error the app can show. */
export async function requireUser(
  request: CallableRequest,
  roles?: Role[],
): Promise<{ uid: string; user: UserDoc }> {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Please sign in again.');
  const snap = await db.doc(`users/${uid}`).get();
  const user = snap.data() as UserDoc | undefined;
  if (!user || user.status !== 'active') {
    throw new HttpsError('permission-denied', 'Your account is not active.');
  }
  if (roles && !roles.includes(user.role)) {
    throw new HttpsError('permission-denied', 'You can’t do that with this account.');
  }
  if (user.role === 'client') await requireActiveCompany(user.companyId);
  return { uid, user };
}

export async function requireActiveCompany(companyId?: string | null) {
  if (!companyId) throw new HttpsError('permission-denied', 'Your account has no company.');
  const company = (await db.doc(`companies/${companyId}`).get()).data();
  if (!company || company.status !== 'active') {
    throw new HttpsError(
      'permission-denied',
      company?.status === 'disabled' ? 'account-disabled' : 'account-locked',
    );
  }
  return company;
}

/** A required, trimmed string between min and max characters. */
export function text(value: unknown, field: string, min = 1, max = 4000): string {
  if (typeof value !== 'string') throw new HttpsError('invalid-argument', `${field} is missing.`);
  const trimmed = value.trim();
  if (trimmed.length < min || trimmed.length > max) {
    throw new HttpsError('invalid-argument', `${field} must be ${min} to ${max} characters.`);
  }
  return trimmed;
}

/** "yyyy-MM" for the current month in Lagos, for monthly usage counters. */
export function lagosMonth(date = new Date()): string {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: TIME_ZONE,
    year: 'numeric',
    month: '2-digit',
  }).formatToParts(date);
  const year = parts.find((p) => p.type === 'year')!.value;
  const month = parts.find((p) => p.type === 'month')!.value;
  return `${year}-${month}`;
}

/** Next number from counters/{name}, inside a transaction. */
export async function nextNumber(
  tx: FirebaseFirestore.Transaction,
  name: string,
  start: number,
): Promise<number> {
  const ref = db.doc(`counters/${name}`);
  const snap = await tx.get(ref);
  const next = (snap.data()?.next as number | undefined) ?? start;
  tx.set(ref, { next: next + 1 }, { merge: true });
  return next;
}

/** Great-circle distance in metres. */
export function distanceMetres(
  a: { latitude: number; longitude: number },
  b: { latitude: number; longitude: number },
): number {
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(b.latitude - a.latitude);
  const dLng = rad(b.longitude - a.longitude);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(rad(a.latitude)) * Math.cos(rad(b.latitude)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.sqrt(h));
}
