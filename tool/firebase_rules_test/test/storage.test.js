import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { getBytes, ref, uploadBytes } from 'firebase/storage';
import { createEnv, seed, storageAs } from './helpers.js';

let env;
before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await seed(env);
  await env.clearStorage();
});

const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0]);
const upload = (uid, path, contentType = 'image/jpeg') =>
  uploadBytes(ref(storageAs(env, uid), path), jpeg, { contentType });

describe('work order photos', () => {
  it('lets a client upload report photos for a new request only', async () => {
    await assertSucceeds(upload('daniel', 'workOrders/brand-new/report/leak.jpg'));
    await assertFails(upload('daniel', 'workOrders/open/report/extra.jpg'));
    await assertFails(upload('emeka', 'workOrders/brand-new/report/leak.jpg'));
  });

  it('lets the assignee upload proof while working', async () => {
    await assertSucceeds(upload('emeka', 'workOrders/working/work/after.jpg'));
    await assertFails(upload('emeka', 'workOrders/open/work/after.jpg'));
    await assertFails(upload('emeka', 'workOrders/review/work/after.jpg'));
    await assertFails(upload('tunde', 'workOrders/working/work/after.jpg'));
  });

  it('lets the supervisor upload return evidence during review', async () => {
    await assertSucceeds(upload('sarah', 'workOrders/review/return/issue.jpg'));
    await assertFails(upload('musa', 'workOrders/review/return/issue.jpg'));
  });

  it('lets the supervisor upload inspection photos during review', async () => {
    await assertSucceeds(upload('sarah', 'workOrders/review/inspection/closed.jpg'));
    await assertFails(upload('emeka', 'workOrders/review/inspection/closed.jpg'));
    await assertFails(upload('sarah', 'workOrders/working/inspection/closed.jpg'));
  });

  it('accepts images only', async () => {
    await assertFails(upload('emeka', 'workOrders/working/work/report.pdf', 'application/pdf'));
  });

  it('lets only people on the work order view its photos', async () => {
    await env.withSecurityRulesDisabled((c) =>
      uploadBytes(ref(c.storage(), 'workOrders/open/report/leak.jpg'), jpeg, { contentType: 'image/jpeg' }));
    await assertSucceeds(getBytes(ref(storageAs(env, 'daniel'), 'workOrders/open/report/leak.jpg')));
    await assertSucceeds(getBytes(ref(storageAs(env, 'emeka'), 'workOrders/open/report/leak.jpg')));
    await assertSucceeds(getBytes(ref(storageAs(env, 'sarah'), 'workOrders/open/report/leak.jpg')));
    await assertFails(getBytes(ref(storageAs(env, 'ngozi'), 'workOrders/open/report/leak.jpg')));
    await assertFails(getBytes(ref(storageAs(env, 'tunde'), 'workOrders/open/report/leak.jpg')));
  });
});
