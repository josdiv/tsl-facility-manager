import { GeoPoint } from 'firebase-admin/firestore';
import { HttpsError, onCall } from 'firebase-functions/v2/https';
import { db, distanceMetres, REGION, requireUser, serverTime } from './common';
import { readPosition, requireOnSite } from './geofence';

async function openShift(uid: string) {
  const snap = await db
    .collection('attendance')
    .where('userId', '==', uid)
    .where('status', '==', 'clocked_in')
    .limit(1)
    .get();
  return snap.docs[0];
}

/**
 * Starts a shift. The distance to the facility is worked out here, not on the
 * phone. Answers with the distance either way so the app can show it.
 */
export const clockIn = onCall({ region: REGION }, async (request) => {
  const { uid, user } = await requireUser(request, ['staff', 'supervisor']);
  const position = readPosition(request.data);
  if (!user.locationId) throw new HttpsError('failed-precondition', 'You have no facility assigned.');

  const location = (await db.doc(`locations/${user.locationId}`).get()).data();
  if (!location) throw new HttpsError('not-found', 'Your facility no longer exists.');
  if (!location.geo) {
    throw new HttpsError('failed-precondition', 'location-not-set');
  }
  const geo = location.geo as GeoPoint;
  const distanceM = requireOnSite(geo, location.radiusM, position, request.data?.isMocked);
  if (await openShift(uid)) throw new HttpsError('already-exists', 'You’re already clocked in.');

  const now = serverTime();
  const ref = db.collection('attendance').doc();
  const batch = db.batch();
  batch.set(ref, {
    userId: uid,
    userName: user.name,
    locationId: user.locationId,
    locationName: location.name,
    status: 'clocked_in',
    attendanceStatus: 'present',
    clockInAt: now,
    clockInGeo: new GeoPoint(position.latitude, position.longitude),
    clockInDistanceM: distanceM,
    clockInAccuracyM: Math.round(position.accuracyM),
    clockOutAt: null,
    clockOutGeo: null,
    clockOutDistanceM: null,
    source: 'app',
    createdAt: now,
    createdBy: uid,
    updatedAt: now,
    updatedBy: uid,
  });
  batch.update(db.doc(`users/${uid}`), { onShift: true });
  await batch.commit();
  return { attendanceId: ref.id, distanceM };
});

/** Ends the open shift. The location is recorded but not required. */
export const clockOut = onCall({ region: REGION }, async (request) => {
  const { uid } = await requireUser(request, ['staff', 'supervisor']);
  const shift = await openShift(uid);
  if (!shift) throw new HttpsError('failed-precondition', 'You’re not clocked in.');

  let geo: GeoPoint | null = null;
  let distanceM: number | null = null;
  if (request.data?.latitude != null) {
    const position = readPosition(request.data);
    geo = new GeoPoint(position.latitude, position.longitude);
    const location = (await db.doc(`locations/${shift.data().locationId}`).get()).data();
    if (location) distanceM = Math.round(distanceMetres(location.geo as GeoPoint, position));
  }

  const now = serverTime();
  const batch = db.batch();
  batch.update(shift.ref, {
    status: 'clocked_out',
    clockOutAt: now,
    clockOutGeo: geo,
    clockOutDistanceM: distanceM,
    updatedAt: now,
    updatedBy: uid,
  });
  batch.update(db.doc(`users/${uid}`), { onShift: false });
  await batch.commit();
  return { attendanceId: shift.id };
});
