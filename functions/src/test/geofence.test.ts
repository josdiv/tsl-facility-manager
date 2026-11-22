import assert from 'node:assert/strict';
import { test } from 'node:test';
import { readPosition, requireOnSite } from '../geofence';

const mono = { latitude: 9.099274882146355, longitude: 7.500952698872983 };
// About 40 m and about 330 km away.
const near = { latitude: 9.09963, longitude: 7.50095 };
const far = { latitude: 6.5244, longitude: 3.3792 };
const reason = (fn: () => unknown) => {
  try { fn(); return 'ok'; } catch (e) { return (e as Error).message; }
};

test('inside the radius with a good fix passes and returns the distance', () => {
  const d = requireOnSite(mono, 100, { ...near, accuracyM: 10 }, false);
  assert.ok(d > 30 && d < 50, `distance ${d}`);
});

test('far away is refused even with a vague fix', () => {
  assert.equal(reason(() => requireOnSite(mono, 100, { ...far, accuracyM: 400 }, false)), 'outside-geofence');
});

test('a vague fix near the site asks for a better signal', () => {
  assert.equal(reason(() => requireOnSite(mono, 100, { ...near, accuracyM: 80 }, false)), 'weak-signal');
});

test('fake GPS is refused', () => {
  assert.equal(reason(() => requireOnSite(mono, 100, { ...near, accuracyM: 5 }, true)), 'mock-location');
});

test('a missing reading is refused', () => {
  assert.equal(reason(() => readPosition(undefined)), 'We couldn’t read your location.');
});
