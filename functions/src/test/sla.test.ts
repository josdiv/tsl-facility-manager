import assert from 'node:assert/strict';
import { test } from 'node:test';
import { firstRun, nextRun } from '../sla';

// Lagos is UTC+1, so 08:00 in Lagos is 07:00 UTC.
const lagos = (iso: string) => Date.parse(`${iso}+01:00`);
const iso = (ms: number) => new Date(ms + 3600_000).toISOString().slice(0, 16);

test('first run is the start day at the due time, in Lagos time', () => {
  assert.equal(iso(firstRun('daily', lagos('2026-11-17T00:00'), '08:00')), '2026-11-17T08:00');
});

test('a start later in the day than the due time runs the next day', () => {
  const start = lagos('2026-11-17T10:00');
  assert.equal(iso(firstRun('daily', start, '08:00')), '2026-11-18T08:00');
});

test('weekday schedules skip the weekend', () => {
  // Friday 20 November 2026 → Monday 23 November.
  const friday = lagos('2026-11-20T14:00');
  assert.equal(iso(nextRun('weekdays', friday, '14:00', lagos('2026-11-01T00:00'))), '2026-11-23T14:00');
  // Starting on a Saturday waits for Monday.
  assert.equal(iso(firstRun('weekdays', lagos('2026-11-21T00:00'), '09:00')), '2026-11-23T09:00');
});

test('weekend schedules run on Saturday and Sunday only', () => {
  const sunday = lagos('2026-11-22T09:00');
  assert.equal(iso(nextRun('weekends', sunday, '09:00', lagos('2026-11-01T00:00'))), '2026-11-28T09:00');
});

test('weekly and fortnightly add 7 and 14 days', () => {
  const run = lagos('2026-11-17T08:00');
  assert.equal(iso(nextRun('weekly', run, '08:00', run)), '2026-11-24T08:00');
  assert.equal(iso(nextRun('fortnightly', run, '08:00', run)), '2026-12-01T08:00');
});

test('monthly keeps the start date, clamped to short months', () => {
  const start = lagos('2026-01-31T08:00');
  const feb = nextRun('monthly', start, '08:00', start);
  assert.equal(iso(feb), '2026-02-28T08:00');
  // Back to the 31st once the month has one.
  assert.equal(iso(nextRun('monthly', feb, '08:00', start)), '2026-03-31T08:00');
});

test('quarterly, twice a year and yearly', () => {
  const start = lagos('2026-11-17T08:00');
  assert.equal(iso(nextRun('quarterly', start, '08:00', start)), '2027-02-17T08:00');
  assert.equal(iso(nextRun('biannually', start, '08:00', start)), '2027-05-17T08:00');
  assert.equal(iso(nextRun('annually', start, '08:00', start)), '2027-11-17T08:00');
});
