import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { getBytes, ref, uploadBytes } from 'firebase/storage';
import { createEnv, storageAs } from './helpers.js';

// Storage rules read only the sign-in token's claims (see storage.rules), so
// nothing is seeded in Firestore here.
let env;
before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearStorage(); });

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
const upload = (uid, path, contentType = 'image/jpeg') =>
  uploadBytes(ref(storageAs(env, uid), path), jpeg, { contentType });
const marina = (id, kind, file) => `locations/marina/workOrders/${id}/${kind}/${file}`;

describe('work order photos', () => {
  it('lets a client upload report photos at their company\'s locations', async () => {
    await assertSucceeds(upload('daniel', marina('brand-new', 'report', 'leak.jpg')));
    await assertSucceeds(upload('daniel', 'locations/harbour/workOrders/brand-new/report/leak.jpg'));
    await assertFails(upload('daniel', 'locations/cedar/workOrders/brand-new/report/leak.jpg'));
    await assertFails(upload('daniel', marina('brand-new', 'work', 'leak.jpg')));
    await assertFails(upload('locked', marina('brand-new', 'report', 'leak.jpg')));
  });

  it('lets staff upload proof of work at their own location only', async () => {
    await assertSucceeds(upload('emeka', marina('working', 'work', 'after.jpg')));
    await assertFails(upload('grace', marina('working', 'work', 'after.jpg')));
    await assertFails(upload('emeka', marina('working', 'report', 'after.jpg')));
    await assertFails(upload('emeka', marina('working', 'inspection', 'after.jpg')));
    await assertFails(upload('gone', marina('working', 'work', 'after.jpg')));
  });

  it('lets the location\'s supervisor upload return and inspection photos', async () => {
    await assertSucceeds(upload('sarah', marina('review', 'return', 'issue.jpg')));
    await assertSucceeds(upload('sarah', marina('review', 'inspection', 'closed.jpg')));
    await assertFails(upload('musa', marina('review', 'return', 'issue.jpg')));
    await assertFails(upload('sarah', marina('review', 'work', 'closed.jpg')));
  });

  it('accepts images only, never replaced', async () => {
    await assertFails(upload('emeka', marina('working', 'work', 'report.pdf'), 'application/pdf'));
    await assertSucceeds(upload('emeka', marina('working', 'work', 'once.jpg')));
    await assertFails(upload('emeka', marina('working', 'work', 'once.jpg')));
  });

  it('refuses the old layout and anyone signed out', async () => {
    await assertFails(upload('emeka', 'workOrders/working/work/after.jpg'));
    await assertFails(uploadBytes(ref(env.unauthenticatedContext().storage(), marina('x', 'report', 'a.jpg')), jpeg, { contentType: 'image/jpeg' }));
  });

  it('lets people at the location view its photos', async () => {
    const path = marina('open', 'report', 'leak.jpg');
    await env.withSecurityRulesDisabled((c) => uploadBytes(ref(c.storage(), path), jpeg, { contentType: 'image/jpeg' }));
    for (const uid of ['daniel', 'emeka', 'sarah', 'admin']) await assertSucceeds(getBytes(ref(storageAs(env, uid), path)));
    for (const uid of ['grace', 'musa', 'locked', 'gone']) await assertFails(getBytes(ref(storageAs(env, uid), path)));
  });
});

describe('documents and stock photos', () => {
  it('lets staff and supervisors at the location read documents; admins write them', async () => {
    const path = 'locations/marina/documents/sop/manual.pdf';
    await assertSucceeds(uploadBytes(ref(storageAs(env, 'admin'), path), jpeg, { contentType: 'application/pdf' }));
    await assertFails(uploadBytes(ref(storageAs(env, 'sarah'), 'locations/marina/documents/sop/x.pdf'), jpeg, { contentType: 'application/pdf' }));
    await assertSucceeds(getBytes(ref(storageAs(env, 'emeka'), path)));
    await assertFails(getBytes(ref(storageAs(env, 'grace'), path)));
    await assertFails(getBytes(ref(storageAs(env, 'daniel'), path)));
  });

  it('lets the field team read stock photos', async () => {
    const path = 'inventory/filters/photo.jpg';
    await assertSucceeds(upload('admin', path));
    await assertFails(upload('emeka', 'inventory/filters/other.jpg'));
    await assertSucceeds(getBytes(ref(storageAs(env, 'grace'), path)));
    await assertFails(getBytes(ref(storageAs(env, 'daniel'), path)));
  });
});
