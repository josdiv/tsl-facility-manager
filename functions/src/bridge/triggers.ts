/**
 * Copies admin-managed records from the dashboard's database ((default)) into
 * the app's database (tsl-app) whenever they change. One trigger per
 * collection, so a failure in one never holds up the others.
 */
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { REGION } from '../common';
import { Bridged, logSteps, syncAdminRecord } from './sync';

function bridge(collection: Bridged) {
  return onDocumentWritten(
    { document: `${collection}/{id}`, database: '(default)', region: REGION, retry: false },
    async (event) => {
      // Off in the live project until the switch-over (functions/.env);
      // on in the emulators (functions/.env.local).
      if (process.env.BRIDGE_ENABLED !== 'true') return;
      const before = event.data?.before.data();
      const after = event.data?.after.data();
      const steps = await syncAdminRecord(collection, event.params.id, before, after, { apply: true });
      logSteps(collection, event.params.id, steps);
    },
  );
}

export const bridgeStaff = bridge('staff');
export const bridgeClient = bridge('client');
export const bridgeLocation = bridge('location');
export const bridgeZone = bridge('zone');
export const bridgeAsset = bridge('assets');
export const bridgeDocument = bridge('documents');
export const bridgeInventory = bridge('inventory');
export const bridgeSla = bridge('sla_schedules');
