/**
 * Cloud Functions for TSL Facility Manager. The data contract is in
 * docs/firestore-schema.md ("Cloud Functions").
 */
export { createUser, sendEmailCode, verifyEmailCode } from './auth';
export { clockIn, clockOut } from './attendance';
export {
  bridgeAsset,
  bridgeClient,
  bridgeDocument,
  bridgeInventory,
  bridgeLocation,
  bridgeSla,
  bridgeStaff,
  bridgeZone,
} from './bridge/triggers';
export { onCompanyAccessChange, onUserAccessChange } from './claims';
export {
  actionRequisition,
  assignAssetRef,
  assignInventoryRef,
  onRequisitionCreated,
  onUserNameChange,
} from './parts';
export { createWorkOrder, onSlaScheduleWrite, runSlaSchedules } from './sla';
export {
  onSupportMessage,
  onWorkOrderMessage,
  onWorkOrderWrite,
  reportIssue,
} from './workOrders';
