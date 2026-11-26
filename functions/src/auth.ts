import { createHash, randomBytes, randomInt } from 'node:crypto';
import { Timestamp } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { adminDb, logSteps, syncAdminRecord } from './bridge/sync';
import { syncClaims } from './claims';
import { sendMail } from './mail';
import {
  auth,
  db,
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
/** How long a new client has to fill in the sign-up form after their code. */
const TICKET_TTL_MS = 30 * 60 * 1000;

const normaliseEmail = (value: unknown) => text(value, 'Email', 3, 254).toLowerCase();
const optionalText = (value: unknown, field: string, max: number) =>
  value == null || (typeof value === 'string' && !value.trim()) ? null : text(value, field, 1, max);
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
 * Emails a 6-digit code to a client, or to someone signing up as one.
 * Always answers the same way, so the form can't be used to find out which
 * emails have accounts.
 */
export const sendEmailCode = onCall({ region: REGION }, async (request) => {
  const email = normaliseEmail(request.data?.email);
  const ref = db.doc(`emailCodes/${emailKey(email)}`);
  const existing = (await ref.get()).data();
  if (existing && Date.now() - existing.sentAt.toMillis() < RESEND_AFTER_MS) {
    throw new HttpsError('resource-exhausted', 'Please wait a minute before asking for another code.');
  }

  // Clients sign themselves up, so a new email gets a code too. A client
  // account that was switched off gets nothing.
  const client = await findClient(email);
  const user = client?.data() as UserDoc | undefined;
  if (client && user?.status !== 'active') {
    // Record the attempt for rate limiting, but send nothing.
    await ref.set({ sentAt: Timestamp.now(), codeHash: null, attempts: 0, expiresAt: Timestamp.now() });
    return { sent: true };
  }

  // App Review: reviewers can't read the inbox, so one review email signs in
  // with a fixed code. Its hash lives in settings/appReview, which only the
  // server can read (set with tool/set_review_code.cjs); nothing is emailed.
  const review = (await db.doc('settings/appReview').get()).data();
  if (review?.email === email && typeof review.codeHash === 'string') {
    await ref.set({
      uid: client?.id ?? null,
      codeHash: review.codeHash,
      attempts: 0,
      sentAt: Timestamp.now(),
      expiresAt: Timestamp.fromMillis(Date.now() + CODE_TTL_MS),
    });
    logger.info('app review sign-in code set');
    return { sent: true };
  }

  const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
  await ref.set({
    uid: client?.id ?? null,
    codeHash: hashCode(email, code),
    attempts: 0,
    sentAt: Timestamp.now(),
    expiresAt: Timestamp.fromMillis(Date.now() + CODE_TTL_MS),
  });

  try {
    await sendMail(
      email,
      'Your TSL Facility Manager verification code',
      'Your TSL Facility Manager verification code\n\n' +
        'Enter this code in the app to continue:\n\n' +
        code +
        '\n\nThe code expires in 10 minutes. If you didn’t ask for it, you can ' +
        'ignore this email.',
    );
  } catch (error) {
    logger.error('verification code email failed', error);
    // Allow an immediate retry, since nothing was delivered.
    await ref.delete();
    throw new HttpsError('unavailable', 'We couldn’t send the code. Please try again.');
  }
  logger.info(client ? 'sign-in code sent' : 'sign-up code sent');
  return { sent: true };
});

/**
 * Checks the code. A client gets a custom token to sign in with; a new email
 * gets a short-lived sign-up ticket for [createClientAccount] instead.
 */
export const verifyEmailCode = onCall({ region: REGION }, async (request) => {
  const email = normaliseEmail(request.data?.email);
  const code = text(request.data?.code, 'Code', 6, 6);
  const ref = db.doc(`emailCodes/${emailKey(email)}`);
  const invalid = new HttpsError('invalid-argument', 'That code is wrong or has expired.');

  const outcome = await db.runTransaction(async (tx) => {
    const entry = (await tx.get(ref)).data();
    if (!entry?.codeHash || entry.expiresAt.toMillis() < Date.now()) throw invalid;
    if (entry.attempts >= MAX_ATTEMPTS) {
      throw new HttpsError('resource-exhausted', 'Too many tries. Ask for a new code.');
    }
    if (entry.codeHash !== hashCode(email, code)) {
      tx.update(ref, { attempts: entry.attempts + 1 });
      return null;
    }
    if (entry.uid) {
      tx.delete(ref);
      return { uid: entry.uid as string };
    }
    // A new email: the code is used up, and the ticket proves the email for
    // the sign-up form.
    const ticket = randomBytes(24).toString('hex');
    tx.set(ref, {
      uid: null,
      codeHash: null,
      ticketHash: hashCode(email, ticket),
      attempts: 0,
      sentAt: entry.sentAt,
      expiresAt: Timestamp.fromMillis(Date.now() + TICKET_TTL_MS),
    });
    return { ticket };
  });
  if (!outcome) throw invalid;
  if ('ticket' in outcome) return { signupTicket: outcome.ticket };
  return { token: await clientToken(outcome.uid, invalid) };
});

/** Signs a client in: checks their account and company, then mints a token. */
async function clientToken(uid: string, invalid: HttpsError): Promise<string> {
  const user = (await db.doc(`users/${uid}`).get()).data() as UserDoc | undefined;
  if (!user || user.status !== 'active') throw invalid;
  await requireActiveCompany(user.companyId);

  await db.doc(`users/${uid}`).update({ lastLoginAt: serverTime() });
  // Storage rules read these claims; set them before the first sign-in.
  await syncClaims(uid, user);
  return auth.createCustomToken(uid);
}

/**
 * A new client signs up, after proving their email with a code. Their
 * record goes into the dashboard's `client` collection, which holds client
 * records apart from staff; the bridge copies it into the app as a company
 * and a client user, done here straight away so they can sign in now.
 */
export const createClientAccount = onCall({ region: REGION }, async (request) => {
  const data = request.data ?? {};
  const email = normaliseEmail(data.email);
  const ticket = text(data.ticket, 'Ticket', 10, 100);
  const name = text(data.name, 'Name', 1, 100);
  const companyName = optionalText(data.company, 'Company', 200);
  const phoneNumber = optionalText(data.phone, 'Phone', 20);
  const ref = db.doc(`emailCodes/${emailKey(email)}`);
  const expired = new HttpsError('invalid-argument', 'Your sign-up has expired. Ask for a new code.');

  await db.runTransaction(async (tx) => {
    const entry = (await tx.get(ref)).data();
    if (!entry?.ticketHash || entry.expiresAt.toMillis() < Date.now()) throw expired;
    if (entry.ticketHash !== hashCode(email, ticket)) throw expired;
    tx.delete(ref);
  });

  if (await findClient(email)) {
    throw new HttpsError('already-exists', 'You already have an account. Sign in with a new code.');
  }
  if (await auth.getUserByEmail(email).catch(() => null)) {
    throw new HttpsError(
      'already-exists',
      'This email belongs to a staff account. Use “Staff or supervisor? Sign in”.',
    );
  }

  const id = `client_${randomBytes(7).toString('hex')}`;
  const record = {
    clientID: id,
    clientName: companyName ?? name,
    contactName: name,
    clientEmail: email,
    clientPhone: phoneNumber,
    clientOTP: null,
    createdAt: Timestamp.now(),
    createdBy: 'app',
  };
  await adminDb.doc(`client/${id}`).set(record);
  const steps = await syncAdminRecord('client', id, undefined, record, { apply: true });
  logSteps('client', id, steps);
  if (steps.some((s) => s.action === 'skip')) {
    throw new HttpsError('internal', 'We couldn’t finish setting up your account. Please try again.');
  }
  logger.info(`client ${id} signed up`);
  return { token: await clientToken(id, expired) };
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
    await sendMail(
      email,
      'Set up your TSL Facility Manager password',
      'Welcome to TSL Facility Manager\n\n' +
        'Tap the link below to choose your password, then sign in with ' +
        `${email}:\n\n${link}`,
    ).catch((error) => logger.error('password setup email failed', error));
  }
  return { uid: account.uid };
});

/**
 * A client deletes their own account, as the app stores require for
 * accounts made in the app. Their sign-in, personal details, notifications,
 * devices and support chat go, as does their record in the dashboard's
 * `client` collection. Requests they reported stay with the facility team
 * as business records. Staff and supervisor accounts are managed in the
 * dashboard.
 */
export const deleteMyAccount = onCall({ region: REGION }, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'Please sign in again.');
  const ref = db.doc(`users/${uid}`);
  const user = (await ref.get()).data() as UserDoc | undefined;
  if (!user || user.status === 'deleted') {
    throw new HttpsError('not-found', 'This account has already been deleted.');
  }
  if (user.role !== 'client') {
    throw new HttpsError(
      'permission-denied',
      'Staff and supervisor accounts are managed by your administrator.',
    );
  }

  // The record is anonymised first, so the bridge's reaction to the
  // dashboard record going away finds nothing personal left to copy.
  await ref.set(
    {
      status: 'deleted',
      name: 'Deleted client',
      email: null,
      phone: null,
      locationId: null,
      locationName: null,
      onShift: false,
      deletedAt: serverTime(),
      updatedAt: serverTime(),
      updatedBy: uid,
    },
    { merge: true },
  );
  await Promise.all([
    db.recursiveDelete(ref.collection('notifications')),
    db.recursiveDelete(ref.collection('fcmTokens')),
    db.recursiveDelete(db.doc(`supportThreads/${uid}`)),
    user.email ? db.doc(`emailCodes/${emailKey(user.email)}`).delete() : Promise.resolve(),
  ]);
  // Their own dashboard record (clients who signed up in the app).
  const adminRecord = adminDb.doc(`client/${uid}`);
  if ((await adminRecord.get()).exists) await adminRecord.delete();
  await auth.deleteUser(uid).catch((error) => {
    if (error.code !== 'auth/user-not-found') throw error;
  });
  logger.info(`client ${uid} deleted their account`);
  return { deleted: true };
});
