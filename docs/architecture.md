# Architecture (Phases 1–12)

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

## Workbench (v0.123.0)

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
facts and goals enter the context. It does not enter subdirectories,
watch processes, plan, or run adapters.
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
Adapters are not invoked for a recorded step. A high-risk or irreversible
step still requires confirmation on a live run.

## Dependency policy

Core: ANSI CL + ASDF + UIOP.  
Web (optional): Hunchentoot.  
Tests: FiveAM.
