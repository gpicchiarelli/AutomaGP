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
core/          events · mea · planner · executor
```

## Autonomy (Phase 12 / PROMPT §28)

- `make-autonomy-policy` — `:authority` `:read` | `:simulate` | `:execute`
- `autonomous-step` / `gp-autonomous-step` — one controlled cycle
- `autonomous-loop` / `gp-autonomous-loop` — repeat until done/halt/max-steps
- High-risk / irreversible operators require `auto-confirm` or `confirm-fn`
- Default authority `:simulate`; adapters still opt-in
- `prefer-archive` (default true): reuse a scored procedure when its steps
  still apply; otherwise MEA. A live execution of that plan updates the score.
  Simulation does not. The archive file stays in the persistence service.

## Workbench, observation, and external actions

This section is the detailed contract behind the summary in the README.
Each sentence corresponds to a tested behaviour.

`gp-narrate` speaks the recorded trace in Italian. A failed `gp-plan` opens
a listening session. `gp-induce-rule` turns the manual before/after change
into an operator: the object symbol shared by that change becomes `?X0`,
and numbers stay ground. A second example with the same name merges when
it fits; a differing number or a one-off value is refused.
`gp-learn-action` stays ground. A second example with the same constants
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
plan, or run adapters.
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
`gp-watch-terminal-text` repeats that read until
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
answer within two seconds, that text is skipped. It does not stay
listening, plan, or run adapters.
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
`gp-plan-open-goals` plans those goals. It does not change facts,
simulate, or execute. No fact-like goal is an error.
`POST /api/plan-open-goals` returns that plan.
`plan-external-actions` names the adapter action that plan would run,
with arguments grounded from the step. It does not invoke the adapter.
An operator removed after the plan contributes nothing.
`GET /api/plan` includes that list, recorded when the plan was built,
and whether it still matches. Simulation does not run it.
The workbench runs it on a confirmed execute only when the list is
not empty and still matches. When the recorded action no longer
matches, an execute refuses before any fact changes, whether or not
adapters were requested, so that step's symbolic effect and any
earlier step are not applied. The workbench does not offer Esegui.
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
`plan-external-actions-supported-p` is false when the current facts,
including the effects of earlier steps, no longer reach an action the
plan would hand to an adapter. `GET /api/plan` returns that as
`external-supported`. An execute then refuses before any fact
changes, whether or not adapters were requested, so an earlier step
is not applied. The workbench does not offer Esegui in that case.
Simulation still does not change facts. A precondition produced by an
earlier step still leaves the action supported. When the facts
support the action again, an execute without adapters applies the
steps and leaves the computer alone.
A refused `gp-run`, including the same refusal from an autonomous
execute, leaves the context mode as it was and does not record an
execution. A run that starts still sets the mode to execute.
An autonomous execute halts, and does not signal, when that action
no longer matches or the facts no longer support it, with or without
adapters when the plan recorded its actions. The loop does not take
another step. When the action is authorized, the execute still runs.
`gp-ask` reads an Italian phrase. A leading `voglio`, `raggiungi`,
`obiettivo`, `manca`, `fammi`, `ottieni`, or `rendi` is optional: the
words that remain are the goal. It is recorded only when an operator add,
a reaction goal, a rule consequent, or a current goal has that shape. The
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
not execute. An unknown first word records nothing as well. When the
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
rule name and the fact list; otherwise it offers simulate, and asks before
execute. Start the Lisp server, then:

```bash
./scripts/run-web.sh
cd macos/AutomaGPWorkbench && swift run
```

## Web (Phase 11)

Optional Hunchentoot console on `127.0.0.1:47391`.
`GET /api/archive` and `POST /api/archive/remember|use|score` are a thin
façade over the same procedural memory the REPL uses. `use` replays stored
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

## Dependency policy

Core: ANSI Common Lisp, ASDF, UIOP.
Web (optional): Hunchentoot.
Tests: FiveAM.
Workbench: Swift 5.9, macOS 13 or later, no packages.
