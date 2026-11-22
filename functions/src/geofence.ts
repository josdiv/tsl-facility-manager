import { HttpsError } from 'firebase-functions/v2/https';
import { distanceMetres } from './common';

/** GPS readings less precise than this can't confirm someone is on site. */
export const MAX_ACCURACY_M = 50;

export interface Position {
  latitude: number;
  longitude: number;
  accuracyM: number;
}

/** The phone's reading sent with a call. Throws if it's missing or malformed. */
export function readPosition(data: unknown): Position {
  const { latitude, longitude, accuracyM } = (data ?? {}) as Record<string, unknown>;
  const ok = (v: unknown, min: number, max: number): v is number =>
    typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;
  if (!ok(latitude, -90, 90) || !ok(longitude, -180, 180) || !ok(accuracyM, 0, 100000)) {
    throw new HttpsError('invalid-argument', 'We couldn’t read your location.');
  }
  return { latitude, longitude, accuracyM };
}

/**
 * Checks that a reading is inside a facility's geofence, for clock-in and for
 * client reports. Returns the distance in metres; throws `failed-precondition`
 * with message `mock-location`, `outside-geofence` or `weak-signal` otherwise.
 */
export function requireOnSite(
  site: { latitude: number; longitude: number },
  radiusM: number,
  position: Position,
  isMocked: unknown,
): number {
  const distanceM = Math.round(distanceMetres(site, position));
  // Android flags readings from fake-GPS apps. The flag is self-reported, so
  // it stops casual cheating rather than a determined one.
  if (isMocked === true) throw new HttpsError('failed-precondition', 'mock-location');
  // A vague reading is still decisive when its whole error margin is outside.
  if (distanceM - position.accuracyM > radiusM) {
    throw new HttpsError('failed-precondition', 'outside-geofence', { distanceM, radiusM });
  }
  if (position.accuracyM > MAX_ACCURACY_M) {
    throw new HttpsError('failed-precondition', 'weak-signal', { distanceM, accuracyM: position.accuracyM });
  }
  if (distanceM > radiusM) {
    throw new HttpsError('failed-precondition', 'outside-geofence', { distanceM, radiusM });
  }
  return distanceM;
}
