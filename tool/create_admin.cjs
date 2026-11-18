/**
 * Creates an admin account in the live project and emails a link to set its
 * password through the company mail API. For the first admin; after that,
 * admins use the createUser function from the dashboard.
 *
 *   node tool/create_admin.cjs <email> "<full name>"
 *
 * Uses the Firebase CLI's login.
 */
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const req = require('node:module').createRequire(path.join(__dirname, '../functions/package.json'));
const { initializeApp, applicationDefault } = req('firebase-admin/app');
const { getAuth } = req('firebase-admin/auth');
const { getFirestore, FieldValue } = req('firebase-admin/firestore');
const cli = require('/opt/homebrew/lib/node_modules/firebase-tools/lib/auth.js');
const api = require('/opt/homebrew/lib/node_modules/firebase-tools/lib/api.js');
const { sendMail } = require(path.join(__dirname, '../functions/lib/mail.js'));

const PROJECT = 'tsl-facility-manager';
const [email, name] = [process.argv[2]?.trim().toLowerCase(), process.argv[3]?.trim()];
if (!email || !name) {
  console.error('Usage: node tool/create_admin.cjs <email> "<full name>"');
  process.exit(1);
}

// The CLI's login as application default credentials, in an owner-only
// temporary file deleted on exit.
const account = cli.getGlobalDefaultAccount();
const credentialsFile = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'tsl-admin-')), 'adc.json');
fs.writeFileSync(credentialsFile, JSON.stringify({
  type: 'authorized_user',
  client_id: api.clientId(),
  client_secret: api.clientSecret(),
  refresh_token: account.tokens.refresh_token,
  quota_project_id: PROJECT,
}), { mode: 0o600 });
process.env.GOOGLE_APPLICATION_CREDENTIALS = credentialsFile;
process.on('exit', () => fs.rmSync(path.dirname(credentialsFile), { recursive: true, force: true }));

const app = initializeApp({ projectId: PROJECT, credential: applicationDefault() });
const auth = getAuth(app);
const db = getFirestore(app, 'tsl-app');

async function main() {
  const user = await auth.getUserByEmail(email).catch(async (e) => {
    if (e.code !== 'auth/user-not-found') throw e;
    console.log(`creating ${email}`);
    return auth.createUser({ email, displayName: name });
  });
  const ref = db.doc(`users/${user.uid}`);
  if ((await ref.get()).exists) {
    console.log('users document already exists; leaving it as it is');
  } else {
    const now = FieldValue.serverTimestamp();
    await ref.create({
      role: 'admin', status: 'active', name, email, phone: null, designation: 'Administrator',
      locationId: null, locationName: null, companyId: null, companyName: null,
      onShift: false, lastLoginAt: null,
      createdAt: now, createdBy: 'setup', updatedAt: now, updatedBy: 'setup',
    });
    console.log('users document created (role: admin)');
  }
  const link = await auth.generatePasswordResetLink(email);
  await sendMail(
    email,
    'Set up your TSL Facility Manager password',
    'Welcome to TSL Facility Manager\n\n' +
      `You have an administrator account for ${email}. Tap the link below to ` +
      `choose your password:\n\n${link}\n\nIf you didn’t expect this, you can ignore it.`,
  );
  console.log(`password setup email sent to ${email}`);
}

main().then(() => process.exit(0), (e) => { console.error(e.message ?? e); process.exit(1); });
