;;;; interface/web.lisp — Hunchentoot operator console (Phase 11)
;;;;
;;;; Optional web layer. Load via (ql:quickload :automa-gp/web).
;;;; All reasoning delegates to WEB-API-HANDLE → core/REPL.

(defpackage #:automa-gp/web
  (:use #:cl #:automa-gp)
  (:export #:*default-web-port*
           #:*web-acceptor*
           #:start-web
           #:stop-web
           #:web-running-p
           #:web-url
           #:gp-start-web
           #:gp-stop-web))

(in-package #:automa-gp/web)

(defparameter *default-web-port* 47391
  "Default local port (uncommon; avoids 3000/8080).")

(defvar *web-acceptor* nil
  "Current Hunchentoot acceptor, or NIL.")

(defun web-running-p ()
  (and *web-acceptor* (hunchentoot:started-p *web-acceptor*)))

(defun web-url (&optional (acceptor *web-acceptor*))
  (when acceptor
    (format nil "http://127.0.0.1:~A/" (hunchentoot:acceptor-port acceptor))))

(defun %console-html ()
  "Single-page operator console — inspect/control only, no chatbot."
  "<!DOCTYPE html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\"/>
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"/>
<title>AUTOMA GP — Operator Console</title>
<style>
  :root {
    --bg: #e8e4dc;
    --panel: #f7f4ee;
    --ink: #1c1a17;
    --muted: #5c574e;
    --line: #c9c2b4;
    --accent: #0b6e4f;
    --accent-ink: #f4fff9;
    --warn: #8a3b12;
    --mono: \"IBM Plex Mono\", \"JetBrains Mono\", ui-monospace, monospace;
    --sans: \"Source Sans 3\", \"IBM Plex Sans\", system-ui, sans-serif;
  }
  * { box-sizing: border-box; }
  body {
    margin: 0; min-height: 100vh;
    font-family: var(--sans); color: var(--ink);
    background:
      radial-gradient(ellipse at 10% 0%, #dfe8e2 0%, transparent 45%),
      linear-gradient(165deg, #efe8db 0%, var(--bg) 55%, #d5d0c6 100%);
  }
  header {
    display: flex; flex-wrap: wrap; align-items: baseline; gap: .75rem 1.5rem;
    padding: 1.25rem 1.5rem .75rem; border-bottom: 1px solid var(--line);
  }
  header h1 {
    margin: 0; font-size: 1.6rem; letter-spacing: .04em;
    font-family: var(--mono); font-weight: 600;
  }
  header .tag { color: var(--muted); font-size: .9rem; }
  main {
    display: grid;
    grid-template-columns: minmax(240px, 320px) 1fr;
    gap: 1rem; padding: 1rem 1.5rem 2rem;
  }
  @media (max-width: 840px) { main { grid-template-columns: 1fr; } }
  .panel {
    background: var(--panel); border: 1px solid var(--line);
    padding: 1rem; border-radius: 2px;
  }
  .panel h2 {
    margin: 0 0 .75rem; font-size: .78rem; text-transform: uppercase;
    letter-spacing: .12em; color: var(--muted); font-family: var(--mono);
  }
  .stack { display: flex; flex-direction: column; gap: .75rem; }
  .row { display: flex; flex-wrap: wrap; gap: .4rem; }
  button, select, input {
    font: inherit; font-size: .9rem;
    border: 1px solid var(--line); background: #fff; color: var(--ink);
    padding: .4rem .65rem; border-radius: 2px;
  }
  button {
    cursor: pointer; background: var(--accent); color: var(--accent-ink);
    border-color: #095a41;
  }
  button.secondary { background: #fff; color: var(--ink); border-color: var(--line); }
  button:disabled {
    cursor: not-allowed; opacity: .45;
  }
  pre {
    margin: 0; padding: .75rem; background: #1c1a17; color: #e7e2d6;
    font-family: var(--mono); font-size: .78rem; line-height: 1.45;
    overflow: auto; max-height: 42vh; border-radius: 2px;
  }
  .grid2 { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
  @media (max-width: 840px) { .grid2 { grid-template-columns: 1fr; } }
  label { display: block; font-size: .8rem; color: var(--muted); margin-bottom: .2rem; }
  .status { font-family: var(--mono); font-size: .85rem; color: var(--muted); }
  .err { color: var(--warn); }
</style>
</head>
<body>
<header>
  <h1>AUTOMA GP</h1>
  <span class=\"tag\">Operator console · symbolic core only</span>
  <span class=\"status\" id=\"statusLine\">loading…</span>
</header>
<main>
  <aside class=\"stack\">
    <section class=\"panel stack\">
      <h2>Session</h2>
      <div class=\"row\">
        <button type=\"button\" id=\"btnRefresh\">Refresh</button>
        <button type=\"button\" class=\"secondary\" id=\"btnReset\">Reset</button>
      </div>
      <p class=\"status\" style=\"margin:0\">Refresh, Reset, and Load stay available when the server is unreachable. Plan, Simulate, Run, Emit, React, Add fact, Step, Loop, Remember, Use, and Score stay idle until a refresh succeeds.</p>
      <label for=\"domain\">Domain</label>
      <div class=\"row\">
        <select id=\"domain\">
          <option value=\"documents\">documents</option>
          <option value=\"software\">software</option>
          <option value=\"hardware\">hardware</option>
          <option value=\"music\">music</option>
          <option value=\"geometry\">geometry</option>
        </select>
        <button type=\"button\" id=\"btnDomain\">Load</button>
      </div>
    </section>
    <section class=\"panel stack\">
      <h2>Deliberate</h2>
      <div class=\"row\">
        <button type=\"button\" id=\"btnPlan\" disabled>Plan</button>
        <button type=\"button\" class=\"secondary\" id=\"btnSim\" disabled>Simulate</button>
        <button type=\"button\" class=\"secondary\" id=\"btnRun\" disabled>Run</button>
      </div>
      <label for=\"goals\">Goals JSON (optional)</label>
      <input id=\"goals\" placeholder='[[\"tests-ok\",\"myapp\"]]' style=\"width:100%\"/>
      <p class=\"status\" style=\"margin:0\">Plan with an empty Goals field uses open context goals (same as the workbench). It stays idle when none are open, when typed Goals JSON is invalid or empty, and when typed Goals JSON already holds in the facts. A single fact array is treated as one goal. Plan reuses an archived procedure whose goals include every requested fact. An exact match comes first. Extra goals of that procedure are applied when its steps still work. Otherwise procedures that each achieve part of the request are combined: no extra goals first, then procedures that also achieve something else. Steps whose extra goals cannot be restored are left aside. A search fills anything left. Simulate stays idle until status reports a successful matching, supported plan. Run stays idle until that refresh's plan GET returns, so adapters follow the live external list. Run always asks for confirmation; when the plan names adapter actions it may run them after that confirm, like the workbench Esegui.</p>
    </section>
    <section class=\"panel stack\">
      <h2>Events</h2>
      <label for=\"event\">Event JSON</label>
      <input id=\"event\" value='[\"file-created\",\"document.pdf\"]' style=\"width:100%\"/>
      <div class=\"row\">
        <button type=\"button\" id=\"btnEmit\" disabled>Emit + react + plan</button>
        <button type=\"button\" class=\"secondary\" id=\"btnReact\" disabled>React</button>
      </div>
      <p class=\"status\" style=\"margin:0\">React stays idle when there is no pending event. Emit stays idle until Event JSON is a non-empty array.</p>
    </section>
    <section class=\"panel stack\">
      <h2>Assert</h2>
      <label for=\"fact\">Fact JSON</label>
      <input id=\"fact\" placeholder='[\"toolchain\",\"ready\"]' style=\"width:100%\"/>
      <button type=\"button\" class=\"secondary\" id=\"btnFact\" disabled>Add fact</button>
      <p class=\"status\" style=\"margin:0\">Add fact stays idle until Fact JSON is a non-empty array.</p>
    </section>
    <section class=\"panel stack\">
      <h2>Autonomy</h2>
      <label for=\"authority\">Authority</label>
      <select id=\"authority\">
        <option value=\"simulate\" selected>simulate (safe)</option>
        <option value=\"read\">read</option>
        <option value=\"execute\">execute</option>
      </select>
      <label for=\"maxSteps\">Max steps (loop)</label>
      <input id=\"maxSteps\" type=\"number\" min=\"1\" max=\"32\" value=\"8\" style=\"width:100%\"/>
      <div class=\"row\">
        <button type=\"button\" id=\"btnAutoStep\" disabled>Step</button>
        <button type=\"button\" class=\"secondary\" id=\"btnAutoLoop\" disabled>Loop</button>
      </div>
      <p class=\"status\" style=\"margin:0\">Default is simulate — never unattended OS destruction. Authority and max steps follow the session policy (same as the workbench). Read still recognizes pending events (facts and goals may change), then halts without planning, simulating, or executing. Execute asks for confirmation, then may run adapters like the workbench Passo/Ciclo. Step and Loop stay idle when there is no open goal and no pending event.</p>
    </section>
    <section class=\"panel stack\">
      <h2>Archive</h2>
      <label for=\"procName\">Procedure name</label>
      <input id=\"procName\" placeholder=\"connect-iface\" style=\"width:100%\"/>
      <div class=\"row\">
        <button type=\"button\" id=\"btnRemember\" disabled>Remember</button>
        <button type=\"button\" class=\"secondary\" id=\"btnUse\" disabled>Use</button>
      </div>
      <div class=\"row\">
        <button type=\"button\" class=\"secondary\" id=\"btnScoreOk\" disabled>Score success</button>
        <button type=\"button\" class=\"secondary\" id=\"btnScoreFail\" disabled>Score failure</button>
      </div>
      <p class=\"status\" style=\"margin:0\">Remember stays idle until a successful plan exists. Simulate and Run also need that plan's external actions to still match and stay supported. Use stays idle until an archived procedure applies to the current facts (a name must match and apply; without a name, any applicable procedure plus an open goal). Score needs a named archived procedure. Use replays stored steps. A missing precondition is restored by stored procedures that achieve some of those facts: a full cover first, then procedures with no extra goals, then procedures that also achieve something else. Steps whose extra goals cannot be restored are left aside. A search fills anything left. That repair may itself reuse a stored procedure, sixty-one levels deep. Then the stored steps continue.</p>
    </section>
  </aside>
  <section class=\"stack\">
    <div class=\"grid2\">
      <div class=\"panel\"><h2>Facts</h2><pre id=\"facts\">[]</pre></div>
      <div class=\"panel\"><h2>Goals</h2><pre id=\"goalsOut\">[]</pre></div>
    </div>
    <div class=\"grid2\">
      <div class=\"panel\"><h2>Events</h2><pre id=\"events\">[]</pre></div>
      <div class=\"panel\"><h2>Plan</h2><pre id=\"plan\">null</pre></div>
    </div>
    <div class=\"panel\"><h2>Archive</h2><pre id=\"archive\">[]</pre></div>
    <div class=\"panel\"><h2>Autonomy</h2><pre id=\"autonomy\">null</pre></div>
    <div class=\"panel\"><h2>Explain</h2><pre id=\"explain\">(no trace)</pre></div>
  </section>
</main>
<script>
async function api(method, path, body) {
  const opts = { method, headers: { 'Accept': 'application/json' } };
  if (body !== undefined) {
    opts.headers['Content-Type'] = 'application/json';
    opts.body = JSON.stringify(body);
  }
  const r = await fetch(path, opts);
  const text = await r.text();
  let data;
  try { data = JSON.parse(text); } catch (e) { data = { ok: false, error: text }; }
  if (!r.ok || data.ok === false) {
    throw new Error(data.error || r.statusText || 'request failed');
  }
  return data;
}
function show(id, value) {
  document.getElementById(id).textContent =
    typeof value === 'string' ? value : JSON.stringify(value, null, 2);
}
function setDisabled(id, off) {
  document.getElementById(id).disabled = !!off;
}
let openGoals = 0;
let currentFacts = [];
let currentProcedures = [];
let planTouchesComputer = false;
let serverReachable = false;
function idleMutationControls() {
  planTouchesComputer = false;
  openGoals = 0;
  currentFacts = [];
  currentProcedures = [];
  ['btnPlan','btnSim','btnRun','btnEmit','btnReact','btnFact',
   'btnAutoStep','btnAutoLoop','btnRemember','btnUse','btnScoreOk','btnScoreFail'
  ].forEach(id => setDisabled(id, true));
}
function markDisconnected(message) {
  serverReachable = false;
  idleMutationControls();
  const line = document.getElementById('statusLine');
  line.textContent = message || 'Server unreachable';
  line.classList.add('err');
}
function markConnected() {
  serverReachable = true;
  document.getElementById('statusLine').classList.remove('err');
}
function goalsInputFilled() {
  return document.getElementById('goals').value.trim().length > 0;
}
function termKey(t) {
  if (typeof t === 'string') return t.toUpperCase();
  if (typeof t === 'number' || typeof t === 'boolean') return String(t);
  return JSON.stringify(t);
}
function factKey(f) {
  if (!Array.isArray(f)) return null;
  return JSON.stringify(f.map(termKey));
}
function factHolds(goal) {
  const k = factKey(goal);
  return !!k && currentFacts.some(f => factKey(f) === k);
}
function normalizeGoalsInput(g) {
  if (g == null) return null;
  if (!Array.isArray(g) || g.length === 0) return null;
  if (!Array.isArray(g[0])) return [g];
  return g.filter(Array.isArray);
}
function typedGoalsAllHold() {
  try {
    const list = normalizeGoalsInput(parseInput('goals', null));
    return !!(list && list.length && list.every(factHolds));
  } catch (e) {
    return false;
  }
}
function typedGoalsReady() {
  // Filled Goals must parse to a non-empty goal list before Plan enables.
  try {
    const list = normalizeGoalsInput(parseInput('goals', null));
    return !!(list && list.length);
  } catch (e) {
    return false;
  }
}
function updatePlanButton() {
  if (!serverReachable) { setDisabled('btnPlan', true); return; }
  if (goalsInputFilled()) {
    setDisabled('btnPlan', !typedGoalsReady() || typedGoalsAllHold());
  } else {
    setDisabled('btnPlan', openGoals <= 0);
  }
}
function namedProcedureExists() {
  const name = procedureName();
  if (!name) return false;
  const want = name.toUpperCase();
  return currentProcedures.some(p => String(p.name || '').toUpperCase() === want);
}
function namedProcedureApplies() {
  const name = procedureName();
  if (!name) return false;
  const want = name.toUpperCase();
  const found = currentProcedures.find(p => String(p.name || '').toUpperCase() === want);
  return !!(found && found.applies);
}
function updateArchiveButtons() {
  if (!serverReachable) {
    setDisabled('btnUse', true);
    setDisabled('btnScoreOk', true);
    setDisabled('btnScoreFail', true);
    return;
  }
  const applies = namedProcedureApplies();
  const named = namedProcedureExists();
  const hasApplicable = currentProcedures.some(p => p.applies);
  // Named Use needs a procedure that applies now; nameless Use needs any
  // applicable procedure plus an open goal to match.
  setDisabled('btnUse', !(procedureName() ? applies : (hasApplicable && openGoals > 0)));
  setDisabled('btnScoreOk', !named);
  setDisabled('btnScoreFail', !named);
}
function validJsonArray(id) {
  try {
    const v = parseInput(id, null);
    return Array.isArray(v) && v.length > 0;
  } catch (e) {
    return false;
  }
}
function updateEmitFactButtons() {
  if (!serverReachable) {
    setDisabled('btnEmit', true);
    setDisabled('btnFact', true);
    return;
  }
  setDisabled('btnEmit', !validJsonArray('event'));
  setDisabled('btnFact', !validJsonArray('fact'));
}
async function refresh() {
  try {
    const st = await api('GET', '/api/status');
    markConnected();
    document.getElementById('statusLine').textContent =
      'v' + st.version + ' · ' + st.context + ' · ' + st.mode +
      ' · domains ' + JSON.stringify(st.domains);
    const planOk = !!st['plan-success'];
    openGoals = st['open-goals'] || 0;
    const pendingEvents = st['pending-events'] || 0;
    const autonomyWork = openGoals > 0 || pendingEvents > 0;
    // Gate from status immediately (includes external-matches / supported)
    // so Sim/Run stay idle before the later plan GET returns.
    const matches = st['external-matches'] !== false;
    const supported = st['external-supported'] !== false;
    const canSimRun = planOk && matches && supported;
    setDisabled('btnSim', !canSimRun);
    // Run waits for this refresh's plan GET so adapters follow the live
    // external list, not a stale planTouchesComputer from the prior plan.
    planTouchesComputer = false;
    setDisabled('btnRun', true);
    setDisabled('btnRemember', !planOk);
    setDisabled('btnReact', pendingEvents <= 0);
    setDisabled('btnAutoStep', !autonomyWork);
    setDisabled('btnAutoLoop', !autonomyWork);
    currentProcedures = [];
    updateArchiveButtons();
    currentFacts = (await api('GET', '/api/facts')).facts || [];
    show('facts', currentFacts);
    updatePlanButton();
    updateEmitFactButtons();
    show('goalsOut', (await api('GET', '/api/goals')).goals);
    show('events', (await api('GET', '/api/events')).events);
    const plan = (await api('GET', '/api/plan')).plan;
    show('plan', plan);
    planTouchesComputer = !!(plan && Array.isArray(plan.external) && plan.external.length
                             && plan['external-matches'] !== false
                             && plan['external-supported'] !== false);
    setDisabled('btnRun', !canSimRun);
    currentProcedures = (await api('GET', '/api/archive?applies=1')).procedures || [];
    show('archive', currentProcedures);
    updateArchiveButtons();
    const auto = await api('GET', '/api/autonomy');
    show('autonomy', auto);
    syncAutonomyControls(auto);
    const ex = await api('GET', '/api/explain');
    show('explain', ex.text || '(no trace)');
  } catch (e) {
    markDisconnected(e.message);
    throw e;
  }
}
function syncAutonomyControls(auto) {
  const policy = (auto && auto.policy) || {};
  const auth = String(policy.authority || 'simulate').replace(/^:/, '').toLowerCase();
  const sel = document.getElementById('authority');
  if ([...sel.options].some(o => o.value === auth)) sel.value = auth;
  const steps = Number(policy['max-steps']);
  if (Number.isFinite(steps) && steps >= 1) {
    document.getElementById('maxSteps').value = String(Math.min(32, Math.max(1, Math.round(steps))));
  }
}
function autonomyMaxSteps() {
  const n = Number(document.getElementById('maxSteps').value);
  if (!Number.isFinite(n)) return 8;
  return Math.min(32, Math.max(1, Math.round(n)));
}
function pushAutonomyPolicy(patch) {
  if (!serverReachable) return Promise.resolve();
  return api('POST', '/api/autonomy/policy', patch).then(refresh);
}
function parseInput(id, fallback) {
  const raw = document.getElementById(id).value.trim();
  if (!raw) return fallback;
  return JSON.parse(raw);
}
document.getElementById('btnRefresh').onclick = () => refresh().catch(e => alert(e.message));
document.getElementById('btnReset').onclick = () => api('POST', '/api/reset', {}).then(refresh).catch(e => alert(e.message));
document.getElementById('btnDomain').onclick = () =>
  api('POST', '/api/load-domain', { domain: document.getElementById('domain').value, seed_demo: true })
    .then(refresh).catch(e => alert(e.message));
document.getElementById('btnPlan').onclick = () => {
  let body = {};
  let path = '/api/plan-open-goals';
  try {
    const list = normalizeGoalsInput(parseInput('goals', null));
    if (list) {
      body.goals = list;
      path = '/api/plan';
    }
  } catch (e) { alert('Goals JSON: ' + e.message); return; }
  api('POST', path, body).then(refresh).catch(e => alert(e.message));
};
document.getElementById('goals').addEventListener('input', updatePlanButton);
document.getElementById('btnSim').onclick = () => api('POST', '/api/simulate', {}).then(refresh).catch(e => alert(e.message));
document.getElementById('btnRun').onclick = () => {
  const adapters = planTouchesComputer;
  const msg = adapters
    ? 'Run will update the context facts and may run adapter actions on this computer. Continue?'
    : 'Run will update the context facts. Adapter actions stay off. Continue?';
  if (!confirm(msg)) return;
  api('POST', '/api/run', { confirm: true, adapters })
    .then(refresh).catch(e => alert(e.message));
};
document.getElementById('btnEmit').onclick = () => {
  let ev;
  try { ev = parseInput('event'); } catch (e) { alert(e.message); return; }
  api('POST', '/api/emit', { event: ev, react: true, plan: true }).then(refresh).catch(e => alert(e.message));
};
document.getElementById('btnReact').onclick = () =>
  api('POST', '/api/react', { plan: true }).then(refresh).catch(e => alert(e.message));
document.getElementById('btnFact').onclick = () => {
  let fact;
  try { fact = parseInput('fact'); } catch (e) { alert(e.message); return; }
  api('POST', '/api/add-fact', { fact }).then(refresh).catch(e => alert(e.message));
};
document.getElementById('event').addEventListener('input', updateEmitFactButtons);
document.getElementById('fact').addEventListener('input', updateEmitFactButtons);
function autonomyPayload(loop) {
  const authority = document.getElementById('authority').value;
  const payload = {
    authority,
    auto_confirm: false,
    adapters: false
  };
  if (loop) payload.max_steps = autonomyMaxSteps();
  if (authority === 'execute') {
    const msg = loop
      ? ('Up to ' + autonomyMaxSteps()
         + ' autonomous steps may update facts. Adapter actions run only if a new plan requires them. Continue?')
      : 'One autonomous step may update facts. Adapter actions run only if a new plan requires them. Continue?';
    if (!confirm(msg)) return null;
    payload.adapters = true;
    payload.auto_confirm = true;
  }
  return payload;
}
document.getElementById('btnAutoStep').onclick = () => {
  const payload = autonomyPayload(false);
  if (!payload) return;
  api('POST', '/api/autonomy/step', payload).then(refresh).catch(e => alert(e.message));
};
document.getElementById('btnAutoLoop').onclick = () => {
  const payload = autonomyPayload(true);
  if (!payload) return;
  api('POST', '/api/autonomy/loop', payload).then(refresh).catch(e => alert(e.message));
};
document.getElementById('authority').addEventListener('change', () => {
  pushAutonomyPolicy({ authority: document.getElementById('authority').value })
    .catch(e => alert(e.message));
});
document.getElementById('maxSteps').addEventListener('change', () => {
  pushAutonomyPolicy({ 'max-steps': autonomyMaxSteps() })
    .catch(e => alert(e.message));
});
function procedureName() {
  const raw = document.getElementById('procName').value.trim();
  return raw ? raw : null;
}
document.getElementById('procName').addEventListener('input', updateArchiveButtons);
document.getElementById('btnRemember').onclick = () => {
  const name = procedureName();
  api('POST', '/api/archive/remember', name ? { name } : {})
    .then(refresh).catch(e => alert(e.message));
};
document.getElementById('btnUse').onclick = () => {
  const name = procedureName();
  api('POST', '/api/archive/use', name ? { name } : {})
    .then(refresh).catch(e => alert(e.message));
};
document.getElementById('btnScoreOk').onclick = () => {
  const name = procedureName();
  if (!name) { alert('Procedure name required'); return; }
  api('POST', '/api/archive/score', { name, success: true })
    .then(refresh).catch(e => alert(e.message));
};
document.getElementById('btnScoreFail').onclick = () => {
  const name = procedureName();
  if (!name) { alert('Procedure name required'); return; }
  api('POST', '/api/archive/score', { name, success: false })
    .then(refresh).catch(e => alert(e.message));
};
refresh().catch(() => {});
updateEmitFactButtons();
</script>
</body>
</html>")

(defclass gp-acceptor (hunchentoot:acceptor)
  ()
  (:default-initargs
   :address "127.0.0.1"
   :document-root nil
   :error-template-directory nil
   :access-log-destination nil
   :message-log-destination nil))

(defmethod hunchentoot:acceptor-dispatch-request ((acceptor gp-acceptor) request)
  (let* ((method (hunchentoot:request-method* request))
         (uri (hunchentoot:script-name* request))
         (qs (hunchentoot:query-string* request))
         (path (if (and qs (plusp (length qs)))
                   (format nil "~A?~A" uri qs)
                   uri)))
    (cond
      ((and (eq method :get) (or (string= uri "/") (string= uri "/index.html")))
       (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
       (%console-html))
      ((and (>= (length uri) 5) (string= uri "/api/" :end1 5))
       (multiple-value-bind (code ctype body)
           (web-api-handle-json
            method path
            (when (member method '(:post :put :patch))
              (or (hunchentoot:raw-post-data :force-text t :request request)
                  "")))
         (setf (hunchentoot:return-code*) code
               (hunchentoot:content-type*) ctype)
         body))
      (t
       (setf (hunchentoot:return-code*) 404
             (hunchentoot:content-type*) "text/plain; charset=utf-8")
       "Not found"))))

(defun start-web (&key (port *default-web-port*) (address "127.0.0.1"))
  "Start the operator console on ADDRESS:PORT (default 127.0.0.1:47391).
Returns the acceptor. Idempotent if already running on the same port."
  (when (web-running-p)
    (let ((p (hunchentoot:acceptor-port *web-acceptor*)))
      (when (and (= p port)
                 (equal address (hunchentoot:acceptor-address *web-acceptor*)))
        (return-from start-web *web-acceptor*))
      (stop-web)))
  (gp-context) ; ensure session context exists
  (let ((acceptor (make-instance 'gp-acceptor :port port :address address)))
    (hunchentoot:start acceptor)
    (setf *web-acceptor* acceptor)
    (format t "~&AUTOMA GP web console: ~A~%" (web-url acceptor))
    acceptor))

(defun stop-web ()
  "Stop the operator console if running."
  (when *web-acceptor*
    (ignore-errors (hunchentoot:stop *web-acceptor*))
    (setf *web-acceptor* nil))
  t)

(defun gp-start-web (&rest args &key &allow-other-keys)
  "Alias for START-WEB (REPL-friendly name)."
  (apply #'start-web args))

(defun gp-stop-web ()
  "Alias for STOP-WEB."
  (stop-web))
