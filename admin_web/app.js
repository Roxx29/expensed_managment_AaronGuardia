// Monchi Admin: static page, Firebase JS SDK from Google's CDN. Every write is
// checked by firebase/firestore.rules (only e-mails in `admins` pass).
import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.18.0/firebase-app.js';
import { getAuth, GoogleAuthProvider, onAuthStateChanged, signInWithPopup, signOut } from 'https://www.gstatic.com/firebasejs/12.18.0/firebase-auth.js';
import {
  getFirestore, collection, getDocs, doc, getDoc, setDoc, updateDoc, deleteDoc, serverTimestamp, Timestamp,
} from 'https://www.gstatic.com/firebasejs/12.18.0/firebase-firestore.js';
import { firebaseConfig } from './config.js';

const app = initializeApp(firebaseConfig);
const auth = getAuth(app);
const db = getFirestore(app);
const DAY = 86400000;

// ---------- tiny DOM helper: strings always become text (no HTML injection) ----------
function h(tag, attrs = {}, ...kids) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k.startsWith('on')) el.addEventListener(k.slice(2), v);
    else if (k === 'class') el.className = v;
    else el.setAttribute(k, v === true ? '' : v);
  }
  for (const kid of kids.flat()) if (kid != null && kid !== false) el.append(kid instanceof Node ? kid : String(kid));
  return el;
}
const $app = document.getElementById('app');
const show = (...nodes) => $app.replaceChildren(...nodes);
function toast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg; t.style.display = 'block';
  clearTimeout(toast.timer); toast.timer = setTimeout(() => (t.style.display = 'none'), 3500);
}
const date = (ts) => (ts?.toDate ? ts.toDate() : null);
const fmt = (d) => (d ? d.toLocaleDateString('es', { day: 'numeric', month: 'short', year: 'numeric' }) : '—');
const lower = (s) => String(s || '').trim().toLowerCase();

// ---------- the same rules as lib/domain/premium/gift_premium.dart ----------
const grantActive = (g) => g && (!g.until || date(g.until) > new Date());
function redemptionUntil(r) {
  if (r.days == null) return null;
  return new Date((date(r.redeemedAt) ?? new Date()).getTime() + r.days * DAY);
}
const redemptionActive = (r) => r && !r.revoked && (r.days == null || redemptionUntil(r) > new Date());

// ---------- state ----------
let S = { users: [], grants: {}, redemptions: {}, codes: [], announcement: null, tab: location.hash.slice(1) || 'resumen', q: '' };

async function load() {
  const [u, g, r, c, a] = await Promise.all([
    getDocs(collection(db, 'users')), getDocs(collection(db, 'grants')), getDocs(collection(db, 'redemptions')),
    getDocs(collection(db, 'codes')), getDoc(doc(db, 'config', 'announcement')),
  ]);
  S.users = u.docs.map((d) => ({ uid: d.id, ...d.data() }));
  S.grants = Object.fromEntries(g.docs.map((d) => [d.id, d.data()]));
  S.redemptions = Object.fromEntries(r.docs.map((d) => [d.id, d.data()]));
  S.codes = c.docs.map((d) => ({ id: d.id, ...d.data() }));
  S.announcement = a.exists() ? a.data() : null;
}
function premiumOf(u) {
  const out = [];
  if (u.playPremium) out.push('play');
  if (grantActive(S.grants[lower(u.email)])) out.push('gift');
  if (redemptionActive(S.redemptions[u.uid])) out.push('code');
  return u.blocked ? out.filter((p) => p === 'play') : out;
}
async function act(fn, ok) {
  try { await fn(); await load(); render(); if (ok) toast(ok); return true; } catch (e) { console.error(e); toast('Error: ' + (e.code || e.message)); return false; }
}

// ---------- screens ----------
function login(message) {
  show(h('div', { class: 'center' }, h('div', {},
    h('img', { src: 'logo.png', alt: '' }), h('h2', {}, 'Monchi Admin'),
    message ? h('p', { class: 'muted' }, message) : null,
    h('button', { class: 'btn primary', onclick: () => signInWithPopup(auth, new GoogleAuthProvider()).catch((e) => toast(e.code)) }, 'Entrar con Google'),
  )));
}

const TABS = [['resumen', 'Resumen'], ['usuarios', 'Usuarios'], ['regalos', 'Premium regalado'], ['codigos', 'Códigos'], ['anuncio', 'Anuncio']];
function render() {
  const nav = h('nav', {}, TABS.map(([id, name]) => h('button', { class: S.tab === id ? 'on' : '', onclick: () => { S.tab = id; location.hash = id; render(); } }, name)));
  const body = { resumen, usuarios, regalos, codigos, anuncio }[S.tab]?.() ?? resumen();
  show(
    h('header', {}, h('img', { src: 'logo.png', alt: '' }), h('h1', {}, 'Monchi Admin'),
      h('div', { class: 'who' }, auth.currentUser.email,
        h('button', { class: 'btn', onclick: () => act(() => Promise.resolve(), 'Actualizado') }, 'Actualizar'),
        h('button', { class: 'btn', onclick: () => signOut(auth) }, 'Salir'))),
    nav, h('main', {}, body),
  );
}

function resumen() {
  const now = Date.now();
  const p = S.users.map(premiumOf);
  const stat = (n, label) => h('div', { class: 'stat' }, h('b', {}, n), h('span', {}, label));
  const months = [...Array(6)].map((_, i) => { const d = new Date(); d.setDate(1); d.setMonth(d.getMonth() - 5 + i); return d; });
  const perMonth = months.map((m) => S.users.filter((u) => { const c = date(u.createdAt); return c && c.getFullYear() === m.getFullYear() && c.getMonth() === m.getMonth(); }).length);
  const max = Math.max(1, ...perMonth);
  const builds = {};
  for (const u of S.users) builds[u.appBuild || '?'] = (builds[u.appBuild || '?'] || 0) + 1;
  return [
    h('div', { class: 'grid' },
      stat(S.users.length, 'Usuarios con cuenta'),
      stat(S.users.filter((u) => (date(u.lastSeen)?.getTime() ?? 0) > now - 30 * DAY).length, 'Activos (30 días)'),
      stat(p.filter((x) => x.length).length, 'Con Premium'),
      stat(p.filter((x) => x.includes('play')).length, 'Pagan en Google Play (según la app)'),
      stat(p.filter((x) => x.includes('gift')).length, 'Premium regalado'),
      stat(p.filter((x) => x.includes('code')).length, 'Con código'),
      stat(S.users.filter((u) => u.blocked).length, 'Bloqueados'),
    ),
    h('div', { class: 'card', style: 'margin-top:16px' }, h('h2', {}, 'Altas por mes'),
      h('div', { class: 'bars' }, months.map((m, i) => h('div', { class: 'bar' },
        h('span', {}, perMonth[i]), h('i', { style: `height:${(perMonth[i] / max) * 100}px` }),
        h('span', {}, m.toLocaleDateString('es', { month: 'short' })))))),
    h('div', { class: 'card' }, h('h2', {}, 'Versión de la app (build)'),
      Object.entries(builds).sort((a, b) => String(b[0]).localeCompare(String(a[0]), undefined, { numeric: true }))
        .map(([b, n]) => h('span', { class: 'chip' }, `build ${b}: ${n}`))),
    h('p', { class: 'muted' }, 'Solo aparecen quienes iniciaron sesión con Google en la app. Monchi no registra a los demás (privacidad).'),
  ];
}

function askDays() {
  const v = prompt('¿Cuántos días de Premium? Deja vacío para siempre.', '30');
  if (v === null) return undefined;
  if (v.trim() === '') return null;
  const n = parseInt(v, 10);
  return n > 0 ? n : undefined;
}
const giveGrant = (email, days, note = '') => setDoc(doc(db, 'grants', lower(email)), {
  until: days ? Timestamp.fromMillis(Date.now() + days * DAY) : null,
  note, createdAt: serverTimestamp(), by: auth.currentUser.email,
});

function usuarios() {
  const q = S.q.toLowerCase();
  const list = S.users.filter((u) => !q || lower(u.email).includes(q) || lower(u.name).includes(q))
    .sort((a, b) => (date(b.lastSeen)?.getTime() ?? 0) - (date(a.lastSeen)?.getTime() ?? 0));
  const search = h('input', { placeholder: 'Buscar por correo o nombre', value: S.q, oninput: (e) => { S.q = e.target.value; const pos = e.target.selectionStart; render(); const i = $app.querySelector('main input'); i.focus(); i.setSelectionRange(pos, pos); } });
  return h('div', { class: 'card' },
    h('div', { class: 'row', style: 'justify-content:space-between;margin-bottom:10px' }, search,
      h('button', { class: 'btn', onclick: exportCsv }, 'Exportar CSV')),
    h('div', { class: 'scroll' }, h('table', {},
      h('tr', {}, ['Usuario', 'Alta', 'Última vez', 'Build', 'Premium', ''].map((t) => h('th', {}, t))),
      list.map((u) => {
        const p = premiumOf(u);
        const email = lower(u.email);
        return h('tr', {},
          h('td', {}, h('div', {}, u.name || '—'), h('div', { class: 'muted' }, u.email)),
          h('td', {}, fmt(date(u.createdAt))), h('td', {}, fmt(date(u.lastSeen))), h('td', {}, u.appBuild ?? '—'),
          h('td', {}, p.map((x) => h('span', { class: 'chip ' + x }, { play: 'Google Play', gift: 'Regalo', code: 'Código' }[x])),
            u.blocked ? h('span', { class: 'chip blocked' }, 'Bloqueado') : null, !p.length && !u.blocked ? h('span', { class: 'muted' }, 'Gratis') : null),
          h('td', {}, h('div', { class: 'row' },
            S.grants[email] || (S.redemptions[u.uid] && !S.redemptions[u.uid].revoked)
              ? h('button', { class: 'btn', onclick: () => act(async () => {
                  if (S.grants[email]) await deleteDoc(doc(db, 'grants', email));
                  if (S.redemptions[u.uid]) await updateDoc(doc(db, 'redemptions', u.uid), { revoked: true });
                }, 'Premium quitado') }, 'Quitar Premium')
              : h('button', { class: 'btn', onclick: () => { const d = askDays(); if (d !== undefined) act(() => giveGrant(email, d), 'Premium regalado'); } }, 'Regalar Premium'),
            S.redemptions[u.uid]?.revoked
              ? h('button', { class: 'btn', onclick: () => act(() => deleteDoc(doc(db, 'redemptions', u.uid)), 'Puede canjear otro código') }, 'Permitir otro código')
              : null,
            h('button', { class: 'btn', onclick: () => act(() => updateDoc(doc(db, 'users', u.uid), { blocked: !u.blocked }), u.blocked ? 'Desbloqueado' : 'Bloqueado') }, u.blocked ? 'Desbloquear' : 'Bloquear'),
            h('button', { class: 'btn danger', onclick: () => deleteUser(u) }, 'Borrar datos'))));
      }))),
    list.length ? null : h('p', { class: 'muted' }, 'Nadie todavía.'));
}

async function deleteUser(u) {
  if (!confirm(`¿Borrar la copia en la nube y los datos de ${u.email}? No se puede deshacer.`)) return;
  const done = await act(async () => {
    // Cloud backup: metadata + chunks (lib/features/backup/application/cloud_backup.dart).
    for (const c of (await getDocs(collection(db, 'backups', u.uid, 'chunks'))).docs) await deleteDoc(c.ref);
    await deleteDoc(doc(db, 'backups', u.uid));
    if (S.redemptions[u.uid]) await deleteDoc(doc(db, 'redemptions', u.uid));
    if (S.grants[lower(u.email)]) await deleteDoc(doc(db, 'grants', lower(u.email)));
    await deleteDoc(doc(db, 'users', u.uid));
  }, 'Datos borrados');
  if (!done) return;
  alert(`Último paso: borra la cuenta ${u.email} en Firebase › Authentication › Usuarios (se abre ahora).`);
  window.open(`https://console.firebase.google.com/project/${firebaseConfig.projectId}/authentication/users`, '_blank', 'noopener');
}

function exportCsv() {
  const rows = [['email', 'nombre', 'alta', 'ultima_vez', 'build', 'premium', 'bloqueado']]
    .concat(S.users.map((u) => [u.email, u.name ?? '', date(u.createdAt)?.toISOString() ?? '', date(u.lastSeen)?.toISOString() ?? '', u.appBuild ?? '', premiumOf(u).join('+'), u.blocked ? 'si' : 'no']));
  // Leading =+-@ are neutralised so a spreadsheet never runs a cell as a formula.
  const cell = (v) => `"${String(v).replace(/^[=+\-@\t\r]/, "'$&").replace(/"/g, '""')}"`;
  const blob = new Blob(['﻿' + rows.map((r) => r.map(cell).join(',')).join('\r\n')], { type: 'text/csv' });
  h('a', { href: URL.createObjectURL(blob), download: 'monchi_usuarios.csv' }).click();
}

function regalos() {
  const email = h('input', { type: 'email', placeholder: 'correo@gmail.com', required: true });
  const days = h('input', { type: 'number', min: 1, placeholder: 'vacío = para siempre', style: 'width:170px' });
  const note = h('input', { placeholder: 'Nota (opcional)' });
  const list = Object.entries(S.grants).sort((a, b) => (date(b[1].createdAt)?.getTime() ?? 0) - (date(a[1].createdAt)?.getTime() ?? 0));
  return [
    h('div', { class: 'card' }, h('h2', {}, 'Regalar Premium por correo'),
      h('p', { class: 'muted' }, 'Funciona aunque la persona aún no haya entrado: lo recibe al iniciar sesión con ese correo de Google en la app.'),
      h('div', { class: 'row' }, h('label', {}, 'Correo', email), h('label', {}, 'Días', days), h('label', {}, 'Nota', note),
        h('button', { class: 'btn primary', onclick: () => {
          if (!email.checkValidity() || !email.value) return toast('Escribe un correo válido');
          act(() => giveGrant(email.value, parseInt(days.value, 10) || null, note.value.trim()), 'Premium regalado');
        } }, 'Regalar'))),
    h('div', { class: 'card scroll' }, h('table', {},
      h('tr', {}, ['Correo', 'Hasta', 'Nota', 'Dado por', ''].map((t) => h('th', {}, t))),
      list.map(([id, g]) => h('tr', {},
        h('td', {}, id), h('td', {}, g.until ? fmt(date(g.until)) + (grantActive(g) ? '' : ' (vencido)') : 'Para siempre'),
        h('td', {}, g.note || ''), h('td', { class: 'muted' }, g.by || ''),
        h('td', {}, h('button', { class: 'btn danger', onclick: () => act(() => deleteDoc(doc(db, 'grants', id)), 'Regalo quitado') }, 'Quitar'))))),
      list.length ? null : h('p', { class: 'muted' }, 'No hay regalos.')),
  ];
}

function randomCode() {
  const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const r = crypto.getRandomValues(new Uint32Array(8));
  return 'MONCHI-' + [...r].map((n) => abc[n % abc.length]).join('');
}
function codigos() {
  const code = h('input', { value: randomCode(), style: 'width:200px;text-transform:uppercase' });
  const days = h('input', { type: 'number', min: 1, value: 30, style: 'width:110px' });
  const uses = h('input', { type: 'number', min: 1, value: 1, style: 'width:90px' });
  const expires = h('input', { type: 'date' });
  const create = () => act(async () => {
    const id = code.value.trim().toUpperCase();
    if (!/^[A-Z0-9-]{4,32}$/.test(id)) throw new Error('El código solo admite letras, números y guiones (4 a 32).');
    if ((await getDoc(doc(db, 'codes', id))).exists()) throw new Error('Ese código ya existe.');
    await setDoc(doc(db, 'codes', id), {
      days: parseInt(days.value, 10) || null, maxUses: Math.max(1, parseInt(uses.value, 10) || 1), uses: 0, active: true,
      expiresAt: expires.value ? Timestamp.fromDate(new Date(expires.value + 'T23:59:59')) : null,
      createdAt: serverTimestamp(), by: auth.currentUser.email,
    });
  }, 'Código creado');
  const redeemedBy = (id) => Object.entries(S.redemptions).filter(([, r]) => r.code === id)
    .map(([uid]) => S.users.find((u) => u.uid === uid)?.email ?? uid);
  return [
    h('div', { class: 'card' }, h('h2', {}, 'Nuevo código promocional'),
      h('p', { class: 'muted' }, 'El usuario lo canjea en Más › Monchi Premium › Canjear un código (necesita iniciar sesión con Google). Cada usuario puede canjear un solo código; para darle otro, borra su canje con "Quitar Premium" y luego "Permitir otro código".'),
      h('div', { class: 'row' }, h('label', {}, 'Código', code), h('label', {}, 'Días (vacío = siempre)', days),
        h('label', {}, 'Usos máximos', uses), h('label', {}, 'Vence (opcional)', expires),
        h('button', { class: 'btn primary', onclick: create }, 'Crear'))),
    h('div', { class: 'card scroll' }, h('table', {},
      h('tr', {}, ['Código', 'Premium', 'Usos', 'Vence', 'Canjeado por', ''].map((t) => h('th', {}, t))),
      S.codes.sort((a, b) => (date(b.createdAt)?.getTime() ?? 0) - (date(a.createdAt)?.getTime() ?? 0)).map((c) => h('tr', {},
        h('td', {}, h('code', {}, c.id), c.active ? null : h('span', { class: 'chip blocked' }, 'Desactivado')),
        h('td', {}, c.days ? `${c.days} días` : 'Para siempre'), h('td', {}, `${c.uses} / ${c.maxUses}`),
        h('td', {}, fmt(date(c.expiresAt))), h('td', { class: 'muted' }, redeemedBy(c.id).join(', ')),
        h('td', {}, h('div', { class: 'row' },
          h('button', { class: 'btn', onclick: () => { navigator.clipboard?.writeText(c.id); toast('Copiado'); } }, 'Copiar'),
          h('button', { class: 'btn', onclick: () => act(() => updateDoc(doc(db, 'codes', c.id), { active: !c.active }), c.active ? 'Desactivado' : 'Activado') }, c.active ? 'Desactivar' : 'Activar'),
          h('button', { class: 'btn danger', onclick: () => confirm(`¿Borrar ${c.id}?`) && act(() => deleteDoc(doc(db, 'codes', c.id)), 'Código borrado') }, 'Borrar')))))),
      S.codes.length ? null : h('p', { class: 'muted' }, 'No hay códigos.')),
  ];
}

function anuncio() {
  const a = S.announcement || {};
  const es = h('textarea', { maxlength: 300 }); es.value = a.es || '';
  const en = h('textarea', { maxlength: 300 }); en.value = a.en || '';
  const active = h('input', { type: 'checkbox' }); active.checked = !!a.active;
  return h('div', { class: 'card' }, h('h2', {}, 'Anuncio en Inicio'),
    h('p', { class: 'muted' }, 'Aparece arriba en la pantalla de Inicio de todos los usuarios (se lee al abrir la app). Máximo 300 caracteres.'),
    h('label', {}, 'Español', es), h('br'), h('label', {}, 'Inglés (opcional; si está vacío se muestra el español)', en), h('br'),
    h('div', { class: 'row', style: 'justify-content:space-between' },
      h('label', { style: 'flex-direction:row;align-items:center;gap:8px;font-size:14px;color:inherit' }, active, 'Mostrar el anuncio'),
      h('button', { class: 'btn primary', onclick: () => act(() => setDoc(doc(db, 'config', 'announcement'), {
        es: es.value.trim(), en: en.value.trim(), active: active.checked, updatedAt: serverTimestamp(), by: auth.currentUser.email,
      }), 'Anuncio guardado') }, 'Guardar')));
}

// ---------- start ----------
let denied = '';
onAuthStateChanged(auth, async (user) => {
  if (!user) return login(denied && `${denied} no es administrador.`);
  try {
    if (!(await getDoc(doc(db, 'admins', user.email))).exists()) throw new Error('not admin');
  } catch {
    denied = user.email;
    return signOut(auth); // shows the login screen with the message
  }
  denied = '';
  show(h('div', { class: 'center' }, h('p', { class: 'muted' }, 'Cargando datos…')));
  try { await load(); render(); } catch (e) { console.error(e); show(h('div', { class: 'center' }, h('p', {}, 'No se pudieron leer los datos: ' + (e.code || e.message)))); }
});
