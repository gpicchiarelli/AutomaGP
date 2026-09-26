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
        <button type=\"button\" id=\"btnPlan\">Plan</button>
        <button type=\"button\" class=\"secondary\" id=\"btnSim\">Simulate</button>
        <button type=\"button\" class=\"secondary\" id=\"btnRun\">Run</button>
      </div>
      <label for=\"goals\">Goals JSON (optional)</label>
      <input id=\"goals\" placeholder='[[\"tests-ok\",\"myapp\"]]' style=\"width:100%\"/>
    </section>
    <section class=\"panel stack\">
      <h2>Events</h2>
      <label for=\"event\">Event JSON</label>
      <input id=\"event\" value='[\"file-created\",\"document.pdf\"]' style=\"width:100%\"/>
      <div class=\"row\">
        <button type=\"button\" id=\"btnEmit\">Emit + react + plan</button>
        <button type=\"button\" class=\"secondary\" id=\"btnReact\">React</button>
      </div>
    </section>
    <section class=\"panel stack\">
      <h2>Assert</h2>
      <label for=\"fact\">Fact JSON</label>
      <input id=\"fact\" placeholder='[\"toolchain\",\"ready\"]' style=\"width:100%\"/>
      <button type=\"button\" class=\"secondary\" id=\"btnFact\">Add fact</button>
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
async function refresh() {
  const st = await api('GET', '/api/status');
  document.getElementById('statusLine').textContent =
    'v' + st.version + ' · ' + st.context + ' · ' + st.mode +
    ' · domains ' + JSON.stringify(st.domains);
  show('facts', (await api('GET', '/api/facts')).facts);
  show('goalsOut', (await api('GET', '/api/goals')).goals);
  show('events', (await api('GET', '/api/events')).events);
  show('plan', (await api('GET', '/api/plan')).plan);
  const ex = await api('GET', '/api/explain');
  show('explain', ex.text || '(no trace)');
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
  try {
    const g = parseInput('goals', null);
    if (g) body.goals = g;
  } catch (e) { alert('Goals JSON: ' + e.message); return; }
  api('POST', '/api/plan', body).then(refresh).catch(e => alert(e.message));
};
document.getElementById('btnSim').onclick = () => api('POST', '/api/simulate', {}).then(refresh).catch(e => alert(e.message));
document.getElementById('btnRun').onclick = () =>
  api('POST', '/api/run', { confirm: true, adapters: false }).then(refresh).catch(e => alert(e.message));
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
refresh().catch(e => {
  document.getElementById('statusLine').textContent = e.message;
  document.getElementById('statusLine').classList.add('err');
});
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
         (uri (hunchentoot:script-name* request)))
    (cond
      ((and (eq method :get) (or (string= uri "/") (string= uri "/index.html")))
       (setf (hunchentoot:content-type*) "text/html; charset=utf-8")
       (%console-html))
      ((and (>= (length uri) 5) (string= uri "/api/" :end1 5))
       (multiple-value-bind (code ctype body)
           (web-api-handle-json
            method uri
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
