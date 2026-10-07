// node tools/admin_metrics_test.mjs — checks admin_web/metrics.js.
import assert from 'node:assert/strict';
import { computeMetrics, dayKey } from '../admin_web/metrics.js';

const now = new Date(2026, 9, 7, 15); // 7 Oct 2026, local
const d = (y, m, day) => new Date(y, m - 1, day, 10);
const users = [
  // Signed up 20 days ago, came back 10 days later and today; pays monthly.
  { createdAt: d(2026, 9, 17), activeDays: [20260917, 20260927, 20261007], opens: 12, playPremium: true, plan: 'monthly' },
  // Signed up 20 days ago, never came back; lifetime.
  { createdAt: d(2026, 9, 17), activeDays: [20260917], opens: 1, playPremium: true, plan: 'lifetime' },
  // New today, old build (no activeDays/opens), only lastSeen.
  { createdAt: d(2026, 10, 7), lastSeen: d(2026, 10, 7) },
  // Yearly, active 3 days ago; gift too.
  { createdAt: d(2026, 6, 1), activeDays: [20261004], opens: 7, playPremium: true, plan: 'yearly' },
];
const premiumOf = (u) => [...(u.playPremium ? ['play'] : []), ...(u.plan === 'yearly' ? ['gift'] : [])];
const m = computeMetrics(users, { now, premiumOf, prices: { monthly: 2, yearly: 12, lifetime: 30 } });

assert.equal(dayKey(now), 20261007);
assert.equal(m.total, 4);
assert.equal(m.newToday, 1);
assert.equal(m.new30, 3);
assert.equal(m.dau, 2); // user 1 (activeDays) + user 3 (lastSeen)
assert.equal(m.wau, 3);
assert.equal(m.mau, 4);
assert.equal(m.stickiness, 50);
assert.equal(m.opens, 20);
assert.equal(m.avgOpens, 6.7);
assert.equal(m.cohort, 2);
assert.equal(m.retention, 50);
assert.deepEqual(m.plans, { monthly: 1, yearly: 1, lifetime: 1, unknown: 0 });
assert.equal(m.paying, 3);
assert.equal(m.gift, 1);
assert.equal(m.conversion, 75);
assert.equal(m.mrr, 2 + 12 / 12);
assert.equal(m.lifetimeRevenue, 30);
assert.equal(m.newPerDay.length, 30);
assert.equal(m.newPerDay.at(-1).n, 1);
assert.equal(m.activePerDay.at(-1).n, 2);
assert.equal(m.signupsPerMonth.at(-1).n, 1);
assert.equal(m.signupsPerMonth.at(-2).n, 2);
console.log('admin metrics: all checks passed');

// Feature usage and stability.
import { featureUsage, stability } from '../admin_web/metrics.js';
const fu = [
  { appBuild: '32', features: { statistics: 3, receipt_scan: 1, crash: 1, error: 4 } },
  { appBuild: '32', features: { statistics: 1 } },
  { appBuild: '31' }, // old build: no features
];
assert.deepEqual(featureUsage(fu), [
  { key: 'statistics', uses: 4, users: 2 },
  { key: 'receipt_scan', uses: 1, users: 1 },
]);
const st = stability(fu);
assert.equal(st.reporting, 2);
assert.equal(st.crashes, 1);
assert.equal(st.errors, 4);
assert.equal(st.usersWithCrash, 1);
assert.equal(st.crashFree, 50);
assert.deepEqual(st.perBuild, [{ build: '32', users: 2, crashes: 1, errors: 4 }]);
console.log('feature usage + stability: all checks passed');
