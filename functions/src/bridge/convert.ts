/**
 * Converts records from the admin dashboard's database ((default)) into the
 * app's format (tsl-app), as described in docs/admin-db-integration-plan.md.
 * Pure functions: everything they need from other records comes in [Lookup].
 */
import { GeoPoint, Timestamp } from 'firebase-admin/firestore';

export type AdminDoc = Record<string, unknown>;

/** Other admin records a conversion needs, already fetched. */
export interface Lookup {
  location(id: string | null): AdminDoc | undefined;
  staff(id: string | null): AdminDoc | undefined;
  zone(id: string | null): AdminDoc | undefined;
  client(id: string | null): AdminDoc | undefined;
}

/**
 * A converted record. [fields] are owned by the admin and overwritten on every
 * change; [onCreate] are only set when the app's record is first made, so the
 * app or its server can change them afterwards.
 */
export interface Converted {
  collection: string;
  id: string;
  fields: Record<string, unknown>;
  onCreate: Record<string, unknown>;
}

// --------------------------------------------------------------- helpers

const str = (v: unknown): string | null => {
  if (typeof v === 'string') return v.trim() || null;
  if (typeof v === 'number') return String(v);
  return null;
};

/** Numbers sometimes arrive as text ("25"). */
const num = (v: unknown): number | null => {
  const n = typeof v === 'number' ? v : typeof v === 'string' && v.trim() ? Number(v) : NaN;
  return Number.isFinite(n) ? n : null;
};

const lower = (v: unknown) => str(v)?.toLowerCase().replace(/[\s-]+/g, '_') ?? null;

/** "2026-11-19" as midnight in Lagos (UTC+1, no daylight saving). */
export function lagosDate(v: unknown): Timestamp | null {
  if (v instanceof Timestamp) return v;
  const s = str(v);
  if (!s || !/^\d{4}-\d{2}-\d{2}/.test(s)) return null;
  const ms = Date.parse(`${s.slice(0, 10)}T00:00:00+01:00`);
  return Number.isFinite(ms) ? Timestamp.fromMillis(ms) : null;
}

/** "09:00:00" or "9:00" → "09:00". */
export function hhmm(v: unknown): string | null {
  const m = /^(\d{1,2}):(\d{2})/.exec(str(v) ?? '');
  if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) return null;
  return `${m[1].padStart(2, '0')}:${m[2]}`;
}

/** Nigerian numbers to E.164: "08031234501" → "+2348031234501". */
export function phone(v: unknown): string | null {
  const raw = str(v)?.replace(/[\s()-]/g, '');
  if (!raw) return null;
  if (/^\+\d{8,15}$/.test(raw)) return raw;
  if (/^234\d{10}$/.test(raw)) return `+${raw}`;
  if (/^0\d{10}$/.test(raw)) return `+234${raw.slice(1)}`;
  return raw;
}

const email = (v: unknown) => str(v)?.toLowerCase() ?? null;

/** Active / Inactive / anything else, for records with a simple status. */
const activeStatus = (v: unknown) => (lower(v) === 'inactive' ? 'inactive' : 'active');

const audit = (d: AdminDoc) => ({
  createdAt: d.createdAt instanceof Timestamp ? d.createdAt : Timestamp.now(),
  createdBy: 'admin-sync',
});

// ----------------------------------------------------------------- staff

const ROLES: Record<string, 'staff' | 'supervisor'> = {
  staff: 'staff',
  technician: 'staff',
  supervisor: 'supervisor',
  facility_supervisor: 'supervisor',
};

const USER_STATUS: Record<string, 'active' | 'inactive' | 'exited'> = {
  active: 'active',
  inactive: 'inactive',
  suspended: 'inactive',
  exited: 'exited',
  terminated: 'exited',
  resigned: 'exited',
};

/** `staff/{staffId}` → `users/{staffId}`. Null when the role isn't one the app knows. */
export function convertStaff(id: string, d: AdminDoc, look: Lookup): Converted | null {
  const role = ROLES[lower(d.role) ?? ''];
  const address = email(d.email);
  if (!role || !address) return null;
  const locationId = str(d.assignedFacility);
  const location = look.location(locationId);
  return {
    collection: 'users',
    id,
    fields: {
      role,
      status: USER_STATUS[lower(d.status) ?? ''] ?? 'inactive',
      name: str(d.name) ?? address,
      email: address,
      phone: phone(d.phone),
      designation: str(d.designation),
      // Kept even if the facility isn't copied yet; its name is filled in
      // when it is (sync.ts).
      locationId,
      locationName: location ? str(location.name) : null,
      companyId: null,
      companyName: null,
    },
    onCreate: { onShift: false, lastLoginAt: null, ...audit(d) },
  };
}

// --------------------------------------------------------------- clients

/**
 * `client/{clientId}` → `companies/{clientId}`. The dashboard has no
 * facility list for clients yet, so `locationIds` is only set if it gains a
 * `locationIds` field; otherwise the app's list is kept.
 */
export function convertCompany(id: string, d: AdminDoc): Converted {
  const fields: Record<string, unknown> = {
    name: str(d.clientName) ?? id,
    status: ['locked', 'disabled'].includes(lower(d.status) ?? '') ? lower(d.status) : 'active',
    contactEmail: email(d.clientEmail),
    contactPhone: phone(d.clientPhone),
  };
  const onCreate: Record<string, unknown> = { locationIds: [], monthlyWorkOrderLimit: null, ...audit(d) };
  if (Array.isArray(d.locationIds)) fields.locationIds = d.locationIds.filter((x) => typeof x === 'string');
  if (d.monthlyWorkOrderLimit !== undefined) fields.monthlyWorkOrderLimit = num(d.monthlyWorkOrderLimit);
  return { collection: 'companies', id, fields, onCreate };
}

/** The client company's contact, who signs in to the app with an emailed code. */
export function convertClientUser(id: string, d: AdminDoc): Converted | null {
  const address = email(d.clientEmail);
  if (!address) return null;
  const companyLocations = Array.isArray(d.locationIds) ? (d.locationIds as string[]) : [];
  return {
    collection: 'users',
    id,
    fields: {
      role: 'client',
      status: activeStatus(d.status),
      name: str(d.contactName) ?? str(d.clientName) ?? address,
      email: address,
      phone: phone(d.clientPhone),
      designation: null,
      companyId: id,
      companyName: str(d.clientName) ?? id,
    },
    // The client picks their facility in the app.
    onCreate: {
      locationId: companyLocations[0] ?? null,
      locationName: null,
      onShift: false,
      lastLoginAt: null,
      ...audit(d),
    },
  };
}

// ------------------------------------------------------------ facilities

const LOCATION_TYPES = ['office', 'warehouse', 'shopping_mall', 'residential', 'industrial'];

export function convertLocation(id: string, d: AdminDoc, look: Lookup): Converted {
  const lat = num(d.latitude);
  // The dashboard has spelled it "longitute" in at least one record.
  const lng = num(d.longitude ?? d.longitute);
  const manager = look.staff(str(d.siteManager));
  const type = lower(d.type);
  return {
    collection: 'locations',
    id,
    fields: {
      name: str(d.name) ?? id,
      type: type && LOCATION_TYPES.includes(type) ? type : type === 'mall' ? 'shopping_mall' : 'other',
      address: str(d.address) ?? '',
      geo: lat != null && lng != null && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? new GeoPoint(lat, lng) : null,
      radiusM: (num(d.radius) ?? 0) > 0 ? num(d.radius) : 100,
      siteManagerId: str(d.siteManager),
      siteManagerName: manager ? str(manager.name) : null,
      zoneCount: num(d.zonesTotal) ?? 0,
      assetCount: num(d.assetTotal) ?? 0,
      status: activeStatus(d.status),
    },
    onCreate: { timeZone: 'Africa/Lagos', ...audit(d) },
  };
}

export function convertZone(id: string, d: AdminDoc): Converted | null {
  const locationId = str(d.locationId);
  if (!locationId) return null;
  return {
    collection: 'zones',
    id,
    fields: {
      locationId,
      name: str(d.name) ?? id,
      description: str(d.description),
      status: activeStatus(d.status),
    },
    onCreate: audit(d),
  };
}

const ASSET_STATUS: Record<string, string> = { active: 'active', maintenance: 'maintenance', under_maintenance: 'maintenance' };

/** Assets sit in a zone; the facility comes from that zone. */
export function convertAsset(id: string, d: AdminDoc, look: Lookup): Converted | null {
  const zoneId = str(d.zoneId);
  const zone = look.zone(zoneId);
  const locationId = str(zone?.locationId);
  if (!zone || !locationId) return null;
  return {
    collection: 'assets',
    id,
    fields: {
      ref: str(d.assetId) ?? id,
      locationId,
      zoneId,
      zoneName: str(zone.name),
      equipmentName: str(d.equipmentName) ?? id,
      nextServiceAt: lagosDate(d.nextService ?? d.nextServiceDate),
      status: ASSET_STATUS[lower(d.status) ?? ''] ?? 'inactive',
    },
    onCreate: audit(d),
  };
}

const DOC_CATEGORIES: Record<string, string> = {
  compliance: 'compliance',
  certificate: 'compliance',
  manual: 'manual',
  manuals: 'manual',
  contract: 'contract',
  contracts: 'contract',
  report: 'report',
  reports: 'report',
};

const CONTENT_TYPES: Record<string, string> = {
  pdf: 'application/pdf',
  jpg: 'image/jpeg',
  jpeg: 'image/jpeg',
  png: 'image/png',
  webp: 'image/webp',
  doc: 'application/msword',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xls: 'application/vnd.ms-excel',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
};

/** The file stays on the dashboard's server; the app opens [fileUrl]. */
export function convertDocument(id: string, d: AdminDoc): Converted | null {
  const locationId = str(d.locationId);
  const url = str(d.documentFile);
  if (!locationId) return null;
  const fileName = url ? decodeURIComponent(url.split('?')[0].split('/').pop() ?? '') : '';
  const extension = fileName.split('.').pop()?.toLowerCase() ?? '';
  return {
    collection: 'documents',
    id,
    fields: {
      locationId,
      title: str(d.title) ?? fileName ?? id,
      category: DOC_CATEGORIES[lower(d.category) ?? ''] ?? 'other',
      description: str(d.description),
      filePath: null,
      fileUrl: url,
      fileName: fileName || null,
      contentType: CONTENT_TYPES[extension] ?? null,
      sizeBytes: null,
    },
    onCreate: audit(d),
  };
}

export function stockStatus(quantity: number, threshold: number): 'ok' | 'low' | 'out' {
  return quantity <= 0 ? 'out' : quantity <= threshold ? 'low' : 'ok';
}

export function convertInventory(id: string, d: AdminDoc): Converted | null {
  const locationId = str(d.locationId);
  if (!locationId) return null;
  const quantity = Math.max(0, Math.round(num(d.quantity) ?? 0));
  const alertThreshold = Math.max(0, Math.round(num(d.alertThreshold) ?? 0));
  return {
    collection: 'inventory',
    id,
    fields: {
      ref: str(d.inventoryId) ?? id,
      locationId,
      itemName: str(d.itemName) ?? id,
      quantity,
      alertThreshold,
      stockStatus: stockStatus(quantity, alertThreshold),
      photoPath: null,
      photoUrl: str(d.itemPhoto),
      status: activeStatus(d.status),
    },
    onCreate: audit(d),
  };
}

// ------------------------------------------------------------------- SLA

const FREQUENCIES: Record<string, string> = {
  daily: 'daily',
  weekday: 'weekdays',
  weekdays: 'weekdays',
  weekend: 'weekends',
  weekends: 'weekends',
  weekly: 'weekly',
  fortnightly: 'fortnightly',
  biweekly: 'fortnightly',
  monthly: 'monthly',
  quarterly: 'quarterly',
  biannually: 'biannually',
  bi_annually: 'biannually',
  half_yearly: 'biannually',
  annually: 'annually',
  yearly: 'annually',
};

const PRIORITIES = ['low', 'medium', 'high', 'critical'];

/**
 * `sla_schedules/{slaId}` → `slaSchedules/{slaId}`. [appCreatesJobs] says
 * whether the app's scheduler turns it into work orders; when the dashboard
 * does that itself, the app's copy is for display only.
 */
export function convertSla(id: string, d: AdminDoc, appCreatesJobs: boolean): Converted | null {
  const locationId = str(d.locationId);
  const frequency = FREQUENCIES[lower(d.frequency) ?? ''];
  const dueTime = hhmm(d.dueTime);
  const startAt = lagosDate(d.startDate);
  if (!locationId || !frequency || !dueTime || !startAt) return null;
  const priority = lower(d.priority);
  return {
    collection: 'slaSchedules',
    id,
    fields: {
      task: str(d.task) ?? id,
      description: str(d.description),
      locationId,
      assetId: str(d.assetId),
      frequency,
      startAt,
      dueTime,
      priority: priority && PRIORITIES.includes(priority) ? priority : 'high',
      assignedToId: str(d.assignedTo),
      supervisorId: str(d.supervisedBy),
      status: activeStatus(d.status),
      createsJobs: appCreatesJobs,
    },
    onCreate: { nextRunAt: null, lastRunAt: null, ...audit(d) },
  };
}

// --------------------------------------------------------------- compare

/** Whether two Firestore values are the same, including timestamps and geopoints. */
export function sameValue(a: unknown, b: unknown): boolean {
  if (a === b) return true;
  if (a == null || b == null) return a == null && b == null;
  if (a instanceof Timestamp || b instanceof Timestamp) {
    return a instanceof Timestamp && b instanceof Timestamp && a.isEqual(b);
  }
  if (a instanceof GeoPoint || b instanceof GeoPoint) {
    return a instanceof GeoPoint && b instanceof GeoPoint && a.isEqual(b);
  }
  if (Array.isArray(a) || Array.isArray(b)) {
    return Array.isArray(a) && Array.isArray(b) && a.length === b.length && a.every((x, i) => sameValue(x, b[i]));
  }
  if (typeof a === 'object' && typeof b === 'object') {
    const ka = Object.keys(a as object);
    const kb = Object.keys(b as object);
    return ka.length === kb.length && ka.every((k) => sameValue((a as AdminDoc)[k], (b as AdminDoc)[k]));
  }
  return false;
}

/** The admin-owned fields that differ from the app's current record. */
export function changedFields(fields: Record<string, unknown>, current: AdminDoc | undefined) {
  return Object.fromEntries(Object.entries(fields).filter(([k, v]) => !current || !sameValue(v, current[k])));
}
