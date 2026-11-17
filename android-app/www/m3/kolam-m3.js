/*! Kolam M3 — Material Design 3 "Android app mode" for Kolam web apps.
 * Inside the Android app (Capacitor shell, Android WebView or the installed PWA on Android) the page gets
 * <html class="k-android k-app"> and follows Material Design 3. In any normal browser nothing changes:
 * the app keeps its Kolam look. Force it for testing with ?app=android or ?app=web (kept for the tab session).
 *
 * Load in <head> (before kolam-m3.css is fine) so the class is set before the first paint:
 *   <script src="https://tgopinath.github.io/kolam-design-system/m3/kolam-m3.js"></script>
 * then call KolamM3.init({...}) once the page is ready. See m3/README.md.
 */
(function (root, factory) {
  const api = factory(root);
  if (typeof module === 'object' && module.exports) module.exports = api;
  else root.KolamM3 = api;
})(typeof window !== 'undefined' ? window : globalThis, function (win) {
  'use strict';
  const VERSION = '1.0.0';
  const doc = win.document;
  const KOLAM_PRIMARY = '#0077b6';
  const MODE_KEY = 'k-app-mode';

  // ------------------------------------------------------------------ colour: sRGB <-> CIELAB / LCh
  // HCT approximation: "tone" is CIELAB L* (exactly what HCT uses, so tone-based contrast holds),
  // hue and chroma come from LCh(ab) instead of CAM16. Good enough for scheme generation.
  const hexToRgb = hex => {
    let h = String(hex).trim().replace('#', '');
    if (h.length === 3) h = h.split('').map(c => c + c).join('');
    const n = parseInt(h, 16);
    return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
  };
  const rgbToHex = rgb => '#' + rgb.map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('');
  const toLin = c => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  const fromLin = c => 255 * (c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055);
  const E = 216 / 24389, K = 24389 / 27, WHITE = [0.95047, 1, 1.08883];
  const fLab = t => (t > E ? Math.cbrt(t) : (K * t + 16) / 116);
  function rgbToLch(rgb) {
    const [r, g, b] = rgb.map(toLin);
    const X = 0.4123908 * r + 0.3575843 * g + 0.1804808 * b;
    const Y = 0.2126390 * r + 0.7151687 * g + 0.0721923 * b;
    const Z = 0.0193308 * r + 0.1191948 * g + 0.9505322 * b;
    const fx = fLab(X / WHITE[0]), fy = fLab(Y / WHITE[1]), fz = fLab(Z / WHITE[2]);
    const L = 116 * fy - 16, a = 500 * (fx - fy), bb = 200 * (fy - fz);
    return { l: L, c: Math.hypot(a, bb), h: ((Math.atan2(bb, a) * 180) / Math.PI + 360) % 360 };
  }
  // Returns linear-light sRGB (may be out of gamut).
  function lchToLin(l, c, h) {
    const a = c * Math.cos((h * Math.PI) / 180), b = c * Math.sin((h * Math.PI) / 180);
    const fy = (l + 16) / 116, fx = fy + a / 500, fz = fy - b / 200;
    const inv = f => (f * f * f > E ? f * f * f : (116 * f - 16) / K);
    const X = inv(fx) * WHITE[0], Y = (l > K * E ? fy * fy * fy : l / K) * WHITE[1], Z = inv(fz) * WHITE[2];
    return [
      3.2409699 * X - 1.5373832 * Y - 0.4986108 * Z,
      -0.9692436 * X + 1.8759675 * Y + 0.0415551 * Z,
      0.0556301 * X - 0.2039770 * Y + 1.0569715 * Z,
    ];
  }
  const inGamut = lin => lin.every(v => v >= -1e-4 && v <= 1 + 1e-4);
  // The colour at a given tone (L*), keeping hue and as much of the wanted chroma as sRGB allows.
  function toneColor(h, c, tone) {
    if (tone >= 100) return '#ffffff';
    if (tone <= 0) return '#000000';
    let lo = 0, hi = c, best = 0;
    if (inGamut(lchToLin(tone, c, h))) best = c;
    else for (let i = 0; i < 24; i++) { const mid = (lo + hi) / 2; if (inGamut(lchToLin(tone, mid, h))) { best = mid; lo = mid; } else hi = mid; }
    return rgbToHex(lchToLin(tone, best, h).map(v => fromLin(Math.max(0, Math.min(1, v)))));
  }
  function luminance(hex) { const [r, g, b] = hexToRgb(hex).map(toLin); return 0.2126 * r + 0.7152 * g + 0.0722 * b; }
  function contrastRatio(a, b) { const x = luminance(a), y = luminance(b); return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05); }

  // A tonal palette: tone(t) -> hex.
  function palette(hue, chroma) {
    const cache = {};
    const fn = t => (cache[t] ??= toneColor(hue, chroma, t));
    fn.hue = hue; fn.chroma = chroma;
    return fn;
  }
  // Key palettes from one source colour ("tonal spot" with fidelity to the brand chroma).
  function palettes(sourceHex) {
    const s = rgbToLch(hexToRgb(sourceHex || KOLAM_PRIMARY));
    const pc = Math.max(s.c, 16); // a grey brand still gets a hint of colour
    const err = rgbToLch(hexToRgb('#b3261e'));
    return {
      primary: palette(s.h, pc),
      secondary: palette(s.h, Math.min(pc / 3, 18)),
      tertiary: palette((s.h + 60) % 360, Math.max(Math.min(pc / 2, 36), 20)),
      neutral: palette(s.h, Math.min(pc / 8, 5)),
      neutralVariant: palette(s.h, Math.min(pc / 4, 10)),
      error: palette(err.h, err.c),
    };
  }

  // Tones per role. Light / dark follow the M3 baseline (on-*-container uses tone 30 in light, per the
  // 2024+ Material Theme Builder); the high-contrast pair is used for data-theme="contrast" / prefers-contrast.
  const accentRoles = (p, n, t) => ({
    [n]: p(t.main), ['on-' + n]: p(t.on), [n + '-container']: p(t.cont), ['on-' + n + '-container']: p(t.onCont),
  });
  const fixedRoles = (p, n) => ({
    [n + '-fixed']: p(90), [n + '-fixed-dim']: p(80), ['on-' + n + '-fixed']: p(10), ['on-' + n + '-fixed-variant']: p(30),
  });
  const TONES = {
    light: { acc: { main: 40, on: 100, cont: 90, onCont: 30 }, err: { main: 40, on: 100, cont: 90, onCont: 30 },
      n: { surf: 98, dim: 87, bright: 98, lowest: 100, low: 96, cont: 94, high: 92, highest: 90, on: 10, inv: 20, invOn: 95 },
      nv: { variant: 90, onVariant: 30, outline: 50, outlineVar: 80 }, invPrimary: 80 },
    dark: { acc: { main: 80, on: 20, cont: 30, onCont: 90 }, err: { main: 80, on: 20, cont: 30, onCont: 90 },
      n: { surf: 6, dim: 6, bright: 24, lowest: 4, low: 10, cont: 12, high: 17, highest: 22, on: 90, inv: 90, invOn: 20 },
      nv: { variant: 30, onVariant: 80, outline: 60, outlineVar: 30 }, invPrimary: 40 },
    lightHigh: { acc: { main: 25, on: 100, cont: 35, onCont: 100 }, err: { main: 25, on: 100, cont: 35, onCont: 100 },
      n: { surf: 98, dim: 87, bright: 98, lowest: 100, low: 96, cont: 94, high: 92, highest: 90, on: 0, inv: 20, invOn: 100 },
      nv: { variant: 90, onVariant: 15, outline: 30, outlineVar: 40 }, invPrimary: 90 },
    darkHigh: { acc: { main: 92, on: 10, cont: 75, onCont: 0 }, err: { main: 92, on: 10, cont: 75, onCont: 0 },
      n: { surf: 6, dim: 6, bright: 30, lowest: 0, low: 12, cont: 16, high: 22, highest: 28, on: 100, inv: 90, invOn: 0 },
      nv: { variant: 30, onVariant: 95, outline: 85, outlineVar: 70 }, invPrimary: 30 },
  };
  function buildScheme(P, t) {
    const N = P.neutral, NV = P.neutralVariant;
    return Object.assign({},
      accentRoles(P.primary, 'primary', t.acc), accentRoles(P.secondary, 'secondary', t.acc),
      accentRoles(P.tertiary, 'tertiary', t.acc), accentRoles(P.error, 'error', t.err),
      fixedRoles(P.primary, 'primary'), fixedRoles(P.secondary, 'secondary'), fixedRoles(P.tertiary, 'tertiary'),
      {
        background: N(t.n.surf), 'on-background': N(t.n.on),
        surface: N(t.n.surf), 'on-surface': N(t.n.on), 'surface-dim': N(t.n.dim), 'surface-bright': N(t.n.bright),
        'surface-container-lowest': N(t.n.lowest), 'surface-container-low': N(t.n.low), 'surface-container': N(t.n.cont),
        'surface-container-high': N(t.n.high), 'surface-container-highest': N(t.n.highest),
        'surface-variant': NV(t.nv.variant), 'on-surface-variant': NV(t.nv.onVariant),
        outline: NV(t.nv.outline), 'outline-variant': NV(t.nv.outlineVar),
        'inverse-surface': N(t.n.inv), 'inverse-on-surface': N(t.n.invOn), 'inverse-primary': P.primary(t.invPrimary),
        'surface-tint': P.primary(t.acc.main), shadow: '#000000', scrim: '#000000',
      });
  }
  function scheme(sourceHex) {
    const P = palettes(sourceHex);
    return { source: sourceHex || KOLAM_PRIMARY, light: buildScheme(P, TONES.light), dark: buildScheme(P, TONES.dark),
      lightHigh: buildScheme(P, TONES.lightHigh), darkHigh: buildScheme(P, TONES.darkHigh), palettes: P };
  }
  // The role pairs that carry text or meaning, with the WCAG ratio each must reach.
  const CHECKS = [
    ['on-primary', 'primary', 4.5], ['on-primary-container', 'primary-container', 4.5],
    ['on-secondary', 'secondary', 4.5], ['on-secondary-container', 'secondary-container', 4.5],
    ['on-tertiary', 'tertiary', 4.5], ['on-tertiary-container', 'tertiary-container', 4.5],
    ['on-error', 'error', 4.5], ['on-error-container', 'error-container', 4.5],
    ['on-surface', 'surface', 4.5], ['on-surface', 'surface-container-highest', 4.5],
    ['on-surface-variant', 'surface', 4.5], ['on-surface-variant', 'surface-container', 4.5],
    ['on-surface-variant', 'surface-container-highest', 4.5], ['primary', 'surface', 4.5],
    ['primary', 'surface-container-high', 4.5], ['secondary', 'surface', 4.5], ['error', 'surface', 4.5],
    ['inverse-on-surface', 'inverse-surface', 4.5], ['inverse-primary', 'inverse-surface', 4.5],
    ['outline', 'surface', 3], ['outline', 'surface-container-highest', 3],
  ];
  function checkContrast(roles) {
    return CHECKS.map(([fg, bg, min]) => { const ratio = contrastRatio(roles[fg], roles[bg]); return { fg, bg, min, ratio: Math.round(ratio * 100) / 100, pass: ratio >= min }; });
  }
  const block = (sel, roles) => `${sel}{${Object.entries(roles).map(([k, v]) => `--md-sys-color-${k}:${v};`).join('')}}`;
  function cssFor(sourceHex, base = 'html.k-android[data-m3-colors]') {
    const s = scheme(sourceHex);
    const notLD = ':not([data-theme="light"]):not([data-theme="contrast"])';
    return [
      block(base, s.light) + `${base}{color-scheme:light}`,
      `@media (prefers-color-scheme: dark){${block(base + notLD, s.dark)}${base + notLD}{color-scheme:dark}}`,
      block(base + '[data-theme="dark"]', s.dark) + `${base}[data-theme="dark"]{color-scheme:dark}`,
      block(base + '[data-theme="contrast"]', s.lightHigh),
      `@media (prefers-contrast: more){${block(base + ':not([data-theme])', s.lightHigh)}}`,
      `@media (prefers-contrast: more) and (prefers-color-scheme: dark){${block(base + notLD, s.darkHigh)}}`,
    ].join('\n');
  }

  // ------------------------------------------------------------------ mode detection
  function detect() {
    if (!doc) return false;
    let forced = null;
    try {
      const m = win.location.search.match(/[?&]app=(android|web)\b/);
      if (m) win.sessionStorage.setItem(MODE_KEY, m[1]);
      forced = win.sessionStorage.getItem(MODE_KEY);
    } catch (e) { /* storage blocked: fall back to the query only */
      const m = win.location.search.match(/[?&]app=(android|web)\b/); forced = m && m[1];
    }
    if (forced === 'android') return true;
    if (forced === 'web') return false;
    const ua = win.navigator.userAgent || '';
    const cap = win.Capacitor?.getPlatform?.() === 'android';
    const webview = /Android/.test(ua) && /; wv\)/.test(ua);
    const mm = q => win.matchMedia?.(q).matches;
    const standalone = /Android/.test(ua) && (mm('(display-mode: standalone)') || mm('(display-mode: fullscreen)'));
    return !!(cap || webview || standalone);
  }
  const isAndroid = detect();
  const html = doc?.documentElement;
  if (isAndroid && html) html.classList.add('k-android', 'k-app');

  function applyColors(hex) {
    if (!doc) return;
    let el = doc.getElementById('k-m3-colors');
    if (!el) { el = doc.createElement('style'); el.id = 'k-m3-colors'; (doc.head || html).appendChild(el); }
    el.textContent = cssFor(hex);
    html.setAttribute('data-m3-colors', '');
    syncSystemBars();
  }

  // ------------------------------------------------------------------ small helpers
  const esc = s => String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const icon = (name, filled) => `<span class="md-icon${filled ? ' md-icon--filled' : ''}" aria-hidden="true">${esc(name)}</span>`;
  const plugins = () => win.Capacitor?.Plugins || {};
  const ready = fn => (doc.readyState === 'loading' ? doc.addEventListener('DOMContentLoaded', fn, { once: true }) : fn());
  const cssVar = name => getComputedStyle(html).getPropertyValue(name).trim();
  const prefersReducedMotion = () => win.matchMedia?.('(prefers-reduced-motion: reduce)').matches;
  const isDarkNow = () => {
    const t = html.getAttribute('data-theme');
    if (t === 'dark') return true;
    if (t === 'light' || t === 'contrast') return false;
    return !!win.matchMedia?.('(prefers-color-scheme: dark)').matches;
  };

  // System bars + theme-color follow the surface colour and light/dark scheme.
  function syncSystemBars() {
    if (!isAndroid || !doc) return;
    const surface = cssVar('--md-sys-color-surface');
    if (surface) {
      let meta = doc.querySelector('meta[name="theme-color"]');
      if (!meta) { meta = doc.createElement('meta'); meta.name = 'theme-color'; doc.head.appendChild(meta); }
      meta.content = surface;
    }
    const style = isDarkNow() ? 'DARK' : 'LIGHT'; // DARK = light icons for a dark background
    const P = plugins();
    try { P.SystemBars?.setStyle?.({ style }); } catch (e) {}
    try { P.StatusBar?.setStyle?.({ style }); if (surface && !P.SystemBars) P.StatusBar?.setBackgroundColor?.({ color: surface }); } catch (e) {}
  }

  function haptic(kind = 'light') {
    if (!isAndroid || state.opts?.haptics === false) return;
    const H = plugins().Haptics;
    try {
      if (H) { if (kind === 'selection') H.selectionChanged?.() ?? H.impact?.({ style: 'LIGHT' }); else H.impact?.({ style: kind === 'heavy' ? 'HEAVY' : kind === 'medium' ? 'MEDIUM' : 'LIGHT' }); }
      else win.navigator.vibrate?.(kind === 'heavy' ? 20 : 8);
    } catch (e) {}
  }

  // Material Symbols Rounded, subset to the icons the app uses (much smaller than the whole font).
  const iconSet = new Set(['arrow_back', 'check', 'close', 'more_vert', 'search']);
  let iconsAll = false;
  function loadIcons(names) {
    if (!doc) return;
    (names || []).forEach(n => n && iconSet.add(String(n).trim()));
    doc.querySelectorAll('.md-icon').forEach(el => { const t = el.textContent.trim(); if (/^[a-z0-9_]+$/.test(t)) iconSet.add(t); });
    const base = 'https://fonts.googleapis.com/css2?family=Material+Symbols+Rounded:opsz,wght,FILL,GRAD@24,400,0..1,0';
    const href = iconsAll ? `${base}&display=block` : `${base}&icon_names=${[...iconSet].sort().join(',')}&display=block`;
    let link = doc.getElementById('k-m3-icons');
    if (link && link.href === href) return;
    const next = doc.createElement('link'); next.rel = 'stylesheet'; next.href = href; next.id = 'k-m3-icons';
    if (link) { next.onload = () => link.remove(); link.removeAttribute('id'); link.after(next); } else doc.head.appendChild(next);
  }

  // ------------------------------------------------------------------ ripple (pressed state)
  const RIPPLE_HOSTS = [
    '.md-button', '.md-icon-button', '.md-fab', '.md-chip', '.md-nav-item', '.md-tab', '.md-segmented > button',
    '.md-list-item[href]', 'button.md-list-item', 'label.md-list-item', 'a.md-card', 'button.md-card', '.md-ripple-host',
    '.k-btn', '.k-iconbtn', '.k-tab', 'a.k-list-item', 'button.k-list-item', 'a.k-card', '.k-bottomnav a', '.md-snackbar__action',
  ].join(',');
  function onPointerDown(e) {
    if (e.button !== 0 || prefersReducedMotion()) return;
    const host = e.target.closest?.(RIPPLE_HOSTS);
    if (!host || host.disabled || host.getAttribute('aria-disabled') === 'true') return;
    // Navigation items ripple inside their active-indicator pill, like Android.
    const surface = host.querySelector(':scope > .md-nav-indicator, :scope > .k-pip') || host;
    if (getComputedStyle(surface).position === 'static') surface.style.position = 'relative';
    const wrap = doc.createElement('span'); wrap.className = 'md-ripple'; wrap.setAttribute('aria-hidden', 'true');
    surface.appendChild(wrap);
    const r = wrap.getBoundingClientRect();
    const d = Math.hypot(r.width, r.height) * 2;
    const x = surface === host ? e.clientX - r.left : r.width / 2, y = surface === host ? e.clientY - r.top : r.height / 2;
    const dot = doc.createElement('span'); dot.className = 'md-ripple__wave';
    dot.style.cssText = `width:${d}px;height:${d}px;left:${x - d / 2}px;top:${y - d / 2}px`;
    wrap.appendChild(dot);
    const born = Date.now();
    const release = () => {
      win.removeEventListener('pointerup', release); win.removeEventListener('pointercancel', release);
      setTimeout(() => { dot.classList.add('md-ripple__wave--out'); setTimeout(() => wrap.remove(), 200); }, Math.max(0, 225 - (Date.now() - born)));
    };
    win.addEventListener('pointerup', release); win.addEventListener('pointercancel', release);
    setTimeout(release, 1500); // safety: never leave a ripple behind
  }

  // ------------------------------------------------------------------ swipe helper
  function onSwipe(el, { left, right, threshold = 70, ignore } = {}) {
    let sx = 0, sy = 0, st = 0;
    el.addEventListener('touchstart', e => { const p = e.touches[0]; sx = p.clientX; sy = p.clientY; st = Date.now(); }, { passive: true });
    el.addEventListener('touchend', e => {
      if (ignore && e.target.closest(ignore)) return;
      const p = e.changedTouches[0], dx = p.clientX - sx, dy = p.clientY - sy;
      if (sx < 24 || sx > win.innerWidth - 24) return; // edge swipes belong to Android's back gesture
      if (Date.now() - st > 600 || Math.abs(dx) < threshold || Math.abs(dy) > Math.abs(dx) * 0.6) return;
      haptic('selection');
      (dx < 0 ? left : right)?.(e);
    }, { passive: true });
  }

  // ------------------------------------------------------------------ state + init
  const state = { opts: null, bar: null, nav: null, headline: null, depth: 0, backOverride: null, activeOverride: null, snackQueue: [], snackEl: null, host: null };
  const noop = () => {};
  const stub = { enabled: false, setTitle: noop, setBack: noop, setActive: noop, setActions: noop, snackbar: () => ({ dismiss: noop }), haptic: noop, goBack: noop, appBar: null, navBar: null };

  function currentKey() { return win.location.hash || win.location.pathname; }
  function matchDest(dests) {
    const here = currentKey();
    const keyOf = d => (d.href || '').replace(/^.*?(#.*)$/, '$1');
    const isHome = k => k === '#/' || k === '#' || k === '/';
    let exact = null, best = null, bestLen = -1;
    dests.forEach(d => {
      const k = keyOf(d); if (!k) return;
      if (here === k || (isHome(k) && ['', '#', '#/', '/'].includes(here))) exact = exact || d;
      else if (!isHome(k) && here.startsWith(k.replace(/\/$/, '') + '/') && k.length > bestLen) { best = d; bestLen = k.length; }
    });
    return exact || best;
  }
  function isRoot() {
    const o = state.opts;
    if (typeof o.isRoot === 'function') return !!o.isRoot();
    const here = currentKey();
    if (o.destinations.length) return o.destinations.some(d => { const k = (d.href || '').replace(/^.*?(#.*)$/, '$1'); return k === here || ((k === '#/' || k === '/') && ['', '#', '#/', '/'].includes(here)); });
    return ['', '#', '#/', '/'].includes(here) || here === (o.home || '');
  }
  function homeHref() { const o = state.opts; return o.home || o.destinations[0]?.href || '#/'; }

  function init(options = {}) {
    if (!isAndroid || !doc) return stub;
    const o = state.opts = Object.assign({
      primary: html.getAttribute('data-m3-primary') || null, title: null, destinations: [], active: null, home: null,
      back: 'auto', onBack: null, isRoot: null, actions: [], appBar: true, appBarVariant: 'small', navBar: null, hide: [],
      ripple: true, haptics: true, edgeToEdge: true, icons: 'auto', mount: null,
    }, options);
    if (o.destinations.length > 5) { console.warn('[KolamM3] A navigation bar holds 3 to 5 destinations; using the first 5.'); o.destinations = o.destinations.slice(0, 5); }
    if (o.navBar === null) o.navBar = o.destinations.length >= 2;
    applyColors(o.primary || KOLAM_PRIMARY);
    iconsAll = o.icons === 'all';
    const ctl = { enabled: true, setTitle, setBack, setActive, setActions, snackbar, haptic, goBack, get appBar() { return state.bar; }, get navBar() { return state.nav; } };
    ready(() => {
      const mount = o.mount ? (typeof o.mount === 'string' ? doc.querySelector(o.mount) : o.mount) : doc.body;
      ensureViewportFit();
      (o.hide || []).forEach(sel => doc.querySelectorAll(sel).forEach(el => el.classList.add('k-web-only')));
      if (o.edgeToEdge) html.classList.add('k-edge');
      if (o.ripple) { html.classList.add('k-ripple'); doc.addEventListener('pointerdown', onPointerDown, { passive: true }); }
      if (o.appBar) buildAppBar(mount);
      if (o.navBar && o.destinations.length) buildNavBar(mount);
      const host = state.host = doc.createElement('div'); host.className = 'md-snackbar-host'; host.setAttribute('aria-live', 'polite'); host.setAttribute('aria-atomic', 'true');
      doc.body.appendChild(host);
      loadIcons([...o.destinations.map(d => d.icon), ...o.actions.map(a => a.icon), ...(Array.isArray(o.icons) ? o.icons : [])]);
      win.addEventListener('hashchange', onRoute); win.addEventListener('popstate', onRoute);
      onRoute(true);
      wireBackButton();
      syncSystemBars();
      win.matchMedia?.('(prefers-color-scheme: dark)').addEventListener?.('change', syncSystemBars);
      new MutationObserver(() => requestAnimationFrame(syncSystemBars)).observe(html, { attributes: true, attributeFilter: ['data-theme'] });
    });
    return ctl;
  }

  function ensureViewportFit() {
    let vp = doc.querySelector('meta[name="viewport"]');
    if (!vp) { vp = doc.createElement('meta'); vp.name = 'viewport'; vp.content = 'width=device-width, initial-scale=1'; doc.head.appendChild(vp); }
    if (!/viewport-fit/.test(vp.content)) vp.content += ', viewport-fit=cover';
  }

  // Top app bar: small (default), center, medium or large. Medium/large show a big headline that
  // scrolls away; the title moves into the bar once it has gone.
  function buildAppBar(mount) {
    const o = state.opts, v = o.appBarVariant;
    const bar = state.bar = doc.createElement('header');
    bar.className = `md-top-app-bar md-top-app-bar--${v}`;
    const title = state.title ?? o.title ?? doc.title;
    bar.innerHTML = `<button type="button" class="md-icon-button md-top-app-bar__nav" aria-label="${esc(o.backLabel || 'Back')}" hidden>${icon('arrow_back')}</button>
      <h1 class="md-top-app-bar__title"${v === 'medium' || v === 'large' ? ' aria-hidden="true"' : ''}>${esc(title)}</h1>
      <div class="md-top-app-bar__actions"></div>`;
    mount.prepend(bar);
    if (v === 'medium' || v === 'large') {
      const hl = state.headline = doc.createElement('h1');
      hl.className = `md-top-app-bar-headline md-top-app-bar-headline--${v}`; hl.textContent = title;
      bar.after(hl);
    }
    html.classList.add('k-has-appbar');
    bar.querySelector('.md-top-app-bar__nav').addEventListener('click', () => goBack('arrow'));
    setActions(state.actions || o.actions);
    const onScroll = () => {
      const y = win.scrollY;
      bar.classList.toggle('md-scrolled', y > 0);
      if (state.headline) bar.classList.toggle('md-collapsed', y > state.headline.offsetHeight - 8);
    };
    win.addEventListener('scroll', onScroll, { passive: true }); onScroll();
  }
  function setActions(list = []) {
    state.actions = list;
    if (!state.bar) return;
    const box = state.bar.querySelector('.md-top-app-bar__actions');
    box.innerHTML = '';
    list.slice(0, 3).forEach(a => {
      const el = doc.createElement(a.href ? 'a' : 'button');
      if (a.href) el.href = a.href; else el.type = 'button';
      el.className = 'md-icon-button'; if (a.id) el.id = a.id;
      el.setAttribute('aria-label', a.label || a.icon);
      el.innerHTML = a.text ? `<span class="md-icon-button__text"${a.lang ? ` lang="${esc(a.lang)}"` : ''}>${esc(a.text)}</span>` : icon(a.icon);
      if (a.onClick) el.addEventListener('click', e => a.onClick(e, el));
      box.appendChild(el);
    });
    loadIcons(list.map(a => a.icon));
  }
  function setTitle(t) {
    state.title = t;
    if (state.bar) state.bar.querySelector('.md-top-app-bar__title').textContent = t;
    if (state.headline) state.headline.textContent = t;
  }
  // true / false forces the arrow; a string is where Up goes when there is no history; null = automatic.
  function setBack(v) { state.backOverride = v; updateBack(); }
  function updateBack() {
    if (!state.bar) return;
    const o = state.opts, v = state.backOverride;
    let show = o.back === false ? false : v === null || v === undefined ? !isRoot() : !!v;
    state.bar.querySelector('.md-top-app-bar__nav').hidden = !show;
    html.classList.toggle('k-root', !show);
  }

  function buildNavBar(mount) {
    const o = state.opts;
    const nav = state.nav = doc.createElement('nav');
    nav.className = 'md-navigation-bar'; nav.setAttribute('aria-label', o.navLabel || 'Main');
    o.destinations.forEach(d => {
      const el = doc.createElement(d.href ? 'a' : 'button');
      if (d.href) el.href = d.href; else el.type = 'button';
      el.className = 'md-nav-item'; el.dataset.dest = d.id;
      el.innerHTML = `<span class="md-nav-indicator">${icon(d.icon)}${d.badge ? `<span class="md-badge md-badge--large">${esc(d.badge)}</span>` : ''}</span><span class="md-nav-label">${esc(d.label)}</span>`;
      el.addEventListener('click', e => {
        haptic('selection');
        if (el.getAttribute('aria-current') === 'page') { // re-selecting a destination scrolls it to the top
          if (d.href && currentKey() === (d.href.replace(/^.*?(#.*)$/, '$1'))) { e.preventDefault(); win.scrollTo({ top: 0, behavior: prefersReducedMotion() ? 'auto' : 'smooth' }); }
        }
        d.onSelect?.(d, e);
        if (!d.href) setActive(d.id);
      });
      nav.appendChild(el);
    });
    mount.appendChild(nav);
    html.classList.add('k-has-navbar');
  }
  function setActive(id) { state.activeOverride = id; paintActive(); }
  function paintActive() {
    if (!state.nav) return;
    const o = state.opts;
    const id = state.activeOverride ?? o.active ?? matchDest(o.destinations)?.id;
    state.nav.querySelectorAll('.md-nav-item').forEach(el => {
      const on = el.dataset.dest === id;
      if (on) el.setAttribute('aria-current', 'page'); else el.removeAttribute('aria-current');
      el.querySelector('.md-icon')?.classList.toggle('md-icon--filled', on);
    });
  }
  // A small stack of visited screens tells Up whether "back" stays inside the app.
  const stack = [];
  function onRoute(first) {
    const k = currentKey();
    if (stack[stack.length - 2] === k) stack.pop(); else if (stack[stack.length - 1] !== k) stack.push(k);
    state.depth = stack.length - 1;
    state.activeOverride = null;
    if (first !== true) state.backOverride = null;
    paintActive(); updateBack();
  }

  // Up (the arrow) and Android Back share one path. Order: an open dialog or sheet closes; then the
  // app's onBack / a cancelable "k-m3:back" event; then back a screen; other top destinations return
  // to the first one; Back on the first destination leaves the app.
  function goBack(source = 'api') {
    const o = state.opts;
    if (source === 'system') {
      const dlg = [...doc.querySelectorAll('dialog[open]')].pop();
      if (dlg) { dlg.close?.('back'); return; }
      const sheet = doc.querySelector('[data-m3-back-closes]:not([hidden])');
      if (sheet) { sheet.dispatchEvent(new CustomEvent('k-m3:close', { bubbles: true })); return; }
    }
    const ev = new CustomEvent('k-m3:back', { cancelable: true, detail: { source, root: isRoot() } });
    if (!win.dispatchEvent(ev)) return;
    if (typeof o.onBack === 'function' && o.onBack({ source, root: isRoot() }) === true) return;
    if (typeof o.back === 'function') { o.back({ source, root: isRoot() }); return; }
    const up = typeof state.backOverride === 'string' ? state.backOverride : null;
    if (!isRoot() || (source === 'arrow')) {
      if (o.back === 'history' || state.depth > 0) win.history.back();
      else win.location.href = up || homeHref();
      return;
    }
    const first = o.destinations[0];
    if (first && matchDest(o.destinations) !== first) { win.location.href = first.href || '#/'; return; }
    if (source === 'system') plugins().App?.exitApp?.();
  }
  function wireBackButton() {
    const App = plugins().App;
    if (!App?.addListener) return;
    try { App.addListener('backButton', () => goBack('system')); } catch (e) {}
  }

  // ------------------------------------------------------------------ snackbar
  function snackbar(text, { action, onAction, duration, closable = false } = {}) {
    if (!state.host) return { dismiss: noop };
    let done = false;
    const item = { text, action, onAction, duration: duration ?? (action ? 6000 : 4000), closable, dismiss: () => { done = true; item.el && hideSnack(item); } };
    state.snackQueue.push(item);
    if (state.snackQueue.length === 1) showSnack(item);
    return { dismiss: () => { if (!done) item.dismiss(); } };
  }
  function showSnack(item) {
    const el = item.el = doc.createElement('div');
    el.className = 'md-snackbar'; el.setAttribute('role', 'status');
    el.innerHTML = `<span class="md-snackbar__text">${esc(item.text)}</span>${item.action ? `<button type="button" class="md-snackbar__action">${esc(item.action)}</button>` : ''}${item.closable ? `<button type="button" class="md-icon-button md-snackbar__close" aria-label="Close">${icon('close')}</button>` : ''}`;
    el.querySelector('.md-snackbar__action')?.addEventListener('click', () => { item.onAction?.(); hideSnack(item); });
    el.querySelector('.md-snackbar__close')?.addEventListener('click', () => hideSnack(item));
    state.host.appendChild(el);
    item.timer = setTimeout(() => hideSnack(item), item.duration);
  }
  function hideSnack(item) {
    clearTimeout(item.timer);
    if (!item.el || item.el.classList.contains('md-snackbar--out')) return;
    item.el.classList.add('md-snackbar--out');
    setTimeout(() => {
      item.el.remove();
      state.snackQueue.shift();
      if (state.snackQueue[0]) showSnack(state.snackQueue[0]);
    }, prefersReducedMotion() ? 0 : 150);
  }

  function setMode(mode) { // 'android' | 'web' | null (automatic); reloads the page
    try { mode ? win.sessionStorage.setItem(MODE_KEY, mode) : win.sessionStorage.removeItem(MODE_KEY); } catch (e) {}
    const u = new URL(win.location.href); u.searchParams.delete('app'); win.location.replace(u.toString());
  }

  // Colours can be applied before the first paint with <html data-m3-primary="#hex">.
  if (isAndroid && html && html.getAttribute('data-m3-primary')) applyColors(html.getAttribute('data-m3-primary'));

  return {
    version: VERSION, isAndroid, init, detect, setMode, applyColors, cssFor, scheme, palettes, checkContrast,
    contrastRatio, toneColor, rgbToLch: hex => rgbToLch(hexToRgb(hex)), icon, loadIcons, haptic, onSwipe,
    snackbar: (t, o) => snackbar(t, o), back: () => goBack('system'), KOLAM_PRIMARY,
  };
});
