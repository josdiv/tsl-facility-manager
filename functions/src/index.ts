/**
 * Cloud Functions for TSL Facility Manager. The data contract is in
 * docs/firestore-schema.md ("Cloud Functions").
 *
 * Still to come: actionRequisition, runSlaSchedules, notifications and push,
 * assignRefs, onUserNameChange, and email delivery.
 */
export { createUser, sendEmailCode, verifyEmailCode } from './auth';
export { clockIn, clockOut } from './attendance';
export {
  onSupportMessage,
  onWorkOrderMessage,
  onWorkOrderWrite,
  reportIssue,
} from './workOrders';
