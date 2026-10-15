/* Documentation illustration. No app, camera, Keychain or authentication access.
 * Fusion geometry and spring sampled from helpers/faceid-hud.swift.
 * URLs are shareable: ?scene=lock&time=1.5&export=1&notch=0&outcome=failure
 */
const params = new URLSearchParams(location.search);
const scenes = {
  sudo: 'Fusion opens from the camera notch, scans, confirms the match and folds away. Click the animation to show the password fallback.',
  lock: 'Optional unlock for an already logged-in, locked session. This illustration uses a fictional account; it does not unlock your Mac.',
  onboarding: 'Guided enrollment, with camera access and local face registration. No camera is accessed by this preview.',
  settings: 'The current main window: face registration, sudo status, optional lock-screen unlock and recognition preferences.',
  setup: 'The lock-screen setup sheet after camera and Accessibility approval. Its password field is an illustration and accepts no input.',
  choice: 'The optional authentication choice panel before a sudo scan. These buttons are visual illustrations.'
};
let scene = Object.hasOwn(scenes, params.get('scene')) ? params.get('scene') : 'sudo';
let outcome = params.get('outcome') === 'failure' ? 'failure' : 'success';
let hasNotch = params.get('notch') !== '0';
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const fixedTime = params.has('time');
let playing = !fixedTime && !reducedMotion;
let elapsed = fixedTime ? Math.max(0, Math.min(6, Number(params.get('time')) || 0)) : 1.5;
let started = performance.now() - elapsed * 1000;
const el = id => document.getElementById(id);
if (params.get('export') === '1') document.body.classList.add('export');
const iconPaths = {
  check: '<circle cx="12" cy="12" r="9"/><path d="m8 12 3 3 5-6"/>',
  camera: '<rect x="3" y="6" width="18" height="14" rx="3"/><path d="m8 6 2-3h4l2 3"/><circle cx="12" cy="13" r="3"/>',
  move: '<path d="M3 12h18M7 8l-4 4 4 4m10-8 4 4-4 4"/>',
  shield: '<path d="m12 2 8 3v7c0 5-8 10-8 10S4 17 4 12V5Z"/><path d="m8 12 3 3 5-6"/>',
  person: '<circle cx="12" cy="8" r="4"/><path d="M4 22v-3c0-8 16-8 16 0v3"/>',
  lock: '<rect x="5" y="10" width="14" height="12" rx="3"/><path d="M8 10V6a4 4 0 0 1 8 0v4"/>'
};
function icon(name) { return `<svg class="svg-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${iconPaths[name]}</svg>`; }
function titlebar(title) { return `<div class="titlebar"><span class="traffic"><i></i><i></i><i></i></span>${title}</div>`; }
function windowHTML(name, title, content) { return `<div class="window ${name}-window">${titlebar(title)}${content}</div>`; }
function terminal() { return windowHTML('terminal', 'Terminal', `<div class="terminal-body"><span class="dim">Last login: Wednesday at 09:41</span><br><span class="prompt">demo@Mac ~ %</span> sudo -k &amp;&amp; sudo true<br><span id="terminal-complete" class="completed"><span class="prompt">demo@Mac ~ %</span> <span class="cursor"></span></span></div>`); }
function settings() {
  return windowHTML('settings', 'Mugshot', `<div class="app-header"><img src="../../assets/logo.png" alt=""><div><h2>Mugshot</h2><p>Unlock with face recognition</p></div></div>
    <div class="status-banner">${icon('check')}<div><b>Ready</b><p>sudo unlocks with your face.</p></div><button class="native-button" tabindex="-1">Test</button></div>
    <div class="sections">
      <section class="section"><h3>Your Face</h3><div class="row"><span class="green">${icon('check')} Face registered</span><button class="native-button" tabindex="-1">Re-enroll…</button></div><div class="secondary-row"><span class="link">Add an appearance…</span><span style="color:var(--muted)">glasses, a beard, evening light</span></div></section>
      <section class="section"><h3>Terminal (sudo)</h3><div class="row"><span class="green">${icon('check')} Enabled for sudo</span><button class="native-button" tabindex="-1">Disable</button></div><p>Your password always stays as a fallback.</p></section>
      <section class="section"><h3>Lock Screen</h3><div class="row"><span class="green">${icon('lock')} Face unlock enabled</span><button class="native-button" tabindex="-1">Disable</button></div><p>Mugshot types your saved password after recognizing you. Unavailable for FileVault and after a restart.</p></section>
      <section class="section"><h3>Behavior</h3><div class="toggle-row">Choice panel (Face ID / Fingerprint)<span class="switch off"></span></div><div class="toggle-row">Animated capsule (Dynamic Island)<span class="switch"></span></div><div class="segment"><span>Lenient</span><span class="selected">Balanced</span><span>Strict</span></div><p>The recommended setting.</p></section>
    </div><div class="app-footer"><span class="link">Copy diagnostics</span><span class="link">Uninstall Mugshot…</span></div>`);
}
function buildScene() {
  el('desktop').classList.toggle('locked', scene === 'lock');
  el('desktop').classList.toggle('no-notch', !hasNotch);
  el('menu-app').textContent = scene === 'sudo' || scene === 'choice' ? 'Terminal' : 'Mugshot';
  let html = '';
  if (scene === 'sudo') html = terminal();
  if (scene === 'lock') html = `<div class="lock-date">Wednesday, October 14<div class="lock-time">9:41</div></div><div class="lock-profile"><div class="avatar">${icon('person')}</div><b>Demo</b><div id="lock-password" class="lock-password">Enter password</div><p id="lock-message">Touch ID or enter password</p></div>`;
  if (scene === 'settings') html = settings();
  if (scene === 'onboarding') html = windowHTML('onboarding', 'Mugshot', `<div class="onboarding-content"><img src="../../assets/logo.png" alt="Mugshot"><h2>Set Up Face ID</h2><p>We'll register your face to unlock sudo.<br>It only takes a few seconds.</p><div class="tips"><div>${icon('camera')}Face the webcam in good lighting.</div><div>${icon('move')}Move your head slightly during capture.</div><div>${icon('shield')}Everything stays on your Mac.</div></div><button class="primary" tabindex="-1">Start</button></div>`);
  if (scene === 'choice') html = terminal() + `<div class="window choice-window"><div class="choice-content"><img src="../../assets/readme/faceid-glyph.png" alt=""><h2>Authentication required</h2><p>sudo wants to verify your identity</p><button class="primary" tabindex="-1">Use Face ID</button><button class="native-button" tabindex="-1">Use fingerprint</button><button class="native-button" tabindex="-1">Enter password</button></div></div>`;
  if (scene === 'setup') html = windowHTML('setup', 'Mugshot', `<div class="setup-content"><h2>Set up lock-screen unlock</h2><p>Grant the permissions once. Mugshot detects each approval and continues automatically.</p><div class="checkrow green">${icon('check')}Camera access</div><div class="checkrow green">${icon('check')}Allow…</div><div class="checkrow" style="color:var(--muted)">○ &nbsp;Mac login password</div><hr><p>Your Mac login password is kept in this Mac's Keychain so Mugshot can type it into the lock screen after recognizing you.</p><div class="mock-field">Mac login password</div><div class="setup-actions"><button class="native-button" tabindex="-1">Set up later</button><button class="primary" tabindex="-1">Enable</button></div></div>`);
  el('scene-content').innerHTML = html;
  el('scene-caption').textContent = scenes[scene];
  for (const button of document.querySelectorAll('[data-scene]')) button.setAttribute('aria-pressed', String(button.dataset.scene === scene));
}
function spring(t, duration = .62) {
  if (t <= 0) return 0;
  if (t >= duration) return 1;
  const time = t / duration * .62;
  return 1 - Math.exp(-13.5 * time) * (Math.cos(5.27 * time) + 13.5 / 5.27 * Math.sin(5.27 * time));
}
function clamp(x) { return Math.max(0, Math.min(1, x)); }
function mix(a, b, x) { return a + (b - a) * x; }
function silhouette(width, bodyHeight) {
  const left = 166 - width / 2, right = 166 + width / 2;
  if (!hasNotch) {
    const radius = Math.min(30, bodyHeight / 2), top = 0, bottom = bodyHeight;
    return `M${left + radius},${top}H${right - radius}Q${right},${top} ${right},${radius}V${bottom - radius}Q${right},${bottom} ${right - radius},${bottom}H${left + radius}Q${left},${bottom} ${left},${bottom - radius}V${radius}Q${left},${top} ${left + radius},${top}Z`;
  }
  const bottom = 32 + bodyHeight, radius = Math.min(bottom / 2, 12 + 18 * clamp(bodyHeight / 96));
  return `M${left},0H${right}V${bottom - radius}Q${right},${bottom} ${right - radius},${bottom}H${left + radius}Q${left},${bottom} ${left},${bottom - radius}Z`;
}
function render(time) {
  const animated = scene === 'sudo' || scene === 'lock';
  const closedWidth = hasNotch ? 240 : 112, closedHeight = hasNotch ? 0 : 16;
  const open = animated ? spring(time - .45) : 0;
  const success = animated && time >= 3.15;
  const isFailure = success && outcome === 'failure';
  const compact = success && !isFailure ? spring(time - 3.15, .46) : 0;
  const close = animated ? spring(time - 4.3, .46) : 0;
  let width = mix(closedWidth, 296, open), height = mix(closedHeight, 112, open);
  width = mix(width, Math.max(closedWidth + 56, 268), compact);
  height = mix(height, 90, compact);
  width = mix(width, closedWidth, close); height = mix(height, closedHeight, close);
  el('island-path').setAttribute('d', silhouette(width, height));
  el('island-content').style.opacity = animated ? clamp((time - .57) / .24) * (1 - clamp((time - 4.3) / .18)) : 0;
  el('island-content').style.transform = `translateY(${mix(-9, 0, open) - 11 * compact - (hasNotch ? 0 : 32)}px)`;
  el('island-path').style.opacity = hasNotch ? 1 : open * (1 - close);
  el('camera-light').style.opacity = animated && time >= .45 && !success ? 1 : 0;
  el('camera-light').style.display = hasNotch ? '' : 'none';
  el('face-glyph').style.opacity = success ? 1 - clamp((time - 3.15) / .18) : .89 + .11 * Math.cos(time / 1.1 * Math.PI);
  el('scanline').style.opacity = success ? 0 : 1;
  el('scanline').style.top = `${10 + 44 * (.5 - .5 * Math.cos((time - .45) / 1.55 * Math.PI))}px`;
  el('island-title').textContent = success ? (isFailure ? 'Password' : 'Recognized') : 'Face ID';
  el('island-detail').querySelector('span').textContent = success ? (isFailure ? 'Face not recognized' : 'Access granted') : 'Looking for your face';
  const color = isFailure ? '#e5bc82' : '#86e88a';
  el('result-glyph').style.color = color;
  el('island-detail').style.color = success ? color : '#929292';
  el('island-detail').querySelector('i').style.background = color;
  el('check-circle').style.display = isFailure ? 'none' : '';
  el('check-mark').style.display = isFailure ? 'none' : '';
  el('lock-mark').style.display = isFailure ? 'block' : 'none';
  el('check-circle').style.strokeDashoffset = String(1 - (success ? clamp((time - 3.15) / .34) : 0));
  el('check-mark').style.strokeDashoffset = String(1 - (success ? clamp((time - 3.31) / .25) : 0));
  el('lock-mark').style.strokeDashoffset = String(1 - (isFailure ? clamp((time - 3.15) / .28) : 0));
  el('icon-box').style.transform = isFailure ? `translateX(${Math.sin((time - 3.15) * 65) * 3 * (1 - clamp((time - 3.15) / .36))}px)` : '';
  if (el('terminal-complete')) el('terminal-complete').style.opacity = success && !isFailure ? 1 : 0;
  if (el('lock-message')) el('lock-message').textContent = success && !isFailure ? 'Recognized · unlocking session' : 'Touch ID or enter password';
  if (el('lock-password')) el('lock-password').textContent = success && !isFailure ? '••••••••' : 'Enter password';
  el('pause').textContent = playing ? 'Pause' : 'Play';
}
function updateURL() {
  const url = new URL(location.href);
  url.searchParams.set('scene', scene);
  url.searchParams.set('outcome', outcome);
  url.searchParams.set('notch', hasNotch ? '1' : '0');
  if (!playing) url.searchParams.set('time', elapsed.toFixed(2)); else url.searchParams.delete('time');
  history.replaceState({}, '', url);
}
function replay() { playing = true; elapsed = 0; started = performance.now(); updateURL(); }
for (const button of document.querySelectorAll('[data-scene]')) button.addEventListener('click', () => {
  scene = button.dataset.scene; buildScene(); render(elapsed); updateURL();
});
el('replay').onclick = replay;
el('pause').onclick = () => { playing = !playing; started = performance.now() - elapsed * 1000; render(elapsed); updateURL(); };
el('time').oninput = () => { playing = false; elapsed = Math.max(0, Math.min(6, Number(el('time').value) || 0)); render(elapsed); updateURL(); };
el('outcome').value = outcome;
el('outcome').onchange = () => { outcome = el('outcome').value; render(elapsed); updateURL(); };
el('notch').checked = hasNotch;
el('notch').onchange = () => { hasNotch = el('notch').checked; buildScene(); render(elapsed); updateURL(); };
document.querySelector('.island').onclick = () => { if (scene !== 'sudo' && scene !== 'lock') return; outcome = 'failure'; el('outcome').value = outcome; elapsed = 3.15; started = performance.now() - elapsed * 1000; render(elapsed); updateURL(); };
new ResizeObserver(entries => {
  if (!document.body.classList.contains('export')) el('desktop').style.setProperty('--scene-scale', String(entries[0].contentRect.width / 1200));
}).observe(document.querySelector('.stage-wrap'));
buildScene(); render(elapsed);
el('time').value = elapsed.toFixed(2);
document.body.dataset.ready = 'true';
function animate(now) {
  if (playing) { elapsed = ((now - started) / 1000) % 6; render(elapsed); el('time').value = elapsed.toFixed(2); }
  requestAnimationFrame(animate);
}
requestAnimationFrame(animate);
