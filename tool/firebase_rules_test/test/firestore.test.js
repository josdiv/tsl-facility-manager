import { after, before, beforeEach, describe, it } from 'node:test';
import { assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import {
  addDoc, collection, deleteDoc, doc, getDoc, getDocs, query, serverTimestamp,
  setDoc, Timestamp, updateDoc, where,
} from 'firebase/firestore';
import { as, createEnv, seed } from './helpers.js';

let env;
before(async () => { env = await createEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await seed(env); });

const stamp = (uid) => ({ updatedAt: serverTimestamp(), updatedBy: uid });

describe('signing in', () => {
  it('blocks anyone who is not signed in', async () => {
    const db = env.unauthenticatedContext().firestore();
    await assertFails(getDoc(doc(db, 'workOrders/open')));
    await assertFails(getDoc(doc(db, 'locations/marina')));
  });

  it('blocks users who are not active', async () => {
    await assertFails(getDoc(doc(as(env, 'gone'), 'users/gone')));
  });

  it('blocks clients whose company is locked', async () => {
    await assertFails(getDoc(doc(as(env, 'locked'), 'users/locked')));
  });

  it('keeps counters private, even from admins', async () => {
    await assertFails(getDoc(doc(as(env, 'admin'), 'counters/workOrders')));
    await assertFails(getDoc(doc(as(env, 'admin'), 'emailCodes/anything')));
  });
});

describe('reading work orders', () => {
  it('lets a client read only their own requests', async () => {
    const db = as(env, 'daniel');
    await assertSucceeds(getDoc(doc(db, 'workOrders/open')));
    await assertFails(getDoc(doc(db, 'workOrders/other-client')));
    await assertSucceeds(getDocs(query(collection(db, 'workOrders'), where('clientId', '==', 'daniel'))));
    await assertFails(getDocs(collection(db, 'workOrders')));
  });

  it('lets staff read only work assigned to them', async () => {
    await assertSucceeds(getDoc(doc(as(env, 'emeka'), 'workOrders/open')));
    await assertFails(getDoc(doc(as(env, 'tunde'), 'workOrders/open')));
    await assertSucceeds(getDocs(query(collection(as(env, 'emeka'), 'workOrders'), where('assignedToId', '==', 'emeka'))));
  });

  it('lets a supervisor read their whole location and nothing else', async () => {
    const db = as(env, 'sarah');
    await assertSucceeds(getDocs(query(collection(db, 'workOrders'), where('locationId', '==', 'marina'))));
    await assertFails(getDoc(doc(db, 'workOrders/cedar')));
    await assertFails(getDocs(query(collection(db, 'workOrders'), where('locationId', '==', 'cedar'))));
  });

  it('lets admins read everything', async () => {
    await assertSucceeds(getDocs(collection(as(env, 'admin'), 'workOrders')));
  });
});

describe('work order lifecycle', () => {
  it('does not let anyone create work orders directly', async () => {
    for (const uid of ['daniel', 'emeka', 'sarah', 'admin']) {
      await assertFails(setDoc(doc(as(env, uid), 'workOrders/new'), { title: 'x', status: 'open' }));
    }
  });

  it('lets the assignee start an open task', async () => {
    await assertSucceeds(updateDoc(doc(as(env, 'emeka'), 'workOrders/open'), {
      status: 'in_progress', startedAt: serverTimestamp(), ...stamp('emeka'),
    }));
  });

  it('refuses a start from someone else, with a made-up time, or with extra changes', async () => {
    const change = { status: 'in_progress', startedAt: serverTimestamp(), ...stamp('tunde') };
    await assertFails(updateDoc(doc(as(env, 'tunde'), 'workOrders/open'), change));
    await assertFails(updateDoc(doc(as(env, 'emeka'), 'workOrders/open'), {
      status: 'in_progress', startedAt: Timestamp.now(), ...stamp('emeka'),
    }));
    await assertFails(updateDoc(doc(as(env, 'emeka'), 'workOrders/open'), {
      status: 'in_progress', startedAt: serverTimestamp(), priority: 'low', ...stamp('emeka'),
    }));
    await assertFails(updateDoc(doc(as(env, 'emeka'), 'workOrders/open'), {
      status: 'in_progress', startedAt: serverTimestamp(), updatedAt: serverTimestamp(), updatedBy: 'sarah',
    }));
  });

  it('lets the assignee submit work with photos from the right folder', async () => {
    await assertSucceeds(updateDoc(doc(as(env, 'emeka'), 'workOrders/working'), {
      status: 'pending_review',
      workNote: 'Recharged refrigerant, unit cooling.',
      workPhotos: ['workOrders/working/work/after-1.jpg', 'workOrders/working/work/after-2.jpg'],
      submittedAt: serverTimestamp(),
      ...stamp('emeka'),
    }));
  });

  it('refuses a submission with bad photos, no note, or from the wrong status', async () => {
    const submit = (id, extra) => updateDoc(doc(as(env, 'emeka'), `workOrders/${id}`), {
      status: 'pending_review', workNote: 'Done', workPhotos: [], submittedAt: serverTimestamp(),
      ...stamp('emeka'), ...extra,
    });
    await assertFails(submit('working', { workPhotos: ['workOrders/open/work/stolen.jpg'] }));
    await assertFails(submit('working', { workPhotos: Array.from({ length: 7 }, (_, i) => `workOrders/working/work/${i}.jpg`) }));
    await assertFails(submit('working', { workNote: '' }));
    await assertFails(submit('open', {}));
    await assertFails(submit('review', {}));
  });

  it('does not let staff sign off their own work', async () => {
    await assertFails(updateDoc(doc(as(env, 'emeka'), 'workOrders/review'), {
      status: 'completed', inspectionChecks: [], completedAt: serverTimestamp(), ...stamp('emeka'),
    }));
  });

  it('lets a supervisor at the location confirm work', async () => {
    await assertSucceeds(updateDoc(doc(as(env, 'sarah'), 'workOrders/review'), {
      status: 'completed',
      inspectionChecks: ['Unit operating correctly', 'Area clean and safe'],
      inspectionNote: 'All good.',
      completedAt: serverTimestamp(),
      ...stamp('sarah'),
    }));
    await assertFails(updateDoc(doc(as(env, 'musa'), 'workOrders/review'), {
      status: 'completed', inspectionChecks: [], completedAt: serverTimestamp(), ...stamp('musa'),
    }));
  });

  it('lets a supervisor return work and hand it to someone at the same location', async () => {
    const ret = (extra) => updateDoc(doc(as(env, 'sarah'), 'workOrders/review'), {
      status: 'returned',
      returnReason: 'incomplete_finishing',
      returnFeedback: 'Panel cover not refitted.',
      returnPhotos: ['workOrders/review/return/cover.jpg'],
      returnedAt: serverTimestamp(),
      ...stamp('sarah'),
      ...extra,
    });
    await assertFails(ret({ assignedToId: 'grace', assignedToName: 'Grace Eze' }));
    await assertFails(ret({ assignedToId: 'tunde', assignedToName: 'Someone Else' }));
    await assertFails(ret({ assignedToId: 'gone', assignedToName: 'Former Staff' }));
    await assertFails(ret({ returnReason: 'just_because' }));
    await assertSucceeds(ret({ assignedToId: 'tunde', assignedToName: 'Tunde Bakare' }));
  });

  it('lets the assignee resubmit returned work', async () => {
    await env.withSecurityRulesDisabled((c) => updateDoc(doc(c.firestore(), 'workOrders/working'), { status: 'returned' }));
    await assertSucceeds(updateDoc(doc(as(env, 'emeka'), 'workOrders/working'), {
      status: 'pending_review', workNote: 'Fixed the cover.', workPhotos: [], submittedAt: serverTimestamp(), ...stamp('emeka'),
    }));
  });

  it('allows reassigning active work but not completed work', async () => {
    const reassign = (id) => updateDoc(doc(as(env, 'sarah'), `workOrders/${id}`), {
      assignedToId: 'tunde', assignedToName: 'Tunde Bakare', ...stamp('sarah'),
    });
    await assertSucceeds(reassign('open'));
    await assertFails(reassign('done'));
  });

  it('does not let clients change their requests', async () => {
    await assertFails(updateDoc(doc(as(env, 'daniel'), 'workOrders/open'), { title: 'Changed', ...stamp('daniel') }));
  });

  it('lets admins change anything except the reference', async () => {
    await assertSucceeds(updateDoc(doc(as(env, 'admin'), 'workOrders/open'), { status: 'cancelled', ...stamp('admin') }));
    await assertFails(updateDoc(doc(as(env, 'admin'), 'workOrders/done'), { ref: 'WO-9999', ...stamp('admin') }));
  });

  it('keeps the timeline server-only', async () => {
    await assertSucceeds(getDocs(collection(as(env, 'daniel'), 'workOrders/open/events')));
    await assertFails(addDoc(collection(as(env, 'admin'), 'workOrders/open/events'), { kind: 'started' }));
  });
});

describe('messages', () => {
  const message = (uid, name, role, extra = {}) => ({
    text: 'Hello', senderId: uid, senderName: name, senderRole: role, sentAt: serverTimestamp(), ...extra,
  });

  it('lets people on the work order chat', async () => {
    await assertSucceeds(addDoc(collection(as(env, 'daniel'), 'workOrders/open/messages'), message('daniel', 'Daniel Clarke', 'client')));
    await assertSucceeds(addDoc(collection(as(env, 'emeka'), 'workOrders/open/messages'), message('emeka', 'Emeka Okafor', 'staff')));
    await assertSucceeds(getDocs(collection(as(env, 'sarah'), 'workOrders/open/messages')));
  });

  it('blocks outsiders and fake senders', async () => {
    await assertFails(addDoc(collection(as(env, 'ngozi'), 'workOrders/open/messages'), message('ngozi', 'Ngozi Obi', 'client')));
    await assertFails(addDoc(collection(as(env, 'daniel'), 'workOrders/open/messages'), message('emeka', 'Emeka Okafor', 'staff')));
    await assertFails(addDoc(collection(as(env, 'daniel'), 'workOrders/open/messages'), message('daniel', 'Daniel Clarke', 'admin')));
    await assertFails(addDoc(collection(as(env, 'daniel'), 'workOrders/open/messages'), message('daniel', 'Daniel Clarke', 'client', { text: '' })));
  });

  it('keeps support threads between the user and admins', async () => {
    await assertSucceeds(addDoc(collection(as(env, 'emeka'), 'supportThreads/emeka/messages'), message('emeka', 'Emeka Okafor', 'staff')));
    await assertFails(addDoc(collection(as(env, 'tunde'), 'supportThreads/emeka/messages'), message('tunde', 'Tunde Bakare', 'staff')));
    await assertFails(getDocs(collection(as(env, 'tunde'), 'supportThreads/emeka/messages')));
    await assertSucceeds(getDocs(collection(as(env, 'admin'), 'supportThreads/emeka/messages')));
  });
});

describe('users and profiles', () => {
  it('lets people edit their name and phone, not their role or status', async () => {
    const db = as(env, 'emeka');
    await assertSucceeds(updateDoc(doc(db, 'users/emeka'), { name: 'Emeka O.', phone: '+2348060000000', ...stamp('emeka') }));
    await assertFails(updateDoc(doc(db, 'users/emeka'), { role: 'admin', ...stamp('emeka') }));
    await assertFails(updateDoc(doc(db, 'users/emeka'), { status: 'active', locationId: 'cedar', locationName: 'Cedar Court', ...stamp('emeka') }));
    await assertFails(updateDoc(doc(db, 'users/tunde'), { name: 'Hacked', ...stamp('emeka') }));
  });

  it("lets clients pick a facility from their company's list only", async () => {
    const db = as(env, 'daniel');
    await assertSucceeds(updateDoc(doc(db, 'users/daniel'), { locationId: 'harbour', locationName: 'Harbour Point', ...stamp('daniel') }));
    await assertFails(updateDoc(doc(db, 'users/daniel'), { locationId: 'cedar', locationName: 'Cedar Court', ...stamp('daniel') }));
    await assertFails(updateDoc(doc(db, 'users/daniel'), { locationId: 'harbour', locationName: 'Wrong name', ...stamp('daniel') }));
  });

  it('lets supervisors list their own team only', async () => {
    const db = as(env, 'sarah');
    await assertSucceeds(getDocs(query(collection(db, 'users'), where('locationId', '==', 'marina'))));
    await assertFails(getDocs(query(collection(db, 'users'), where('locationId', '==', 'cedar'))));
    await assertFails(getDoc(doc(as(env, 'emeka'), 'users/tunde')));
  });

  it('does not let anyone create accounts directly', async () => {
    await assertFails(setDoc(doc(as(env, 'admin'), 'users/new'), { role: 'admin', status: 'active', name: 'X' }));
  });

  it('lets people mark their notifications read, nothing more', async () => {
    const db = as(env, 'emeka');
    await assertSucceeds(updateDoc(doc(db, 'users/emeka/notifications/n1'), { readAt: serverTimestamp() }));
    await assertFails(updateDoc(doc(db, 'users/emeka/notifications/n1'), { title: 'Changed' }));
    await assertFails(addDoc(collection(db, 'users/emeka/notifications'), { title: 'Fake' }));
    await assertFails(getDoc(doc(as(env, 'tunde'), 'users/emeka/notifications/n1')));
  });
});

describe('reference data', () => {
  it("shows clients only their company's facilities and zones", async () => {
    const db = as(env, 'daniel');
    await assertSucceeds(getDoc(doc(db, 'locations/marina')));
    await assertFails(getDoc(doc(db, 'locations/cedar')));
    await assertSucceeds(getDocs(query(collection(db, 'zones'), where('locationId', '==', 'marina'))));
    await assertFails(getDocs(query(collection(db, 'zones'), where('locationId', '==', 'cedar'))));
    await assertFails(getDocs(collection(db, 'assets')));
  });

  it('only lets admins edit facilities', async () => {
    const change = { name: 'Renamed', ...stamp('sarah') };
    await assertFails(updateDoc(doc(as(env, 'sarah'), 'locations/marina'), change));
    await assertSucceeds(updateDoc(doc(as(env, 'admin'), 'locations/marina'), { ...change, updatedBy: 'admin' }));
  });

  it('keeps inventory stock status in step with the quantity', async () => {
    const db = as(env, 'admin');
    await assertFails(updateDoc(doc(db, 'inventory/filters'), { quantity: 3, ...stamp('admin') }));
    await assertSucceeds(updateDoc(doc(db, 'inventory/filters'), { quantity: 3, stockStatus: 'low', ...stamp('admin') }));
    await assertSucceeds(updateDoc(doc(db, 'inventory/filters'), { quantity: 0, stockStatus: 'out', ...stamp('admin') }));
  });

  it('shows staff only the inventory at their facility', async () => {
    await assertSucceeds(getDoc(doc(as(env, 'emeka'), 'inventory/filters')));
    await assertFails(getDoc(doc(as(env, 'emeka'), 'inventory/cedar-oil')));
  });
});

describe('requisitions', () => {
  const request = (uid, name, extra = {}) => ({
    type: 'out', inventoryId: 'filters', itemName: 'HVAC air filter', locationId: 'marina',
    workOrderId: 'working', workOrderRef: 'WO-1002', quantity: 2, reason: 'Replace clogged filters',
    requestedById: uid, requestedByName: name, requestedAt: serverTimestamp(), status: 'pending',
    createdAt: serverTimestamp(), createdBy: uid, updatedAt: serverTimestamp(), updatedBy: uid, ...extra,
  });

  it('lets staff request parts at their facility', async () => {
    await assertSucceeds(addDoc(collection(as(env, 'emeka'), 'requisitions'), request('emeka', 'Emeka Okafor')));
  });

  it('refuses pre-approved, foreign, or mismatched requests', async () => {
    const db = as(env, 'emeka');
    const add = (extra) => addDoc(collection(db, 'requisitions'), request('emeka', 'Emeka Okafor', extra));
    await assertFails(add({ status: 'approved' }));
    await assertFails(add({ inventoryId: 'cedar-oil', itemName: 'Generator oil', locationId: 'cedar' }));
    await assertFails(add({ itemName: 'Gold bars' }));
    await assertFails(add({ quantity: 0 }));
    await assertFails(add({ workOrderId: 'cedar', workOrderRef: 'WO-1006' }));
    await assertFails(add({ requestedById: 'tunde' }));
    await assertFails(addDoc(collection(as(env, 'daniel'), 'requisitions'), request('daniel', 'Daniel Clarke')));
  });

  it('does not let anyone approve from the app', async () => {
    await env.withSecurityRulesDisabled((c) =>
      setDoc(doc(c.firestore(), 'requisitions/r1'), { ...request('emeka', 'Emeka Okafor'), requestedAt: Timestamp.now(), createdAt: Timestamp.now(), updatedAt: Timestamp.now() }));
    await assertSucceeds(getDoc(doc(as(env, 'emeka'), 'requisitions/r1')));
    await assertSucceeds(getDoc(doc(as(env, 'sarah'), 'requisitions/r1')));
    await assertFails(getDoc(doc(as(env, 'tunde'), 'requisitions/r1')));
    await assertFails(updateDoc(doc(as(env, 'admin'), 'requisitions/r1'), { status: 'approved', ...stamp('admin') }));
    await assertFails(deleteDoc(doc(as(env, 'emeka'), 'requisitions/r1')));
  });
});

describe('attendance', () => {
  it('only lets clock-ins come from the server', async () => {
    await assertFails(addDoc(collection(as(env, 'emeka'), 'attendance'), { userId: 'emeka', status: 'clocked_in' }));
    await assertSucceeds(getDoc(doc(as(env, 'emeka'), 'attendance/a1')));
    await assertSucceeds(getDoc(doc(as(env, 'sarah'), 'attendance/a1')));
    await assertFails(getDoc(doc(as(env, 'tunde'), 'attendance/a1')));
  });

  it('lets admins correct the attendance status only', async () => {
    await assertSucceeds(updateDoc(doc(as(env, 'admin'), 'attendance/a1'), { attendanceStatus: 'absent', ...stamp('admin') }));
    await assertFails(updateDoc(doc(as(env, 'admin'), 'attendance/a1'), { clockInAt: Timestamp.now(), ...stamp('admin') }));
  });
});
