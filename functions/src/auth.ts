import { createHash, randomInt } from 'node:crypto';
import { Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import {
  auth,
  db,
  isEmulator,
  REGION,
  requireActiveCompany,
  requireUser,
  Role,
  serverTime,
  text,
  UserDoc,
} from './common';

const CODE_TTL_MS = 10 * 60 * 1000;
const RESEND_AFTER_MS = 60 * 1000;
const MAX_ATTEMPTS = 5;

const normaliseEmail = (value: unknown) => text(value, 'Email', 3, 254).toLowerCase();
const emailKey = (email: string) => createHash('sha256').update(email).digest('hex');
const hashCode = (email: string, code: string) =>
  createHash('sha256').update(`${email}:${code}`).digest('hex');

async function findClient(email: string) {
  const snap = await db
    .collection('users')
    .where('email', '==', email)
    .where('role', '==', 'client')
    .limit(1)
    .get();
  return snap.docs[0];
}

/**
 * Emails a 6-digit sign-in code to a client. Always answers the same way, so
 * the form can't be used to find out which emails have accounts.
 */
export const sendEmailCode = onCall({ region: REGION }, async (request) => {
  const email = normaliseEmail(request.data?.email);
  const ref = db.doc(`emailCodes/${emailKey(email)}`);
  const existing = (await ref.get()).data();
  if (existing && Date.now() - existing.sentAt.toMillis() < RESEND_AFTER_MS) {
    throw new HttpsError('resource-exhausted', 'Please wait a minute before asking for another code.');
  }

  const client = await findClient(email);
  const user = client?.data() as UserDoc | undefined;
  if (!client || user?.status !== 'active') {
    // Record the attempt for rate limiting, but send nothing.
    await ref.set({ sentAt: Timestamp.now(), codeHash: null, attempts: 0, expiresAt: Timestamp.now() });
    return { sent: true };
  }

  const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
  await ref.set({
    uid: client.id,
    codeHash: hashCode(email, code),
    attempts: 0,
    sentAt: Timestamp.now(),
    expiresAt: Timestamp.fromMillis(Date.now() + CODE_TTL_MS),
  });

  if (isEmulator) {
    // No email provider in the emulator. Read the code from the logs.
    logger.info(`Sign-in code for ${email}: ${code}`);
  } else {
    // TODO: send through the chosen email provider (Resend, SendGrid, …).
    logger.error('No email provider configured; sign-in code not sent.');
    throw new HttpsError('unavailable', 'We couldn’t send the code. Please try again later.');
  }
  return { sent: true };
});

/** Checks the code and returns a custom token the app signs in with. */
export const verifyEmailCode = onCall({ region: REGION }, async (request) => {
  const email = normaliseEmail(request.data?.email);
  const code = text(request.data?.code, 'Code', 6, 6);
  const ref = db.doc(`emailCodes/${emailKey(email)}`);
  const invalid = new HttpsError('invalid-argument', 'That code is wrong or has expired.');

  const uid = await db.runTransaction(async (tx) => {
    const entry = (await tx.get(ref)).data();
    if (!entry?.codeHash || entry.expiresAt.toMillis() < Date.now()) throw invalid;
    if (entry.attempts >= MAX_ATTEMPTS) {
      throw new HttpsError('resource-exhausted', 'Too many tries. Ask for a new code.');
    }
    if (entry.codeHash !== hashCode(email, code)) {
      tx.update(ref, { attempts: entry.attempts + 1 });
      return null;
    }
    tx.delete(ref);
    return entry.uid as string;
  });
  if (!uid) throw invalid;

  const user = (await db.doc(`users/${uid}`).get()).data() as UserDoc | undefined;
  if (!user || user.status !== 'active') throw invalid;
  await requireActiveCompany(user.companyId);

  await db.doc(`users/${uid}`).update({ lastLoginAt: serverTime() });
  return { token: await auth.createCustomToken(uid, { role: user.role }) };
});

/**
 * Admin only: creates the Firebase Auth account and the `users` document
 * together. Staff and supervisors get a link to set their password.
 */
export const createUser = onCall({ region: REGION }, async (request) => {
  const { uid: adminId } = await requireUser(request, ['admin']);
  const data = request.data ?? {};
  const role = data.role as Role;
  if (!['admin', 'supervisor', 'staff', 'client'].includes(role)) {
    throw new HttpsError('invalid-argument', 'Choose a role.');
  }
  const email = normaliseEmail(data.email);
  const name = text(data.name, 'Name', 1, 100);

  let locationName: string | null = null;
  if (data.locationId) {
    const location = (await db.doc(`locations/${data.locationId}`).get()).data();
    if (!location) throw new HttpsError('not-found', 'That location doesn’t exist.');
    locationName = location.name;
  }
  let companyName: string | null = null;
  if (role === 'client') {
    const company = (await db.doc(`companies/${data.companyId}`).get()).data();
    if (!company) throw new HttpsError('not-found', 'That company doesn’t exist.');
    companyName = company.name;
  }

  const account = await auth.createUser({ email, displayName: name }).catch((error) => {
    if (error.code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'Someone already uses that email.');
    }
    throw error;
  });

  const now = serverTime();
  await db.doc(`users/${account.uid}`).set({
    role,
    status: 'active',
    name,
    email,
    phone: data.phone ?? null,
    designation: data.designation ?? null,
    locationId: data.locationId ?? null,
    locationName,
    companyId: role === 'client' ? data.companyId : null,
    companyName,
    onShift: false,
    lastLoginAt: null,
    createdAt: now,
    createdBy: adminId,
    updatedAt: now,
    updatedBy: adminId,
  });

  if (role !== 'client') {
    const link = await auth.generatePasswordResetLink(email);
    if (isEmulator) logger.info(`Password setup link for ${email}: ${link}`);
    // TODO: email the link through the chosen email provider.
  }
  return { uid: account.uid };
});
