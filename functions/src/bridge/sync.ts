/**
 * Applies one change from the admin database to the app's database. Used by
 * the bridge triggers and by tool/bridge_backfill.cjs.
 */
import { FieldValue, Firestore, getFirestore } from 'firebase-admin/firestore';
import { logger } from 'firebase-functions';
import { syncClaims } from '../claims';
import { auth, db } from '../common';
import {
  AdminDoc,
  changedFields,
  Converted,
  convertAsset,
  convertClientUser,
  convertCompany,
  convertDocument,
  convertInventory,
  convertLocation,
  convertSla,
  convertStaff,
  convertZone,
  Lookup,
} from './convert';

/** The admin dashboard's database. */
export const adminDb: Firestore = getFirestore();

/**
 * Whether the app's scheduler creates work orders from the dashboard's SLA
 * schedules. Off until it's agreed that the dashboard stops creating them
 * (docs/admin-db-integration-plan.md, question 3), so jobs aren't doubled.
 */
export const APP_CREATES_SLA_JOBS = false;

/** Admin collections the bridge copies into the app. */
export const BRIDGED = ['staff', 'client', 'location', 'zone', 'assets', 'documents', 'inventory', 'sla_schedules'] as const;
export type Bridged = (typeof BRIDGED)[number];

/** What a sync did or, in a dry run, would do. */
export interface Step {
  action: 'create' | 'update' | 'unchanged' | 'deactivate' | 'delete' | 'skip' | 'auth';
  target: string;
  detail?: string;
}

export interface SyncOptions {
  /** False for a dry run: nothing is written. */
  apply: boolean;
  /** Copy the bcrypt password into Firebase Auth even if it didn't change. */
  forcePassword?: boolean;
}

async function lookups(collection: Bridged, d: AdminDoc): Promise<Lookup> {
  const cache = new Map<string, AdminDoc | undefined>();
  const fetch = async (path: string | null) => {
    if (!path || cache.has(path)) return;
    cache.set(path, (await adminDb.doc(path).get()).data());
  };
  const id = (v: unknown) => (typeof v === 'string' && v ? v : null);
  if (collection === 'staff') await fetch(id(d.assignedFacility) && `location/${d.assignedFacility}`);
  if (collection === 'location') await fetch(id(d.siteManager) && `staff/${d.siteManager}`);
  if (collection === 'assets') await fetch(id(d.zoneId) && `zone/${d.zoneId}`);
  const get = (prefix: string) => (key: string | null) => (key ? cache.get(`${prefix}/${key}`) : undefined);
  return { location: get('location'), staff: get('staff'), zone: get('zone'), client: get('client') };
}

/**
 * Writes a converted record: only differing fields, creation fields once.
 * [extra] is added whenever something is written.
 */
export async function write(
  target: Firestore,
  c: Converted,
  opts: SyncOptions,
  by = 'admin-sync',
  extra: (changed: Record<string, unknown>) => Record<string, unknown> = () => ({}),
): Promise<Step> {
  const ref = target.doc(`${c.collection}/${c.id}`);
  const current = (await ref.get()).data();
  const changed = changedFields(c.fields, current);
  const path = `${c.collection}/${c.id}`;
  if (current && Object.keys(changed).length === 0) return { action: 'unchanged', target: path };
  if (opts.apply) {
    await ref.set(
      {
        ...(current ? {} : c.onCreate),
        ...changed,
        ...extra(changed),
        updatedAt: FieldValue.serverTimestamp(),
        updatedBy: by,
      },
      { merge: true },
    );
  }
  return { action: current ? 'update' : 'create', target: path, detail: Object.keys(changed).join(', ') };
}

/**
 * Fills in a copied name on app records that point at [id], for records
 * copied before the one they point at.
 */
async function fillNames(collection: string, idField: string, id: string, nameField: string, name: unknown, opts: SyncOptions): Promise<Step[]> {
  const snap = await db.collection(collection).where(idField, '==', id).get();
  const stale = snap.docs.filter((d) => d.data()[nameField] !== name);
  if (opts.apply) await Promise.all(stale.map((d) => d.ref.update({ [nameField]: name ?? null })));
  return stale.map((d) => ({ action: 'update' as const, target: `${collection}/${d.id}`, detail: nameField }));
}

/** Marks the app's copy inactive, or deletes it when it has no status. */
async function retire(collection: string, id: string, opts: SyncOptions, status = 'inactive'): Promise<Step> {
  const ref = db.doc(`${collection}/${id}`);
  const current = (await ref.get()).data();
  const path = `${collection}/${id}`;
  if (!current) return { action: 'skip', target: path, detail: 'not in the app' };
  if (collection === 'documents') {
    if (opts.apply) await ref.delete();
    return { action: 'delete', target: path };
  }
  if (current.status === status) return { action: 'unchanged', target: path };
  if (opts.apply) await ref.update({ status, updatedAt: FieldValue.serverTimestamp(), updatedBy: 'admin-sync' });
  return { action: 'deactivate', target: path };
}

const BCRYPT = /^\$2[abxy]\$\d\d\$[./A-Za-z0-9]{53}$/;

/**
 * Keeps the Firebase sign-in account for [uid] in step. A dashboard bcrypt
 * hash is copied so the same password works in the app. Firebase reads
 * PHP's "$2y$" hashes as the identical "$2a$".
 */
async function ensureAccount(
  uid: string,
  fields: Record<string, unknown>,
  hash: string | null,
  copyHash: boolean,
  opts: SyncOptions,
): Promise<Step[]> {
  const email = fields.email as string;
  const displayName = fields.name as string;
  const disabled = fields.status !== 'active';
  const steps: Step[] = [];
  const existing = await auth.getUser(uid).catch((e) => {
    if (e.code === 'auth/user-not-found') return null;
    throw e;
  });
  if (!existing) {
    const owner = await auth.getUserByEmail(email).catch(() => null);
    if (owner) {
      return [{ action: 'skip', target: `auth/${uid}`, detail: `email already used by another account (${owner.uid})` }];
    }
  }
  const useHash = hash && BCRYPT.test(hash) && (copyHash || !existing);
  if (useHash) {
    if (opts.apply) {
      const record = { uid, email, displayName, disabled, passwordHash: Buffer.from(hash!.replace(/^\$2[bxy]\$/, '$2a$')) };
      const importOne = () => auth.importUsers([record], { hash: { algorithm: 'BCRYPT' } });
      let result = await importOne();
      if (result.failureCount && existing && /existing account/i.test(result.errors[0].error.message)) {
        // Where an import can't replace an account, replace it by hand: same
        // ID, so nothing in the app changes; the person signs in again.
        await auth.deleteUser(uid);
        result = await importOne();
      }
      if (result.failureCount) throw result.errors[0].error;
      // Importing replaces the account, including its claims.
      await syncClaims(uid);
    }
    steps.push({ action: 'auth', target: `auth/${uid}`, detail: existing ? 'password updated' : 'created with dashboard password' });
  } else if (!existing) {
    if (opts.apply) await auth.createUser({ uid, email, displayName, disabled });
    steps.push({ action: 'auth', target: `auth/${uid}`, detail: hash ? 'created; password is not bcrypt, so a reset is needed' : 'created without a password' });
  } else if (existing.email !== email || existing.displayName !== displayName || existing.disabled !== disabled) {
    if (opts.apply) await auth.updateUser(uid, { email, displayName, disabled });
    steps.push({ action: 'auth', target: `auth/${uid}`, detail: 'details updated' });
  }
  return steps;
}

/**
 * Syncs one admin record. [before] is its previous version (undefined when it
 * was just created, or in a backfill); [after] is undefined when it was deleted.
 */
export async function syncAdminRecord(
  collection: Bridged,
  id: string,
  before: AdminDoc | undefined,
  after: AdminDoc | undefined,
  opts: SyncOptions,
): Promise<Step[]> {
  if (!after) {
    switch (collection) {
      case 'staff': {
        const steps = [await retire('users', id, opts)];
        if (opts.apply) await auth.updateUser(id, { disabled: true }).catch(() => undefined);
        return steps;
      }
      case 'client':
        return [await retire('companies', id, opts, 'disabled'), await retire('users', id, opts)];
      case 'location': return [await retire('locations', id, opts)];
      case 'zone': return [await retire('zones', id, opts)];
      case 'assets': return [await retire('assets', id, opts)];
      case 'documents': return [await retire('documents', id, opts)];
      case 'inventory': return [await retire('inventory', id, opts)];
      case 'sla_schedules': return [await retire('slaSchedules', id, opts)];
    }
  }

  const look = await lookups(collection, after);
  const skip = (why: string): Step[] => [{ action: 'skip', target: `${collection}/${id}`, detail: why }];
  switch (collection) {
    case 'staff': {
      const c = convertStaff(id, after, look);
      if (!c) return skip('no email, or a role the app doesn’t use');
      const hash = typeof after.password === 'string' ? after.password : null;
      const copyHash = !!opts.forcePassword || before?.password !== after.password;
      const steps = await ensureAccount(id, c.fields, hash, copyHash, opts);
      if (steps.some((s) => s.action === 'skip')) return steps;
      return [
        ...steps,
        await write(db, c, opts),
        ...(await fillNames('locations', 'siteManagerId', id, 'siteManagerName', c.fields.name, opts)),
      ];
    }
    case 'client': {
      const company = convertCompany(id, after);
      const user = convertClientUser(id, after);
      const steps = [await write(db, company, opts)];
      if (!user) return [...steps, ...skip('no contact email')];
      const account = await ensureAccount(id, user.fields, null, false, opts);
      if (account.some((s) => s.action === 'skip')) return [...steps, ...account];
      return [...steps, ...account, await write(db, user, opts)];
    }
    case 'location': {
      const c = convertLocation(id, after, look);
      return [await write(db, c, opts), ...(await fillNames('users', 'locationId', id, 'locationName', c.fields.name, opts))];
    }
    case 'zone': {
      const c = convertZone(id, after);
      return c ? [await write(db, c, opts)] : skip('no facility');
    }
    case 'assets': {
      const c = convertAsset(id, after, look);
      return c ? [await write(db, c, opts)] : skip('its zone or facility wasn’t found');
    }
    case 'documents': {
      const c = convertDocument(id, after);
      return c ? [await write(db, c, opts)] : skip('no facility');
    }
    case 'inventory': {
      const c = convertInventory(id, after);
      return c ? [await write(db, c, opts)] : skip('no facility');
    }
    case 'sla_schedules': {
      const c = convertSla(id, after, APP_CREATES_SLA_JOBS);
      return c ? [await write(db, c, opts)] : skip('missing facility, frequency, start date or time');
    }
  }
}

/** Logs what a sync did, for the function logs. */
export function logSteps(collection: string, id: string, steps: Step[]) {
  for (const s of steps) {
    if (s.action === 'unchanged') continue;
    const line = `bridge ${collection}/${id}: ${s.action} ${s.target}${s.detail ? ` (${s.detail})` : ''}`;
    if (s.action === 'skip') logger.warn(line);
    else logger.info(line);
  }
}
