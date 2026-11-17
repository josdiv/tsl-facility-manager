// Live checks of the Cloud Functions against the emulators started by
// tool/emulators.sh. Run from the repo root: node tool/functions_smoke.mjs
// It writes test documents into the emulator only; restart the emulators for
// a clean seed afterwards.
const P = 'tsl-facility-manager';
const FS = `http://127.0.0.1:8080/v1/projects/${P}/databases/tsl-app/documents`;
const owner = { Authorization: 'Bearer owner', 'Content-Type': 'application/json' };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const val = (v) => v == null ? null : Object.values(v)[0];
const get = async (path) => (await (await fetch(`${FS}/${path}`, { headers: owner })).json()).fields ?? {};
const list = async (path) => (await (await fetch(`${FS}/${path}?pageSize=100`, { headers: owner })).json()).documents ?? [];
const restVal = (x) => x === null ? { nullValue: null } : typeof x === 'number' ? (Number.isInteger(x) ? { integerValue: String(x) } : { doubleValue: x })
  : x instanceof Date ? { timestampValue: x.toISOString() } : { stringValue: String(x) };
const put = (path, data) => fetch(`${FS}/${path}`, { method: 'PATCH', headers: owner, body: JSON.stringify({ fields: Object.fromEntries(Object.entries(data).map(([k, v]) => [k, restVal(v)])) }) });
const signIn = async (email) => (await (await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake', {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password: 'test1234', returnSecureToken: true }) })).json()).idToken;
const call = async (name, data, token) => (await fetch(`http://127.0.0.1:5001/${P}/europe-west1/${name}`, {
  method: 'POST', headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` }, body: JSON.stringify({ data }) })).json();
const check = (label, ok, detail = '') => console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}${detail ? '  — ' + detail : ''}`);

// 1. Parts request → REQ number + supervisor alert.
const now = new Date();
await put('requisitions/smoke1', { type: 'out', inventoryId: 'filters', itemName: 'HVAC air filter', locationId: 'marina', workOrderId: 'seed1048', workOrderRef: 'WO-1048',
  quantity: 3, reason: 'Clogged filters', requestedById: 'emeka', requestedByName: 'Emeka Okafor', requestedAt: now, status: 'pending', createdAt: now, createdBy: 'emeka', updatedAt: now, updatedBy: 'emeka' });
await sleep(4000);
const req = await get('requisitions/smoke1');
check('request is numbered', /^REQ-\d+$/.test(val(req.ref) ?? ''), val(req.ref));
const sarahNotes = await list('users/sarah/notifications');
check('supervisor is told about it', sarahNotes.some((n) => val(n.fields.title) === 'Parts requested'));

// 2. Admin approves → stock goes down, technician told. Staff can't approve.
const admin = await signIn('admin@thickservices.com');
const emeka = await signIn('emeka@thickservices.com');
const refused = await call('actionRequisition', { requisitionId: 'smoke1', decision: 'approve' }, emeka);
check('staff can’t approve', refused.error?.status === 'PERMISSION_DENIED', refused.error?.status);
const before = Number(val((await get('inventory/filters')).quantity));
const approved = await call('actionRequisition', { requisitionId: 'smoke1', decision: 'approve' }, admin);
const after = await get('inventory/filters');
check('admin approval takes it off stock', approved.result?.status === 'approved' && Number(val(after.quantity)) === before - 3, `${before} → ${val(after.quantity)}, ${val(after.stockStatus)}`);
const again = await call('actionRequisition', { requisitionId: 'smoke1', decision: 'approve' }, admin);
check('can’t be approved twice', again.error?.status === 'FAILED_PRECONDITION');
await sleep(2000);
check('technician is told', (await list('users/emeka/notifications')).some((n) => val(n.fields.title) === 'Parts approved'));

// 3. Too large a request is refused on approval.
await put('requisitions/smoke2', { type: 'out', inventoryId: 'oil', itemName: 'Generator oil', locationId: 'marina', quantity: 50, reason: 'Too many', requestedById: 'emeka', requestedByName: 'Emeka Okafor', requestedAt: now, status: 'pending', createdAt: now, createdBy: 'emeka', updatedAt: now, updatedBy: 'emeka' });
const tooMany = await call('actionRequisition', { requisitionId: 'smoke2', decision: 'approve' }, admin);
check('approval refuses more than is in stock', tooMany.error?.message?.startsWith('Only'), tooMany.error?.message);

// 4. New stock item gets a SKU number.
await put('inventory/smoke-gloves', { locationId: 'marina', itemName: 'Safety gloves', quantity: 10, alertThreshold: 2, stockStatus: 'ok', status: 'active' });
await sleep(3000);
check('new stock item is numbered', /^SKU-\d{6}$/.test(val((await get('inventory/smoke-gloves')).ref) ?? ''), val((await get('inventory/smoke-gloves')).ref));

// 5. Renaming someone updates the copies on their work orders.
await fetch(`${FS}/users/tunde?updateMask.fieldPaths=name`, { method: 'PATCH', headers: owner, body: JSON.stringify({ fields: { name: { stringValue: 'Tunde B. Bakare' } } }) });
await sleep(4000);
check('rename reaches work orders', val((await get('workOrders/seed1037')).assignedToName) === 'Tunde B. Bakare', val((await get('workOrders/seed1037')).assignedToName));

// 6. A new SLA schedule gets its first run.
const start = new Date(Date.now() - 60_000);
const due = new Date(Date.now() + 2 * 3600_000);
const dueTime = `${String((due.getUTCHours() + 1) % 24).padStart(2, '0')}:${String(due.getUTCMinutes()).padStart(2, '0')}`; // Lagos is UTC+1
await put('slaSchedules/smoke-sla', { task: 'Smoke test pump check', locationId: 'marina', frequency: 'daily', startAt: start, dueTime, priority: 'high', assignedToId: 'emeka', supervisorId: 'sarah', status: 'active' });
await sleep(4000);
const sla = await get('slaSchedules/smoke-sla');
check('schedule gets its first run', !!val(sla.nextRunAt), `${val(sla.nextRunAt)} (due ${dueTime} Lagos)`);
