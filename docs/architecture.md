# Architecture

Three surfaces reach one Lisp session. The REPL is primary; the JSON
façade and the Hunchentoot console are thin layers over it; the macOS
Workbench is a native window over that server.

```text
macOS app →  http://127.0.0.1:47391  →  web-api-handle  →  core
browser    →  automa-gp/web          →  web-api-handle  →  core / REPL / autonomy
slime      →  interface/repl.lisp                     ↗
```

```text
interface/     REPL · JSON · web-api · (web via automa-gp/web)
    ↓
domains/       software · documents · hardware · music · geometry
    ↓
autonomy       policy-gated observe→plan→(simulate|execute)→update
    ↓
adapters/      filesystem · processes · macos
    ↓
memory/        working · knowledge · episodic · procedural · persistence
    ↓
core/          events · mea · planner · executor · external
```

## Core contract

What the core guarantees since 0.195.0. Each sentence corresponds to a
tested behaviour; the limits are stated where they apply.

**Contexts.** A context sees its own facts and those of every ancestor.
That is a union with one copy of each fact: a local `(power d on)` does
not hide an inherited `(power d off)`. A parent link that would make a
context its own ancestor signals `context-cycle` before anything is
written, and every walk along the chain goes through `context-lineage`.
`context-add-fact!` and `context-remove-fact!` change the local facts
only. An execute in a child context refuses, before any step, a plan that
would retract a fact the child only inherits (`plan-refused`, reason
`:inherited-retraction`).

**Facts.** Rules, operators, and plans never assert a fact that still
holds a variable. An operator that adds a three-element fact
`(predicate object value)` replaces every other three-element fact with
the same predicate and object; facts of any other length are only added
and deleted as written.

**Matching.** A variable is a symbol whose name starts with `?`; `?`
alone matches anything and binds nothing. `match` and `unify` never bind
a variable to a term that contains it, and every walk over bindings ends
on a circular alist.

**Rules and queries.** `make-rule` signals `unsafe-rule`, with a
`continue` restart, for a consequent variable no antecedent binds.
`forward-chain` runs at most `*forward-chain-limit*` rounds. `query` and
`prove` rename rule variables apart, drop a goal that repeats on its own
path, follow at most `*query-depth-limit*` rule applications below one
goal, and resolve at most `*query-step-limit*` goals in all. Each returns
a value that says whether the answer is complete and signals
`forward-chain-incomplete` or `query-incomplete` when a limit cut it.
There is no tabling: a left-recursive rule ends incomplete, and
`gp-infer` closes such rule sets by forward chaining.

**Planning.** Means-Ends Analysis treats a goal that already holds as a
zero-length success, fails a branch whose goal recurs beneath itself
(`:goal-cycle`), stops when the search returns to a state it has seen
(`:goal-clobbered`), and refuses an operator whose effects it cannot
ground. A goal that is a bare symbol is a label: the plan lists it under
`:ignored-goals`, and `plan-success` speaks for the fact goals only.

**Execution and failure.** A plan step runs inside the restarts `:retry`,
`:skip`, `:use-value`, `:use-alternative`, and `:abort-execution`;
`confirmation-required` adds `:confirm`. The conditions are
`precondition-failure`, `confirmation-required`, `unknown-operator`,
`action-failed`, and `plan-refused`. A deliberative strategy chooses a
restart by policy: `:signal`, `:skip`, `:retry`, `:abort`, or `:ask`.
With `:signal` the condition reaches the caller's handlers with the
restarts still available. The retry limit counts one step. A plan that
names an operator that is gone and carries no recorded effects is refused
before its first step.

**Persistence.** A `.agp` file is UTF-8 data, not code. A dedicated
reader accepts only what the writer produces: no `#.`, no `#S`, no reader
conditionals, no circular labels. Nesting is bounded by
`*persistence-depth-limit*` and new symbols by
`*persistence-symbol-limit*`; no package is created. By default a symbol
may be created in any existing package; bind
`*persistence-symbol-packages*` to a list of names to restrict a file
that is not trusted. A file written by another format version signals
`persistence-version-error`, which `continue` overrides. Every other load
or save failure is a `persistence-error`, and the stores are then as they
were. A write goes to a staged file beside the target that is then
renamed, so a reader never sees half a file; the rewrite does not keep a
custom file mode. A damaged
procedure archive signals `procedure-archive-error` on every access, with
`:retry` and `:skip`, and autosave never overwrites it.

**Threads.** The session state (current context, current plan, last
execution, trace history) belongs to one thread at a time, and the core does
not lock it: it has no threading dependency. `*session-lock*`, defined with
the session commands, is the one lock of the session. The web layer holds
it while a request is answered and its response is written, and every
notice and every watch thread holds it while a noticed form enters a
context, so a request, a watch and another request take turns. A thread that
holds it may take it again, and a watch that cannot get it in time looks at
its stop flag before it tries again. The REPL commands do not take it: a REPL
has one thread, and a front end that runs commands beside a watch holds it
around each one with `with-session-lock`.

**Layers and adapters.** The planner and the core know nothing of the
operating system. An operator may carry an `:external` spec in its meta, the
adapter, the operation and the arguments that make a symbolic step real.
`core/external.lisp` names the actions a plan stands for, records them on the
plan, and decides whether they would still run as recorded; it invokes
nothing. Only under an execute with `*invoke-adapters*` does it hand a spec to
the adapter that registered under its name, with `register-adapter`. The
filesystem, process and macOS adapters in `adapters/` register themselves;
the core never names one. `tests/test-architecture.lisp` fails when a source in
`core/` names an operating-system primitive or an adapter function, and shows
the executor reaching a fake adapter by name alone.

**The façade.** `web-api-handle` answers 200 with the result, 400 with `:error`
when a gate or a body refuses, 404 for an unknown path, 405 with `:allow` for
a known path and the wrong method, and 500 when a request exhausts the
storage of the image, which goes on. A body that is not JSON is a 400 in the
same envelope. Requests are answered one at a time under the session lock.
A flag is read one way everywhere: `null`, `"false"` and `0` are false, and
a value that says neither is refused. `POST /api/run` confirms a risky step
only when the body says `confirm`. A response carries `archive-error` when a
procedure archive file could not be read or written during the request: the
request completes, session memory is coherent, and the file is as it was.
The console, `automa-gp/web`, adds a request policy in front of this: the
Host header must name the console, an Origin header must be its own, a
request other than GET or HEAD must declare `application/json`, and a body
must declare its length and stay within `*max-request-body-octets*`
(1 MiB); the refusals are 403, 415, 411, 400 and 413.

## Autonomy (Phase 12 / PROMPT §28)

- `make-autonomy-policy` — `:authority` `:read` | `:simulate` | `:execute`
- `autonomous-step` / `gp-autonomous-step` — one controlled cycle;
  the REPL entry refuses when there is no open work
- `autonomous-loop` / `gp-autonomous-loop` — repeat until done/halt/max-steps;
  the REPL entry refuses the same idle state
- High-risk / irreversible operators require `auto-confirm` or `confirm-fn`
- Default authority `:simulate`; adapters still opt-in
- `prefer-archive` (default true): reuse a scored procedure when its steps
  still apply; otherwise MEA. A live execution of that plan updates the score.
  Simulation does not. The archive file stays in the persistence service
  (`~/.automa-gp/procedure-archive.agp` by default; snapshot paths without
  a type also use `.agp`).

## Workbench, observation, and external actions

This section is the detailed contract behind the summary in the README.
Each sentence corresponds to a tested behaviour.

Session commands refuse before they change anything, with the typed
condition `command-refused` (reasons such as `:no-open-goal`,
`:goal-holds`, `:no-plan`, `:unsuccessful-plan`, `:no-listening-session`)
and with a `type-error` for a wrong argument. A listening session belongs to
the context it was opened on: it ends, with the last plan and the last
execution, when the session context changes. `gp-narrate` speaks the
recorded trace in Italian. A failed `gp-plan` opens
a listening session. `gp-induce-rule` turns the manual before/after change
into an operator: the object symbol shared by that change becomes `?X0`,
and numbers stay ground. Its preconditions are the facts the change
removed and the before-facts about an object of the change; a fact that
only shares a value with the change is left out. Without an explicit before-state, induce refuses
when listening is not active. A successful plan or archive use that ends
`:plan-failed` listening also drops the before-state. A second example
with the same name merges when it fits, aligned by role whatever its
objects are called, lifting as few constants as fit and keeping risk,
action, and meta; a differing number or a one-off value is refused. `gp-learn-action` stays ground and uses the same
listening gate. A second example with the same constants
merges. A different symbol or number is refused and does not become a
variable. An operator that already uses variables is left unchanged.
`POST /api/remove-fact` retracts one fact by symbol name, so the shell can
edit a fact asserted from another package.
`gp-notice-path` asserts one existing file as `(file-created path)` only
when a registered reaction matches that event. It does not walk a
directory, watch the terminal, or reset the listening before-state.
`gp-notice-directory` looks once at the files in one existing directory,
asserts each file that reaction accepts, and applies the reaction so its
facts and goals enter the context. It enters subdirectories. A
subdirectory that is a symbolic link is not entered. It does not watch
processes, plan, or run adapters.
`gp-watch-directory` repeats that look until `gp-stop-directory-watch`
or `gp-reset`. A file created while the watch runs is noticed on a
later look. The watch still does not plan or run adapters.
`gp-notice-processes` looks once at each process a `process-running`
reaction already names. A running pid or name is asserted and the
reaction's facts and goals enter the context. A variable does not name
a process. It does not list the process table, watch the terminal,
plan, or run adapters.
`gp-watch-processes` repeats that look until `gp-stop-process-watch`
or `gp-reset`. A process that starts while the watch runs is noticed
on a later look, when a reaction already names it. The watch still
does not list the process table, read a terminal, plan, or run
adapters.
`gp-notice-terminals` looks once at each terminal a `terminal-open`
reaction already names. The name is the tty `ps` prints, such as
`ttys000`. An open one is asserted and the reaction's facts and goals
enter the context. A variable does not name a terminal. It does not
list the open terminals, read what is written there, stay listening,
plan, or run adapters. Tests may bind
`*notice-open-terminals-override*` to a list of names when the host
cannot allocate a PTY.
`gp-watch-terminals` repeats that look until `gp-stop-terminal-watch`
or `gp-reset`. A terminal that opens while the watch runs is noticed
on a later look, when a reaction already names it. The watch still
does not list the open terminals, read what is written there, plan,
or run adapters.
`gp-notice-terminal-text` looks once for a text a `terminal-text`
reaction already names, in the transcript file that reaction names.
The text is an exact sequence of characters. A symbolic link is not
followed, and a device is not opened. The rest of the file is not
returned. It does not stay listening, plan, or run adapters.
A transcript that cannot be opened or read signals, and a watch reports it
with `gp-watch-failures`, instead of counting the file as not containing the
text. `gp-watch-terminal-text` repeats that read until
`gp-stop-terminal-text-watch` or `gp-reset`. A text that appears while
the watch runs is noticed on a later look, when a reaction already
names it. The watch still does not follow a link, open a device,
return the rest of the file, read a Terminal.app tab, plan, or run
adapters.
`gp-notice-terminal-screen` looks once for a text a `terminal-screen`
reaction already names, on the Terminal.app tab whose tty that
reaction names. The text is an exact sequence of characters. The rest
of the screen is not returned. The look does not type and does not
run a command in the tab. If Terminal.app is closed or does not
answer within two seconds, that text is skipped. Off macOS there is no
Terminal.app to read, and the notice and its watch are refused with
`notice-refused` instead of starting a watch that could never notice
anything. It does not stay listening, plan, or run adapters.
`gp-watch-terminal-screen` repeats that look until
`gp-stop-terminal-screen-watch` or `gp-reset`. A text that appears
while the watch runs is noticed on a later look, when a reaction
already names it and Terminal.app answers. The watch still does not
type, run a command in the tab, return the rest of the screen, plan,
or run adapters.
Those five watches share one start, repeat, and stop. Each kind has
its own lock. Stopping one leaves the others. A later look that fails
keeps the facts from the previous look. The screen watch allows three
extra seconds for its look to finish; the others allow two.
The slot is taken before the first look. A second start of that kind
fails at once. A stop or `gp-reset` during that look does not leave
the repeat running, including a directory watch whose path is not
known yet. A first look that signals leaves the slot empty.
A stop during the look keeps the target already accepted and does not
record the next file, process, terminal, transcript line, or tab text.
The look does not hold its lock while it reads. A notice that is not
a watch still records every target.
A stop during the directory walk leaves out every file not yet
accepted. A stop during the Terminal.app read stops that osascript and
does not record the tab. A target already accepted stays.
A process check and a transcript read during a notice look use that
same wait. A stop drops the check or the read still open, and that
target is not recorded. A match split across two reads of a transcript
is still found when the look is not stopped. `process-running-p`
outside a notice look is unchanged.
A watch writes to the context it was started on, whichever context is
current when a look finishes. A look that signals is counted, and
`gp-watch-failures` lists the running watches whose latest look signalled,
with the number of looks in a row and the message; such a watch keeps the
facts of its last good look and keeps looking until a look succeeds.
`gp-plan-open-goals` plans the unsatisfied fact-like goals. It does not
change facts, simulate, or execute. No open goal — none recorded, or
all already hold — is an error. `POST /api/plan-open-goals` returns
that plan. `gp-plan` and `POST /api/plan` refuse the same way when
every requested fact-like goal already holds; the previous plan stays.
Core MEA still treats an already-held goal as a zero-length success
inside search.
`plan-external-actions` names the adapter action that plan would run,
with arguments grounded from the step. It does not invoke the adapter.
An operator removed after the plan contributes nothing.
`GET /api/plan` includes that list, recorded when the plan was built,
and whether it still matches. Simulation does not run it.
The workbench runs it on a confirmed execute only when the list is
not empty and still matches. When the recorded action no longer
matches, an execute refuses before any fact changes, whether or not
adapters were requested, so that step's symbolic effect and any
earlier step are not applied. A simulation refuses before any
simulated step. The workbench does not offer Simula or Esegui.
Planning again records the action as it is now.
`gp-use-procedure` records the external action of the rebuilt plan.
It does not invoke the adapter. A confirmed execute with adapters runs
that action when the operator is still the one recorded. When the
operator is gone, the stored effects still apply and no command is
invented. An effects-only step, whose preconditions no longer hold,
applies the symbolic leftovers and does not run the external action.
That step is marked withheld when adapters were requested. Simulation
and an execute without adapters leave the computer alone and do not
mark the step. The workbench says so after a confirmed execute.
`plan-external-actions` omits that step. `plan-external-actions-withheld`
names it, and `GET /api/plan` returns it as `external-withheld`.
The workbench does not offer it as an action that will run.
Changing the operator of that step does not refuse the execute and
does not run the command. The withheld action shown is the one
recorded when the plan was built.
When the rebuilt plan succeeds, a listening session opened for a
failed plan ends — the same rule as `gp-plan` — and the before-state
is cleared so induce cannot reuse it. A manual listening session is
left alone.
`plan-external-actions-supported-p` is false when the current facts,
including the effects of earlier steps, no longer reach an action the
plan would hand to an adapter. `GET /api/plan` returns that as
`external-supported`. An execute or a simulation then refuses before
any fact changes or simulated step, whether or not adapters were
requested for execute, so an earlier step is not applied. The
workbench does not offer Simula or Esegui in that case.
Simulation still does not change facts when it is allowed. A
precondition produced by an earlier step still leaves the action
supported. When the facts support the action again, an execute
without adapters applies the steps and leaves the computer alone.
A refused `gp-run` or `gp-simulate`, including the same refusal from an
autonomous cycle, leaves the context mode as it was and does not
record an execution. A run that starts still sets the mode to execute
or simulate.
An autonomous execute or simulate halts, and does not signal, when that
action no longer matches or the facts no longer support it, with or
without adapters when the plan recorded its actions. The same holds when
the runner itself refuses the plan after the gate, including an execute
that would retract an inherited fact: the halt carries the reason of the
refusal. The loop does not
take another step. When the action is authorized, the execute or
simulate still runs. The workbench Passo and Ciclo buttons post `/api/autonomy/step` and
`/api/autonomy/loop` with the live session authority (`:read`, `:simulate`, or
`:execute`): read may still react to pending events, then halts without
planning, simulating, or executing; simulate does not execute; execute
asks for confirmation and may enable adapters for that run. The picker exposes
all three, matching the HTML console, instead of collapsing `:read` into
simulate. Workbench and HTML captions name that react-then-halt for read.
Ciclo stops at the policy max-steps, when goals hold, or when a step
halts. The workbench shows that last outcome from `GET /api/autonomy`
under Passo and Ciclo, including after a refresh. Limite ciclo sets
that max-steps on the session policy; a loop request without
`max-steps` inherits it. `GET /api/status` reports `open-goals`
(unsatisfied fact-like goals) and `pending-events` beside the total
`goals` and `events` counts. The workbench enables Pianifica from
`open-goals`, enables Passo and Ciclo when either count is positive,
and captions open goals, pending events, or the idle state.
`gp-autonomous-step` and `gp-autonomous-loop` refuse that idle state
as well, so the HTTP endpoints return 400 and do not overwrite the
last autonomy summary. A cycle already under way may still halt with
`:no-goals` after reacting. Status `plan-p` and `plan-success`, plus
`external-matches` and `external-supported` (same helper as `GET /api/plan`),
drive workbench Simula and Esegui; without a successful matching plan those
controls stay idle. Mutation controls (Aggiungi, Chiedi, Nota…, Usa questo
piano, Pianifica, Simula, Esegui, induce, alias) also stay idle when the
workbench is not connected, and the model methods return immediately.
The HTML console reads those status fields before the
plan GET returns, and its gated buttons start disabled.
`gp-simulate` and `gp-run` refuse an unsuccessful plan before changing mode.
`gp-ask` reads an Italian phrase. A leading `voglio`, `raggiungi`,
`obiettivo`, `manca`, `fammi`, `ottieni`, or `rendi` is optional: the
words that remain are the goal. It is recorded only when an operator add,
a reaction goal, a rule consequent, or a current goal has that shape.
When that goal already holds, the phrase is refused: the goal is not
recorded and the previous plan stays. `gp-add-goal` refuses the same
way for a fact-like goal that already holds, matching names across
packages; symbol goals are still accepted as labels, and a plan lists
them under `:ignored-goals`. The
predicate is required, unless the first word is an operator name, a
reaction name, a rule name, or a word in that operator's, reaction's, or
rule's `:ask` meta.
The hardware operator `power-on-device`
answers to `accendi`, and to the same stem, so `accendere` matches.
`gp-name-operator` adds one such word to an operator, reaction, or rule
that already exists, when the name picks out only one of them.
`GET /api/operators`, `GET /api/reactions`, and `GET /api/rules` include
that `:ask` list. The workbench shows each operator already in the
context, together with each reaction and rule, and declares the word on
the one you choose. The request includes the kind, so a shared name still
declares the word on that one. Without a kind, a shared name is refused.
The operator learned in the session keeps its own field.
A phrase that fits two goals records neither and names both. The
workbench can record the one you choose and plan for it. The plan does
not execute. Choosing a candidate plans before recording the goal, so a
fact that already holds is refused without adding it. An unknown first
word records nothing as well. When the
other words fit a goal, the refusal names that goal and the workbench
can declare the word on it before planning. A word with nothing after
it is offered only when the word is a fixed term of that goal, or the
same stem of that term, including one superlative ending such as
`prontissimo`, one adverb ending such as `prontamente`, and one
abstract ending such as `prontezza`. A noun in `-sione` restores a
final D, so `accensione` shares the stem of `accendi`, and a noun
in `-mento` does the same for `accendimento`. A word whose stem is
exactly a name, such as `power-one` for `power-on`, is not offered as
a new word. When the other words already fit a goal and the first
word is not a term of it, those goals are named and the word is not
declared. Or one
exact hyphenated piece of its name, and exactly
one such goal has no variables left. The name itself is not stemmed,
so `prontissimo` does not match `segnala-pronto`. A word that does
not occur there is not a candidate. `power-one` does not match
`power-on`. Several goals that contain the word are named, and none is
recorded; the word is not declared.
A word some operator already answers is
refused without a candidate.
A command word is refused, and so is a word another one already
answers to. The name itself stays exact. A fixed term at the end may be left
unsaid, and the phrase is refused when two goals would fit. A request to
execute or delete is refused. The plan does not change facts.

The native shell is `macos/AutomaGPWorkbench`. While listening it offers the
rule name and the fact list; otherwise it offers simulate, confirm before
execute, and Passo or Ciclo for one autonomous step or a bounded loop when
status shows open goals or pending events. Idle work leaves those buttons
disabled. Simula and Esegui stay disabled until status `plan-p` is true and
`plan-success` is true. A failed plan still opens listening, but those
controls stay idle. `gp-simulate` and `gp-run` refuse an unsuccessful
plan the same way. The last autonomous outcome stays visible under
those controls. Start the Lisp server, then:

```bash
./scripts/run-web.sh
cd macos/AutomaGPWorkbench && swift run
```

## Web (Phase 11)

Optional Hunchentoot console on `127.0.0.1:47391`.
The page disables Remember until status reports `plan-success`, and
disables Simulate and Run until status also reports `external-matches`
and `external-supported` (the same values as `GET /api/plan`) — applied
as soon as status returns, before later GETs. Gated buttons start
disabled so they cannot fire during the first refresh. Autonomy Step/Loop
stay idle when there
is no open goal and no pending event. Authority and loop max-steps follow
the session policy (`GET /api/autonomy`): the console syncs those controls
on refresh and posts `/api/autonomy/policy` when they change, instead of
hard-coding a loop limit. When Authority is `execute`, Step and Loop ask
for confirmation and then send `adapters` and `auto-confirm` true — the
same gate as the workbench Passo/Ciclo. Run stays idle until the plan GET
of that refresh returns (so adapters follow the live external list, not a
stale prior plan), then asks for confirmation and sets `adapters` true only
when the current plan names matching, supported external actions — the same
rule as workbench Esegui. The workbench clears `externalActions` at status
time for the same reason, and `canSimulate` requires `externalSupported`
directly. Simula/Esegui help and captions follow that flag even while the
list is empty. Esegui also stays idle (`planExternalPending`) from status
until the plan GET of that refresh returns — the same Run window as the
HTML console. Esegui's confirm names fact updates with adapters off
honestly (not as a simulation). HTML execute Step/Loop confirm says
adapters run only if a new plan requires them. When a refresh fails, the HTML console idles the same
mutation controls the workbench disables while disconnected, until a
refresh succeeds. `POST /api/simulate` and `/api/run` refuse the same
plan-success and external gates before calling `gp-simulate`/`gp-run`.
Plan stays idle when there is no
open goal unless Goals JSON is typed (empty Goals calls
`/api/plan-open-goals`). Typed Goals that already hold in the facts
keep Plan idle; a single fact array is sent as one goal. Typed Goals that
are invalid JSON or do not form a non-empty goal list keep Plan idle.
Use and Score
stay idle until a named archived procedure exists (Use without a name
needs a non-empty archive and an open goal). React stays idle when there
is no pending event. Emit and Add fact stay idle until Event/Fact JSON
is a non-empty array. Each archived procedure may report `applies`
against the current facts when requested (`GET /api/archive?applies=1`);
Use stays idle when that flag is false. While a refresh is in flight,
Use and Score stay idle until the archive applies probe returns. The
workbench does the same: when status shows facts, open goals, or plan
gates changed, `archiveProbePending` keeps Usa questo piano idle until
`GET /api/archive?applies=1` returns, so a stale applies flag cannot fire.
Plain archive listing and POST
remember/use/score omit `applies` so the list stays cheap. Applies probes
are cached per fact/operator snapshot and procedure fingerprint so a
polling client does not replay every procedure when nothing changed.
`gp-reset` and `gp-clear-memory` drop that cache. `GET /api/archive` and `POST /api/archive/remember|use|score` are a thin
façade over the same procedural memory the REPL uses. `remember` refuses
when there is no plan or the plan did not succeed. `use` replays stored
steps on the current facts. A step whose goal already holds is skipped when
its recorded effects are already in the state. Otherwise those effects are
applied. When the operator is no longer registered, a step whose goal is
still open runs from its recorded preconditions and effects; the trace
records that. A missing precondition is restored first by archived procedures that achieve
some of those facts. One procedure that covers every missing fact is
preferred, smallest extra goal set first. Then procedures whose goals stay
inside the missing set. Then procedures that also achieve something else. When those extra goals
cannot be restored, the steps that serve the missing facts are kept and the
other steps are left aside. A Means-Ends search restores any fact they
leave out. That repair may
itself reuse archived procedures the same way, sixty-one levels deep. A sixty-second
repair does not consult the archive. Planning prefers an exact goal match, then a
procedure whose goals include the request, fewest extra goals first.
Otherwise procedures whose goals are a part of the request are combined,
largest part first, then procedures that also achieve something outside
the request. Those extra goals are applied. When they cannot be restored, the steps
that serve the request are kept and the others are left aside. A search
fills anything they leave. If the useful steps cannot run either, that
procedure is skipped. The stored steps then continue.
A recorded step runs its external action only on a confirmed execute with
adapters, and only when its operator is still the one recorded; the
section above states the full rule. A high-risk or irreversible step still
requires confirmation on a live run.

## Semantic platform foundation (`semantic/`)

The system `automa-gp/semantic` is the foundation of the platform specified in
[`PROMPT-SEMANTICA.md`](PROMPT-SEMANTICA.md) and integrated in
[`piattaforma-semantica.md`](piattaforma-semantica.md). It depends on
`automa-gp` only for `gp-error`, and no standard is implemented in it yet.
Each sentence below corresponds to a tested behaviour.

**Registry.** A `standard-definition` records an identifier (a keyword), a
name, a version, a release, a maturity (`:recommendation`,
`:candidate-recommendation`, `:note`, `:rfc`, `:living-document`), the URL of
the official specification, its documents (normative or informative), its
dependencies, its test suites, its constructs, the status of its catalog of
constructs (`:pending`, `:partial`, `:complete`) and its evidence. A standard
is named `identifier@version`. A dependency must name a version, because one
that does not is not reproducible. `find-standard` with no version returns the
only registered version, and with several signals a
`standard-resolution-error` that lists them. A duplicate is refused unless
`:replace` is given or the restart `:replace-standard` is taken.
`standard-closure` lists a standard and everything it depends on,
dependencies first, in the same order every time; a dependency that is not
registered signals `dependency-missing`, which names what required it, and a
cycle signals `dependency-cycle` with its path.

**Shipped catalog.** The registry is loaded with 16 standards: RDF 1.1,
RDF Schema 1.1, N-Triples, N-Quads, Turtle, RDF/XML, JSON-LD 1.1, OWL 2,
SHACL, SPARQL 1.1, PROV-O, the Wikibase data model, XSD 1.1 datatypes, RFC
3987, BCP 47 and RDF 1.2. Titles, releases and URLs were read from the
publishers' pages. RDF 1.2 is registered as a Candidate Recommendation. A
dependency is declared only where the specification's own list of normative
references says so, which was read for RDF 1.1, N-Triples and SHACL; OWL 2
and SPARQL declare none, and say why. No shipped standard has a construct, a
requirement, evidence or a level: the tests assert that.

**Levels of support.** In order, `:parsed`, `:represented`, `:validated`,
`:semantically-implemented`, `:executable`, `:conformant`. `evidence`
establishes a level only if it is of the right kind and came out right:
a `:test-run` with passes and no failures for the first four, a `:build`
with passes and no failures for `:executable`, and a `:conformance-report`
whose verdict is `:pass` for `:conformant`. `evidenced-level` reaches a level
only if it and every level below it are established, so evidence for a high
level alone proves nothing. A conformance verdict is `:pass`, `:fail`,
`:partial` (something passed, nothing failed, something was left out) or
`:none` (nothing passed and nothing failed). `standard-support` gives the
lowest level among the cataloged constructs and says the standard is
`:claimable` only when the catalog is `:complete` and every construct has a
level. `construct-status` turns a level into the answer the prompt asks of a
construct: `:not-implemented`, `:partially-implemented` up to `:validated`,
`:implemented` from `:semantically-implemented`.

**Requirements.** A requirement has an id such as `REQ-OWL2-SYNTAX-0001`, a
standard with its version, a section, a summary in the maintainer's words
(the specification text is not copied), a modality, a construct, tests and
implementation symbols. It can be registered only for a registered standard,
and for a construct the standard's catalog contains once the catalog has any.
`requirements-implemented-by` answers which requirements a function
implements, `tests-for-requirement` which tests check one, and
`traceability-gaps` which requirements have no test, no implementation, or
name a symbol that does not exist.

**Diagnostics.** Every failure is a `standards-error`, a `gp-error` carrying
a code, a message, a source, a location, a standard, a version, a construct and
a suggestion, with one subtype each for a parse error, a resolution error, a
dependency error, a semantic error, an unsupported construct, an
implementation error, a conformance failure and a runtime error. A
construct that is not implemented is never dropped silently: `report-unsupported`
records a `:not-implemented` diagnostic in the active collector and signals
`unsupported-construct` with the restart `:continue-unsupported`, unless
`*unsupported-policy*` is `:record` and a collector is active. With no collector
the policy cannot let it vanish, and a diagnostic of severity `:error` or
`:warning` noted with nowhere to go is signalled instead.

**Command line.** `scripts/modelc` answers `standard list`, `standard show`,
`standard closure` and `requirements`. A command the prompt lists and that
does not exist yet names the phase that brings it and exits with status 3;
an unknown command exits with 2, a failure with 1, success with 0.

**Layering.** `tests/test-architecture.lisp` fails when a source in `core/`
or `semantic/` names an operating-system primitive, when `core/` or `memory/`
names an adapter, and when an exported symbol of `automa-gp` or
`automa-gp/semantic` is undefined or has no docstring.

## Dependency policy

Core: ANSI Common Lisp, ASDF, UIOP; on SBCL the notices also use `sb-posix`.
Semantic platform foundation (`automa-gp/semantic`): the core, nothing else.
The platform's later systems may depend on further libraries, each in a
system of its own (`piattaforma-semantica.md` §9).
Web (optional): Hunchentoot.
Tests: FiveAM.
Workbench: Swift 5.9, macOS 13 or later, no packages.
