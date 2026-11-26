/**
 * Sets the App Review client sign-in: one email whose sign-in code is fixed,
 * because reviewers can't read the inbox. Stores only a hash, in
 * settings/appReview (server-only). Nothing is emailed to that address.
 *
 *   REVIEW_CODE=123456 node tool/set_review_code.cjs appreview@example.com
 *
 * Uses the Firebase CLI's login. Writes the live tsl-app database.
 */
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createHash } = require('node:crypto');
const req = require('node:module').createRequire(path.join(__dirname, '../functions/package.json'));
const { initializeApp, applicationDefault } = req('firebase-admin/app');
const { getFirestore, FieldValue } = req('firebase-admin/firestore');
const cli = require('/opt/homebrew/lib/node_modules/firebase-tools/lib/auth.js');
const api = require('/opt/homebrew/lib/node_modules/firebase-tools/lib/api.js');

const email = (process.argv[2] || '').trim().toLowerCase();
const code = process.env.REVIEW_CODE || '';
if (!email.includes('@') || !/^\d{6}$/.test(code)) {
  console.error('Usage: REVIEW_CODE=<6 digits> node tool/set_review_code.cjs <email>');
  process.exit(1);
}

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tsl-review-'));
const adc = path.join(dir, 'adc.json');
fs.writeFileSync(adc, JSON.stringify({
  type: 'authorized_user',
  client_id: api.clientId(),
  client_secret: api.clientSecret(),
  refresh_token: cli.getGlobalDefaultAccount().tokens.refresh_token,
  quota_project_id: 'tsl-facility-manager',
}), { mode: 0o600 });
process.env.GOOGLE_APPLICATION_CREDENTIALS = adc;
process.on('exit', () => fs.rmSync(dir, { recursive: true, force: true }));

const app = initializeApp({ projectId: 'tsl-facility-manager', credential: applicationDefault() });
getFirestore(app, 'tsl-app').doc('settings/appReview').set({
  email,
  codeHash: createHash('sha256').update(`${email}:${code}`).digest('hex'),
  updatedAt: FieldValue.serverTimestamp(),
}).then(() => console.log(`Review sign-in set for ${email}.`));
