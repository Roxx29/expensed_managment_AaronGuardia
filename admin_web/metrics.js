// Metrics for the Resumen tab, computed from the `users/<uid>` rows the app
// writes (lib/features/premium/application/usage_ping.dart). Pure functions:
// tested by tools/admin_metrics_test.mjs (node tools/admin_metrics_test.mjs).
export const DAY = 86400000;

/** yyyymmdd of a local date, the same key the app stores in `activeDays`. */
export const dayKey = (d) => d.getFullYear() * 10000 + (d.getMonth() + 1) * 100 + d.getDate();

const toDate = (ts) => (ts?.toDate ? ts.toDate() : ts instanceof Date ? ts : null);
const startOfDay = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate());

/** Local midnights of the last [n] days, oldest first (today last). */
export function lastDays(n, now = new Date()) {
  const today = startOfDay(now);
  return [...Array(n)].map((_, i) => new Date(today.getFullYear(), today.getMonth(), today.getDate() - (n - 1 - i)));
}

/** Day keys a user was active on: `activeDays` from the app, or the day of
 *  `lastSeen` for builds older than 31 that don't send it. */
export function activeKeys(u) {
  const days = Array.isArray(u.activeDays) ? u.activeDays.filter(Number.isInteger) : [];
  const seen = toDate(u.lastSeen);
  return new Set(seen ? [...days, dayKey(seen)] : days);
}

/**
 * Everything the Resumen tab shows. [premiumOf] returns the user's Premium
 * sources ('play' | 'gift' | 'code'); [prices] = {monthly, yearly, lifetime}.
 */
export function computeMetrics(users, { now = new Date(), premiumOf = () => [], prices = {} } = {}) {
  const today = startOfDay(now);
  const keys = users.map(activeKeys);
  const created = users.map((u) => toDate(u.createdAt));
  const daysAgo = (n) => new Date(today.getFullYear(), today.getMonth(), today.getDate() - n);
  const activeWithin = (n) => {
    const window = new Set(lastDays(n, now).map(dayKey));
    return keys.filter((k) => [...k].some((d) => window.has(d))).length;
  };
  const newSince = (n) => created.filter((c) => c && c >= daysAgo(n - 1)).length;

  // Retention: of the people who signed up 8–37 days ago, how many came back
  // a week or more after signing up.
  let cohort = 0;
  let retained = 0;
  users.forEach((_, i) => {
    const c = created[i];
    if (!c || c > daysAgo(8) || c < daysAgo(37)) return;
    cohort++;
    const weekLater = dayKey(new Date(c.getFullYear(), c.getMonth(), c.getDate() + 7));
    if ([...keys[i]].some((d) => d >= weekLater)) retained++;
  });

  const sources = users.map(premiumOf);
  const paying = users.filter((u, i) => sources[i].includes('play'));
  const plan = (p) => paying.filter((u) => u.plan === p).length;
  const plans = {
    monthly: plan('monthly'), yearly: plan('yearly'), lifetime: plan('lifetime'),
    unknown: paying.filter((u) => !['monthly', 'yearly', 'lifetime'].includes(u.plan)).length,
  };
  const opens = users.reduce((s, u) => s + (Number.isInteger(u.opens) ? u.opens : 0), 0);
  const reporting = users.filter((u) => Number.isInteger(u.opens)).length;
  const dau = activeWithin(1);
  const mau = activeWithin(30);

  const days30 = lastDays(30, now);
  const months = [...Array(12)].map((_, i) => new Date(today.getFullYear(), today.getMonth() - 11 + i, 1));
  return {
    total: users.length,
    newToday: newSince(1), new7: newSince(7), new30: newSince(30),
    dau, wau: activeWithin(7), mau,
    stickiness: mau ? Math.round((dau / mau) * 100) : null,
    opens, avgOpens: reporting ? Math.round((opens / reporting) * 10) / 10 : null,
    retention: cohort ? Math.round((retained / cohort) * 100) : null, cohort,
    premium: sources.filter((s) => s.length).length,
    paying: paying.length, plans,
    gift: sources.filter((s) => s.includes('gift')).length,
    code: sources.filter((s) => s.includes('code')).length,
    conversion: users.length ? Math.round((paying.length / users.length) * 1000) / 10 : null,
    mrr: plans.monthly * (prices.monthly ?? 0) + (plans.yearly * (prices.yearly ?? 0)) / 12,
    lifetimeRevenue: plans.lifetime * (prices.lifetime ?? 0),
    blocked: users.filter((u) => u.blocked).length,
    newPerDay: days30.map((d) => ({ date: d, n: created.filter((c) => c && startOfDay(c).getTime() === d.getTime()).length })),
    activePerDay: days30.map((d) => ({ date: d, n: keys.filter((k) => k.has(dayKey(d))).length })),
    signupsPerMonth: months.map((m) => ({
      date: m,
      n: created.filter((c) => c && c.getFullYear() === m.getFullYear() && c.getMonth() === m.getMonth()).length,
    })),
  };
}

const counts = (u) => (u.features && typeof u.features === 'object' ? u.features : null);

/** Most used features: total uses and how many people used each one,
 *  most people first. `crash`/`error` are stability, not features. */
export function featureUsage(users) {
  const out = {};
  for (const u of users) {
    for (const [key, n] of Object.entries(counts(u) ?? {})) {
      if (key === 'crash' || key === 'error' || !Number.isInteger(n) || n <= 0) continue;
      out[key] ??= { key, uses: 0, users: 0 };
      out[key].uses += n;
      out[key].users++;
    }
  }
  return Object.values(out).sort((a, b) => b.users - a.users || b.uses - a.uses);
}

/** Crashes and errors reported by the app (build 32+), overall and per build. */
export function stability(users) {
  const reporting = users.filter((u) => counts(u));
  const n = (u, k) => (Number.isInteger(counts(u)?.[k]) ? counts(u)[k] : 0);
  const crashed = reporting.filter((u) => n(u, 'crash') > 0);
  const perBuild = {};
  for (const u of reporting) {
    const b = u.appBuild || '?';
    perBuild[b] ??= { build: b, users: 0, crashes: 0, errors: 0 };
    perBuild[b].users++;
    perBuild[b].crashes += n(u, 'crash');
    perBuild[b].errors += n(u, 'error');
  }
  return {
    reporting: reporting.length,
    crashes: reporting.reduce((s, u) => s + n(u, 'crash'), 0),
    errors: reporting.reduce((s, u) => s + n(u, 'error'), 0),
    usersWithCrash: crashed.length,
    crashFree: reporting.length ? Math.round(((reporting.length - crashed.length) / reporting.length) * 1000) / 10 : null,
    perBuild: Object.values(perBuild).sort((a, b) => String(b.build).localeCompare(String(a.build), undefined, { numeric: true })),
  };
}
