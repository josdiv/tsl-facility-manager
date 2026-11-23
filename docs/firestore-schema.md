# TSL Facility Manager: Firestore schema

This is the data contract for the mobile app, the admin dashboard and the Cloud
Functions. If you need a field that isn't here, add it to this file in the same
change that starts using it.

The security rules in [`firestore.rules`](../firestore.rules) and
[`storage.rules`](../storage.rules) enforce this document. Tests for them live
in [`tool/firebase_rules_test`](../tool/firebase_rules_test).

## Conventions

| Topic | Rule |
| --- | --- |
| Collection names | camelCase, plural: `workOrders`, `slaSchedules` |
| Field names | camelCase. No spaces, no capitals at the start |
| Document IDs | Firestore auto IDs, except `users/{uid}` (Firebase Auth uid) and `supportThreads/{uid}` |
| Human references | Separate `ref` field, assigned by Cloud Functions from `counters`: `WO-1001`, `REQ-1001`, `AST-000001`, `SKU-000001` |
| Enum values | lowercase snake_case strings: `in_progress`, `pending_review` |
| Dates and times | Firestore `timestamp`, stored in UTC and shown in the location's `timeZone`. Never store dates as text |
| Time of day | Only for recurring schedules: `"HH:mm"` text, 24-hour, read in the location's `timeZone` |
| Coordinates | Firestore `geopoint` |
| Money and counts | `number` (integers unless stated) |
| Files | Cloud Storage path as text, for example `locations/marina/workOrders/abc123/report/1700000000.jpg`. Never a download URL |
| References | `<thing>Id` holds the document ID. A matching `<thing>Name` copy is kept for display (see [Copied names](#copied-names)) |
| Audit | Every top-level document has `createdAt`, `createdBy` (uid or `"system"`), `updatedAt` and `updatedBy` |
| Optional fields | Leave them out or set `null`. Don't use empty strings |

Passwords and one-time codes are never stored in Firestore. Firebase
Authentication handles sign-in.

## Who writes what

| Writer | How |
| --- | --- |
| Mobile app | Firebase client SDK, limited by the security rules |
| Admin dashboard | Firebase client SDK, signed in as a user with `role: "admin"` |
| Cloud Functions | Admin SDK. Bypasses the rules, so it owns every field marked **server** below |

Some actions go through **callable Cloud Functions** because they need checks
the rules can't do safely: creating work orders, clocking in and out, sending
and verifying email codes, creating user accounts, and approving requisitions.
See [Cloud Functions](#cloud-functions).

---

## Collections

### `users/{uid}`

One document per person who can sign in. The ID is the Firebase Auth uid. This
replaces the separate `staff`, `client` and `admin` tables.

| Field | Type | Notes |
| --- | --- | --- |
| `role` | enum | `admin`, `supervisor`, `staff`, `client`. **Admin only** |
| `status` | enum | `active`, `inactive`, `exited`. Only `active` users can use the app. **Admin only** |
| `name` | string | Full name. The user can edit it |
| `email` | string | Lowercase. Same as the Auth email. **Admin only** |
| `phone` | string \| null | E.164 format, for example `+2348031234567`. The user can edit it |
| `designation` | string \| null | Job title, for example `HVAC technician`. Staff and supervisors |
| `locationId` | string \| null | Staff and supervisors: their assigned facility (**admin only**). Clients: the facility they picked, which must be one of their company's `locationIds` |
| `locationName` | string \| null | Copy of the location name |
| `companyId` | string \| null | Clients only. **Admin only** |
| `companyName` | string \| null | Clients only. Copy |
| `onShift` | boolean | **Server.** True while clocked in |
| `lastLoginAt` | timestamp \| null | **Server** |
| `createdAt` `createdBy` `updatedAt` `updatedBy` | | Audit |

Sub-collections:

- `users/{uid}/notifications/{notificationId}`: in-app alerts
- `users/{uid}/fcmTokens/{token}`: push notification tokens

### `users/{uid}/notifications/{notificationId}`

Written by Cloud Functions. The user can only set `readAt`.

| Field | Type | Notes |
| --- | --- | --- |
| `kind` | enum | `assigned`, `returned`, `sla_due`, `submitted`, `completed`, `message`, `requisition`, `system` |
| `title` | string | For example `Task returned for correction` |
| `body` | string | For example `WO-1048 · Incomplete finishing` |
| `workOrderId` | string \| null | The work order's document ID |
| `workOrderRef` | string \| null | Its reference, such as `WO-1048`. The app opens it when tapped |
| `requisitionId` | string \| null | |
| `createdAt` | timestamp | |
| `readAt` | timestamp \| null | Set by the user |

### `users/{uid}/fcmTokens/{token}`

The document ID is the token. The owner writes it.

| Field | Type | Notes |
| --- | --- | --- |
| `platform` | enum | `android`, `ios`, `web` |
| `createdAt` | timestamp | |

### `companies/{companyId}`

A client organisation. Client users belong to one company. This holds the
account status and monthly limit that the "Account locked" and "Monthly limit
reached" screens use.

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | For example `Acme Corp Nigeria Ltd.` |
| `status` | enum | `active`, `locked`, `disabled`. Clients of a company that isn't `active` can't sign in or create requests |
| `monthlyWorkOrderLimit` | number \| null | `null` means no limit |
| `locationIds` | array&lt;string&gt; | Facilities this company's clients can report issues for |
| `contactEmail` | string \| null | |
| `contactPhone` | string \| null | |
| Audit fields | | |

Sub-collection `companies/{companyId}/usage/{yyyy-MM}`, for example `2026-11`:

| Field | Type | Notes |
| --- | --- | --- |
| `workOrderCount` | number | **Server.** Client requests created this month (Africa/Lagos calendar month) |

### `locations/{locationId}`

A facility.

| Field | Type | Notes |
| --- | --- | --- |
| `name` | string | For example `Marina Towers` |
| `type` | enum | `office`, `warehouse`, `shopping_mall`, `residential`, `industrial`, `other` |
| `address` | string | |
| `geo` | geopoint | Centre of the attendance geofence |
| `radiusM` | number | Geofence radius in metres, for example `100` |
| `timeZone` | string | IANA name, default `Africa/Lagos` |
| `siteManagerId` | string \| null | A `users` uid |
| `siteManagerName` | string \| null | Copy |
| `zoneCount` | number | **Server** |
| `assetCount` | number | **Server** |
| `status` | enum | `active`, `inactive` |
| Audit fields | | |

### `zones/{zoneId}`

An area inside a location.

| Field | Type | Notes |
| --- | --- | --- |
| `locationId` | string | |
| `name` | string | For example `Tower A · Floor 3` |
| `description` | string \| null | |
| `status` | enum | `active`, `inactive` |
| Audit fields | | |

### `assets/{assetId}`

| Field | Type | Notes |
| --- | --- | --- |
| `ref` | string | **Server.** `AST-000001` |
| `locationId` | string | Copied from the zone so assets can be listed by location |
| `zoneId` | string | |
| `zoneName` | string | Copy |
| `equipmentName` | string | For example `500kVA Backup Generator` |
| `nextServiceAt` | timestamp \| null | |
| `status` | enum | `active`, `maintenance`, `inactive` |
| Audit fields | | |

### `documents/{documentId}`

Files attached to a location, such as SOPs and certificates.

| Field | Type | Notes |
| --- | --- | --- |
| `locationId` | string | |
| `title` | string | |
| `category` | enum | `compliance`, `manual`, `contract`, `report`, `other` |
| `description` | string \| null | |
| `filePath` | string \| null | Storage path under `locations/{locationId}/documents/{documentId}/`. Null when the file is on the dashboard's server |
| `fileUrl` | string \| null | Link to a file on the dashboard's server (thickservices.com). Set by the admin bridge |
| `fileName` | string | Original file name, for display |
| `contentType` | string | For example `application/pdf` |
| `sizeBytes` | number | |
| Audit fields | | |

### `slaSchedules/{slaId}`

A recurring maintenance task. A scheduled Cloud Function turns each due run into
a work order with `type: "sla"`.

| Field | Type | Notes |
| --- | --- | --- |
| `task` | string | Becomes the work order title |
| `description` | string \| null | |
| `locationId` | string | |
| `assetId` | string \| null | Optional. Replaces the old `locationAsset` field |
| `frequency` | enum | `daily`, `weekdays`, `weekends`, `weekly`, `fortnightly`, `monthly`, `quarterly`, `biannually`, `annually` |
| `startAt` | timestamp | The first day the schedule runs |
| `dueTime` | string | `"HH:mm"` in the location's time zone |
| `priority` | enum | `low`, `medium`, `high`, `critical`. Default `high` |
| `assignedToId` | string | A `staff` uid |
| `supervisorId` | string | A `supervisor` uid |
| `nextRunAt` | timestamp | **Server** |
| `lastRunAt` | timestamp \| null | **Server** |
| `status` | enum | `active`, `inactive` |
| `createsJobs` | boolean | Absent or `true`: the scheduler makes its work orders. `false`: a dashboard schedule whose jobs the dashboard still makes, kept for reference |
| Audit fields | | |

### `workOrders/{workOrderId}`

The centre of the app. Client requests and SLA tasks both live here.

**Created only by Cloud Functions** (the `reportIssue` and `createWorkOrder`
callables, and the SLA scheduler), which assign `ref` and enforce the monthly
limit.

| Field | Type | Notes |
| --- | --- | --- |
| `ref` | string | `WO-1001`, `WO-1002`, and so on |
| `type` | enum | `client`, `sla` |
| `title` | string | |
| `description` | string | |
| `priority` | enum | `low`, `medium`, `high`, `critical` |
| `status` | enum | `open`, `in_progress`, `pending_review`, `returned`, `completed`, `cancelled`. See [lifecycle](#work-order-lifecycle) |
| `locationId` `locationName` | string | |
| `zoneId` `zoneName` | string \| null | |
| `assetId` `assetName` | string \| null | |
| `companyId` `companyName` | string \| null | Client requests |
| `clientId` `clientName` | string \| null | The client user who reported it |
| `slaId` | string \| null | SLA tasks |
| `assignedToId` `assignedToName` | string \| null | The technician |
| `supervisorId` `supervisorName` | string \| null | |
| `assignmentNote` | string \| null | Up to 1,000 characters. The supervisor's note to the technician when reassigning, for example `Overdue, please do this first` |
| `dueAt` | timestamp | |
| `reportPhotos` | array&lt;string&gt; | Storage paths. Up to 4. From the person who reported it |
| `reportGeo` | geopoint \| null | Where the client's phone was when they reported it. Null for SLA and dashboard work |
| `reportDistanceM` | number \| null | Metres from the facility at the time. Null when the facility had no position yet |
| `reportAccuracyM` | number \| null | GPS accuracy of that reading, in metres |
| `startedAt` | timestamp \| null | |
| `workNote` | string \| null | The technician's update when submitting |
| `workPhotos` | array&lt;string&gt; | 1 to 6 when submitting. Proof of completed work |
| `submittedAt` | timestamp \| null | |
| `returnReason` | enum \| null | `incomplete_finishing`, `not_satisfactory`, `safety_concern`, `wrong_resolution` |
| `returnFeedback` | string \| null | |
| `returnPhotos` | array&lt;string&gt; | Up to 4 |
| `returnedAt` | timestamp \| null | |
| `inspectionChecks` | array&lt;string&gt; | Checklist items the supervisor ticked |
| `inspectionNote` | string \| null | |
| `inspectionPhotos` | array&lt;string&gt; | Up to 4. Photos the supervisor adds when confirming |
| `completedAt` | timestamp \| null | |
| `lastMessageAt` | timestamp \| null | **Server** |
| `lastMessagePreview` | string \| null | **Server.** First 120 characters |
| `createdAt` `createdBy` `updatedAt` `updatedBy` | | `updatedBy` must be the uid of the person making the change |

The 4 fixed `attachDocumentOne` to `attachDocumentFour` fields are replaced by
the three photo lists, so it's clear who added each photo and when.

Clients see `returned` as "In Progress". The app does that; the data keeps the
real status.

#### Work order lifecycle

```
            start              submit                 confirm
  open ───────────▶ in_progress ───────▶ pending_review ─────────▶ completed
                         ▲                     │
                         │ submit              │ return for correction
                         └────── returned ◀────┘
```

| Change | Who | Fields they may change |
| --- | --- | --- |
| Start | The assigned staff member | `status` (`open` → `in_progress`), `startedAt` |
| Submit | The assigned staff member | `status` (`in_progress` or `returned` → `pending_review`), `workNote`, `workPhotos` (at least one), `submittedAt` |
| Confirm | A supervisor at the location | `status` (`pending_review` → `completed`), `inspectionChecks`, `inspectionNote`, `inspectionPhotos`, `completedAt` |
| Return | A supervisor at the location | `status` (`pending_review` → `returned`), `returnReason`, `returnFeedback`, `returnPhotos`, `returnedAt`, and optionally `assignedToId` and `assignedToName` |
| Reassign | A supervisor at the location | `assignedToId`, `assignedToName`, `supervisorId`, `supervisorName`, `assignmentNote`. Not allowed once `completed` or `cancelled` |
| Anything | Admin | Any field except `ref`, `createdAt` and `createdBy` |

Every change also sets `updatedAt` (the server time) and `updatedBy`. Times such
as `submittedAt` must be the server time too.

A Cloud Function writes an entry to `events` for each status or assignee change.

### `workOrders/{workOrderId}/events/{eventId}`

The timeline on the work order screens. **Server only.** It replaces the old
`workorder_status` table.

| Field | Type | Notes |
| --- | --- | --- |
| `kind` | enum | `reported`, `assigned`, `started`, `submitted`, `returned`, `confirmed`, `reassigned`, `cancelled` |
| `statusAfter` | enum | The work order status after this event |
| `actorId` | string | uid, or `"system"` |
| `actorName` | string | |
| `actorRole` | enum | `admin`, `supervisor`, `staff`, `client`, `system` |
| `note` | string \| null | For example the return reason, or `Assigned to Emeka Okafor` |
| `photos` | array&lt;string&gt; | Photos added in this step |
| `createdAt` | timestamp | |

### `workOrders/{workOrderId}/messages/{messageId}`

Chat about a work order. It replaces `workorder_message`. Anyone who can see the
work order can read and post, except on `cancelled` orders.

| Field | Type | Notes |
| --- | --- | --- |
| `text` | string | 1 to 2,000 characters |
| `senderId` | string | Must be the uid of the sender |
| `senderName` | string | |
| `senderRole` | enum | `admin`, `supervisor`, `staff`, `client` |
| `sentAt` | timestamp | Server time |

### `supportThreads/{uid}` and `supportThreads/{uid}/messages/{messageId}`

One support conversation per user, not tied to a work order. The user and
admins can read it.

The thread document (**server**): `userId`, `userName`, `userRole`,
`lastMessageAt`, `lastMessagePreview`, `unreadByAdmin` (boolean).

Messages use the same fields as work order messages.

### `attendance/{attendanceId}`

One document per shift. **Written only by the `clockIn` and `clockOut`
callables**, which check the distance to the facility on the server.

| Field | Type | Notes |
| --- | --- | --- |
| `userId` `userName` | string | |
| `locationId` `locationName` | string | |
| `status` | enum | `clocked_in`, `clocked_out` |
| `attendanceStatus` | enum | `present`, `absent`, `off_duty`. An admin can correct it |
| `clockInAt` | timestamp | |
| `clockInGeo` | geopoint | |
| `clockInDistanceM` | number | Distance from the facility centre, in metres |
| `clockInAccuracyM` | number | GPS accuracy reported by the phone |
| `clockOutAt` | timestamp \| null | |
| `clockOutGeo` | geopoint \| null | |
| `clockOutDistanceM` | number \| null | |
| `source` | enum | `app`, `admin`, `system` |
| Audit fields | | |

### `inventory/{itemId}`

| Field | Type | Notes |
| --- | --- | --- |
| `ref` | string | **Server.** `SKU-000001` |
| `locationId` | string | Where the stock is kept |
| `itemName` | string | |
| `quantity` | number | 0 or more |
| `alertThreshold` | number | Low-stock level |
| `stockStatus` | enum | `ok`, `low`, `out`. Must match the quantity: `out` when it's 0, `low` when it's at or below `alertThreshold`, otherwise `ok`. The rules check this |
| `photoPath` | string \| null | Storage path under `inventory/{itemId}/` |
| `photoUrl` | string \| null | Link to a photo on the dashboard's server. Set by the admin bridge |
| `status` | enum | `active`, `inactive` |
| Audit fields | | |

### `requisitions/{requisitionId}`

A parts request (`out`) or a stock delivery (`in`).

| Field | Type | Notes |
| --- | --- | --- |
| `ref` | string | **Server.** `REQ-1001` |
| `type` | enum | `in`, `out` |
| `inventoryId` `itemName` | string | |
| `locationId` | string | Must match the inventory item's location |
| `workOrderId` `workOrderRef` | string \| null | The linked work order. The parts screen asks for it |
| `quantity` | number | 1 or more |
| `reason` | string | |
| `requestedById` `requestedByName` | string | |
| `requestedAt` | timestamp | |
| `status` | enum | `pending`, `approved`, `rejected` |
| `actionedById` `actionedByName` | string \| null | |
| `actionedAt` | timestamp \| null | |
| `rejectionReason` | string \| null | |
| Audit fields | | |

Staff and supervisors create `out` requests with `status: "pending"`. Admins
approve or reject them through the `actionRequisition` callable, which changes
the stock and `stockStatus` in the same transaction. Admins can also create
`in` deliveries.

### `counters/{name}` and `emailCodes/{emailHash}`

**Server only.** No app or dashboard access.

- `counters/workOrders`, `counters/requisitions`, `counters/assets` and
  `counters/inventory` hold `{ next: number }` for the `ref` numbers.
- `emailCodes/{sha256 of email}` holds a hashed sign-in code, the number of
  attempts and an expiry time.

---

## Who can read what

| Collection | Client | Staff | Supervisor | Admin |
| --- | --- | --- | --- | --- |
| `users` | Self | Self | Self, plus users at their location | All |
| `companies` | Own company | No | No | All |
| `locations` | Their company's locations | All active | All active | All |
| `zones` | Their company's locations | All | All | All |
| `assets` | No | All | All | All |
| `documents` | No | Their location | Their location | All |
| `slaSchedules` | No | Their location | Their location | All |
| `workOrders` + `events` + `messages` | Their own requests | Assigned to them | Their location | All |
| `supportThreads` | Own | Own | Own | All |
| `attendance` | No | Own | Own, plus their location | All |
| `inventory` | No | Their location | Their location | All |
| `requisitions` | No | Own | Their location | All |

Every query from the app has to filter the same way, or Firestore refuses it.
For example a supervisor lists work orders with
`where('locationId', '==', myLocationId)`, and a staff member with
`where('assignedToId', '==', uid)`.

Everyone must be signed in with an `active` user document. Clients must also
belong to an `active` company.

## Cloud Storage layout

| Path | Who uploads | Who reads |
| --- | --- | --- |
| `locations/{locationId}/workOrders/{id}/report/{file}` | A client of a company using the location, before calling `reportIssue` (the app picks the new work order ID) | Admins, and staff, supervisors and clients at the location |
| `locations/{locationId}/workOrders/{id}/work/{file}` | Staff at the location | Same |
| `locations/{locationId}/workOrders/{id}/return/{file}` | Supervisors at the location | Same |
| `locations/{locationId}/workOrders/{id}/inspection/{file}` | Supervisors at the location | Same |
| `locations/{locationId}/documents/{documentId}/{file}` | Admin | Staff and supervisors at the location, and admins |
| `inventory/{itemId}/{file}` | Admin | Staff, supervisors and admins |

`{locationId}` is the work order's or document's `locationId`. Work order
photos must be images under 10 MB, and files are never overwritten. Documents
can be up to 25 MB.

Storage rules can't read the `tsl-app` database (only `(default)`), so they
check the person's sign-in token instead. The `onUserAccessChange` and
`onCompanyAccessChange` functions keep these custom claims up to date:

| Claim | Value |
| --- | --- |
| `role` | `admin`, `supervisor`, `staff` or `client` |
| `active` | `true` when the user is `active` and, for a client, their company is too |
| `locs` | Location IDs: a staff member's or supervisor's `locationId`, or all of a client's company `locationIds` |

A new token picks up changed claims. The app refreshes its token before
uploading. The dashboard should do the same, with `getIdToken(true)`.
Firestore rules decide which photos may be attached to a work order, and
when.

## Cloud Functions

| Function | Kind | What it does |
| --- | --- | --- |
| `sendEmailCode` | Callable | Emails a 6-digit code to a client through the company mail API. Stores only a hash in `emailCodes`. One email a minute |
| `verifyEmailCode` | Callable | Checks the code (5 tries, 10 minutes) and returns a Firebase custom token for the app to sign in with |
| `createUser` | Callable, admin | Creates the Auth account and the `users` document. Emails staff a password-setup link |
| `reportIssue` | Callable, client | Checks the company status and monthly limit, and that the client's phone is inside the facility's geofence (same rules as clock-in; skipped while the facility has no position), assigns the `WO-` ref and creates the work order |
| `createWorkOrder` | Callable, admin | Creates a work order from the dashboard, with the next `WO-` ref and copied names |
| `clockIn` / `clockOut` | Callable, staff and supervisor | Checks the distance to the facility and writes `attendance` and `users.onShift`. Refuses fake-GPS readings |
| `actionRequisition` | Callable, admin | Approves or rejects a requisition. Approving changes the stock and `stockStatus` in the same transaction |
| `onWorkOrderWrite` | Trigger | Writes `events` and notifies the people involved |
| `onWorkOrderMessage` / `onSupportMessage` | Trigger | Update the latest-message fields and notify people |
| `onRequisitionCreated` | Trigger | Numbers the request (`REQ-`) and notifies the facility's supervisors |
| `assignAssetRef` / `assignInventoryRef` | Trigger | Give new assets and stock items their `AST-` / `SKU-` refs |
| `onUserNameChange` | Trigger | Updates copied names (see below) |
| `onUserAccessChange` / `onCompanyAccessChange` | Trigger | Keep the Storage token claims (`role`, `active`, `locs`) in step with the user and their company |
| `bridgeStaff`, `bridgeClient`, `bridgeLocation`, `bridgeZone`, `bridgeAsset`, `bridgeDocument`, `bridgeInventory`, `bridgeSla` | Trigger, on the admin database | Copy admin-managed records from the dashboard's database into this one (docs/admin-db-integration-plan.md). Off until the switch-over (`BRIDGE_ENABLED` in `functions/.env`) |
| `onSlaScheduleWrite` | Trigger | Sets `nextRunAt` when a schedule is created or switched back on |
| `runSlaSchedules` | Scheduled, every 15 minutes | Creates each SLA work order 12 hours before it's due, notifies the technician, and moves `nextRunAt` on |

Notifications go to `users/{uid}/notifications` and, as a push through
Firebase Cloud Messaging, to every token in `users/{uid}/fcmTokens`. Pushes
are notification messages on the Android channel `tsl.default`, with `kind`,
`workOrderId` and `workOrderRef` as data. Tokens FCM reports as gone are
deleted.

## Copied names

To avoid an extra read on every list, documents keep a copy of names next to
IDs: `locationName`, `assignedToName`, `clientName` and so on. When the original
name changes, the `onUserNameChange` function and similar ones update the
copies. Only Cloud Functions do this; the app and dashboard write the name at
the moment they set the ID.

## Changes from the first draft

The first draft was the Database Table Schema document and spreadsheet, plus
the sample data in Firestore.

- `staff`, `client` and `admin` are merged into `users`, keyed by the Firebase
  Auth uid. `password` and `clientOTP` are removed; Firebase Auth and the email
  code functions handle sign-in.
- `companies` is new. It holds the client organisation, account status, monthly
  limit and facilities.
- Field names are fixed: `addresss` → `address`, `longitute` and `latitude` →
  `geo`, `AssignedTo` → `assignedToId`, `created by` → `createdBy`,
  `nextService` → `nextServiceAt`.
- Text dates and times (`dueDate` + `dueTime`, `clockInDate` + `clockInTime`)
  are now single timestamps: `dueAt`, `clockInAt`.
- Work order status gains `returned` and `cancelled`. The review fields (work
  note and photos, return reason and feedback, inspection checks, note and
  photos) and the supervisor's `assignmentNote` are added.
- `attachDocumentOne` to `attachDocumentFour` are replaced by `reportPhotos`,
  `workPhotos` and `returnPhotos`.
- `workorder_status` becomes the `events` sub-collection, and
  `workorder_message` becomes the `messages` sub-collection.
- `supportThreads` and `notifications` are new.
- Requisitions gain `workOrderId`. Inventory `quantityStatus` becomes
  `stockStatus` and is checked against the quantity.
- SLA frequency gains `weekly`. The sample "Weekly Generator Load Test" had no
  matching option.
- All enum values are lowercase snake_case.
