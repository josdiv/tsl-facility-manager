# Plan: connecting the app to the admin database

Status, 22 November 2026: step 1 is built and tested on the emulators, but
not switched on in the live project. The questions at the end are still open.

## Progress

- **Step 1, admin → app (built, off in the live project).** Code in
  `functions/src/bridge/`, with conversion tests (`functions/src/test/bridge.test.ts`)
  and an end-to-end emulator test (`tool/bridge_smoke.mjs`).
  `tool/bridge_backfill.cjs` copies everything across at the switch-over (dry
  run by default). The triggers do nothing until `BRIDGE_ENABLED=true` in
  `functions/.env`.
- **Passwords checked on live Firebase:** an account imported with a PHP
  bcrypt hash from the dashboard signs in with the right password and refuses
  a wrong one. The Auth emulator can't check imported hashes.
- **Defaults while questions are open:**
  - SLA schedules are copied but don't create jobs (`createsJobs: false`),
    so jobs aren't doubled (question 3).
  - Client companies keep an empty facility list until the dashboard records
    one (question 2).
  - Staff with an empty dashboard password get an app account without a
    password, and need a reset.
- **Step 2, shared data:** not started.

## The goal

The admin dashboard and the mobile app should work on the same data. An
admin who adds a facility, a staff member or an SLA schedule in the dashboard
should see it in the app, and work done in the app (jobs, attendance, parts
requests) should show in the dashboard.

As agreed with the boss:

- The admin database (`(default)` in the `tsl-facility-manager` project)
  stays the home of everything the admin manages.
- The app keeps its own database (`tsl-app`) for data only the app uses.

## What the admin database looks like today

Surveyed on 22 November 2026 (read only).

| Collection | Docs | What it holds |
| --- | --- | --- |
| `admin` | 1 | Dashboard admin login (username, bcrypt password) |
| `staff` | 4 | Staff and supervisors, with their own dashboard password, role (`Staff`, `Supervisor`), `assignedFacility` |
| `client` | 1 | A client company with one contact email, phone and an unused `clientOTP` field |
| `location` | 3 | Facilities with `latitude`, `longitude`, `radius`, `siteManager` |
| `zone` | 3 | Zones per facility |
| `assets` | 2 | Equipment per zone, `nextService` as text |
| `documents` | 2 | Files stored on thickservices.com, per facility |
| `inventory` | 1 | Stock per facility |
| `requisition` | 1 | Parts requests |
| `sla_schedules` | 4 | Recurring tasks with `assignedTo`, `supervisedBy`, `frequency`, `nextRun` |
| `work_order` | 3 | Jobs (types `Client`, `SLA`), attachments on thickservices.com |
| `workorder_status` | 8 | Job history, with up to 4 photo fields |
| `workorder_message` | 1 | Job chat |
| `attendance` | 3 | Clock-ins, including records the admin enters by hand (`Absent`) |

Things that matter for the plan:

1. **The dashboard has its own login.** It doesn't use Firebase
   Authentication. Staff passwords are bcrypt hashes in `staff` (one is
   empty). The project's Firebase sign-in accounts all belong to the app.
2. **The admin database is open to anyone.** Its rules are Firebase's test
   mode: anyone with the project's public app config can read or change
   everything, including password hashes, emails and phone numbers. Those
   rules stop working on **16 December 2026**. If the dashboard reaches
   Firestore with the public key rather than a server key (service account),
   it stops working that day too.
3. **Different conventions.** The dashboard uses IDs like `staff_6afb6…` and
   `loc_…`, capitalised values (`Active`, `In Progress`, `Weekday`), dates as
   text (`2026-11-19`, `09:00:00`), and one location spells `longitute`.
4. **Overlap.** Both sides create work orders (including SLA ones), record
   attendance and handle parts requests.
5. **Gaps the app needs filled.** Three of the four staff have no facility.
   Clients aren't linked to any facility.

## Recommended approach: a sync bridge

Cloud Functions copy data between the two databases as it changes. Each
piece of data has one owner, and changes only flow one way unless stated.

```
  Admin dashboard ──► (default) admin DB ──bridge──► tsl-app ──► Mobile app
                            ▲                          │
                            └─────────bridge───────────┘
                      (job progress, attendance, requests)
```

Why this rather than letting the app read the admin database directly:

- **The admin database can be locked.** Phones never touch it, so its rules
  can deny all outside access, provided the dashboard uses a service account.
  That fixes the open-data problem.
- **The app barely changes.** It keeps reading `tsl-app` in the format it
  already uses. Name and format differences are handled once, in the bridge.
- **The app's protections stay.** Its security rules, the GPS checks and the
  photo rules all keep working as they do now.

The cost: some data exists in both places, and changes take a second or two
to cross.

### Who owns what

| Data | Owner | Direction | Notes |
| --- | --- | --- | --- |
| Staff and supervisors (`staff` → `users`) | Admin | Admin → app | Creates their app sign-in (see Sign-in) |
| Facilities (`location` → `locations`) | Admin | Admin → app | Includes position and radius for clock-in and reports |
| Zones, assets, documents | Admin | Admin → app | Document files stay on thickservices.com; the app opens their links |
| Stock (`inventory`) | Admin | Admin → app | Quantity only changes through approved requests |
| Clients (`client` → `companies` + client user) | Admin | Admin → app | The dashboard needs to record which facilities each client uses |
| SLA schedules | Admin | Admin → app | One side generates the jobs, not both (question 3) |
| Work orders | Shared | Both | See Work orders |
| Job history (`workorder_status`) | App | App → admin | Written from the app's timeline, with photo links |
| Job chat (`workorder_message`) | Shared | Both | |
| Attendance | App | App → admin | GPS-verified clock-ins come from the app; hand-entered `Absent` records stay in the dashboard |
| Parts requests (`requisition`) | Shared | Both | Staff create them in the app; the admin approves in the dashboard; the bridge applies the stock change |
| Notifications, push devices, sign-in codes, counters, support chat | App | App only | Stay in `tsl-app` |

### Sign-in

- Each staff member's app account uses their dashboard ID as its Firebase ID
  (`staff_6afb6…`), so nothing needs a lookup table.
- Their bcrypt password hash is copied into Firebase Authentication, which
  accepts bcrypt. **They sign in to the app with the same password as the
  dashboard.** When it changes in the dashboard, the bridge copies the new
  hash.
- Clients keep signing in with an emailed code, at the email the dashboard
  has for them.
- The app's own test accounts are removed at switch-over.

### Work orders

- **Created in the app** (client reports): the app owns them, and they're
  copied to `work_order` for the dashboard. Status changes, history and photo
  links follow.
- **Created in the dashboard:** the bridge creates the app's copy, with the
  right technician and supervisor, and the job appears in the app.
- **Admin changes** in the dashboard (reassign, change the due date, cancel)
  flow back to the app. The job's progress (start, submit, inspect) is only
  changed in the app.
- **Numbering:** the dashboard's numbers (`WO-539444`) and the app's
  (`WO-1004`) can't clash, so both are kept. Each copy records the other's
  ID.
- **Photos** stay in Firebase Storage. The dashboard gets view links for
  them in `workorder_status.photo1`–`photo4`.

### Keeping it safe

- **No loops:** the bridge only writes when the converted data actually
  differs, so its own writes don't set it off again.
- **Tests for every conversion:** each one gets automated tests, plus
  end-to-end tests on the emulators with both databases.
- **Dry run first:** the first copy of existing admin data is printed for
  review before anything is written.

## Steps

| # | Step | Who | Rough time |
| --- | --- | --- | --- |
| 0 | Answer the questions below. The dashboard switches to a service account | Boss, dashboard developer | Before 16 Dec |
| 1 | Bridge for admin-owned data (staff and sign-in, facilities, zones, assets, documents, stock, clients, SLA), with tests | App team | 3–4 days |
| 2 | Bridge for shared data (work orders, history, chat, attendance, parts requests), with tests | App team | 4–5 days |
| 3 | Switch-over: copy existing admin data across, remove the app's test and earlier imported copies, test on phones with the boss | Both | 1–2 days |
| 4 | Lock the admin database rules | App team, after the dashboard confirms | Same day as 3 |

About two weeks of app work once the questions are answered. Step 0 is the
urgent one, because of the 16 December deadline.

## Questions for the boss and the dashboard developer

1. **How does the dashboard connect to Firestore?** With a service account
   (server key), or the public web config? If it's the public config, it
   breaks on 16 December and the data is open until then.
2. **Clients and facilities.** Can the dashboard record which facilities each
   client company uses? Can a company have more than one contact who reports
   issues?
3. **SLA jobs.** Should the dashboard or the app's scheduler create the jobs
   from SLA schedules? Only one of them should, or every job appears twice.
4. **Passwords.** Should staff use the same password in the app and the
   dashboard? Do staff and supervisors log in to the dashboard at all?
5. **Parts requests.** When the admin approves a request, is it fine for the
   bridge to reduce the stock, with the dashboard leaving stock alone?
6. **Staff without a facility.** Three of four staff have none. In the app
   they can't clock in or get jobs until the admin assigns one.
7. **Test data.** Should Mono Mall and the test accounts be created again in
   the dashboard, so the boss can keep testing after the switch-over?
8. **Field names.** Some dashboard fields need small fixes or additions (for
   example `longitute`, and client facilities). Is the dashboard developer
   fine making those?
