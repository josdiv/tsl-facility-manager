/**
 * Sets the Storage token claims (role, active, locs) for every user in the
 * live tsl-app database. The onUserAccessChange and onCompanyAccessChange
 * functions keep them up to date afterwards; run this once for users that
 * existed before those functions, or to repair claims.
 *
 *   node tool/sync_claims.cjs
 *
 * Uses the Firebase CLI's login. Build the functions first (npm run build).
 */
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const req = require('node:module').createRequire(path.join(__dirname, '../functions/package.json'));
const { initializeApp, applicationDefault } = req('firebase-admin/app');
const cli = require('/opt/homebrew/lib/node_modules/firebase-tools/lib/auth.js');
const api = require('/opt/homebrew/lib/node_modules/firebase-tools/lib/api.js');

const PROJECT = 'tsl-facility-manager';

// The CLI's login as application default credentials, in an owner-only
// temporary file deleted on exit.
const account = cli.getGlobalDefaultAccount();
const credentialsFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'tsl-claims-')), 'adc.json');
fs.writeFileSync(credentialsFile, JSON.stringify({
  type: 'authorized_user',
  client_id: api.clientId(),
  client_secret: api.clientSecret(),
  refresh_token: account.tokens.refresh_token,
  quota_project_id: PROJECT,
}), { mode: 0o600 });
process.env.GOOGLE_APPLICATION_CREDENTIALS = credentialsFile;
process.on('exit', () => fs.rmSync(path.dirname(credentialsFile), { recursive: true, force: true }));

// Set up the app before the functions code, which reuses it.
initializeApp({ projectId: PROJECT, credential: applicationDefault() });
const { db, auth } = require(path.join(__dirname, '../functions/lib/common.js'));
const { syncClaims } = require(path.join(__dirname, '../functions/lib/claims.js'));

async function main() {
  const users = await db.collection('users').get();
  for (const doc of users.docs) {
    await syncClaims(doc.id, doc.data());
    const { customClaims } = await auth.getUser(doc.id).catch(() => ({}));
    console.log(doc.data().email, JSON.stringify(customClaims ?? null));
  }
}

main().then(() => process.exit(0), (e) => { console.error(e.message ?? e); process.exit(1); });
