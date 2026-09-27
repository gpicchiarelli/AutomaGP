# Architecture (Phases 1–12)

```text
browser  →  automa-gp/web  →  web-api-handle  →  core / REPL / autonomy
slime    →  interface/repl.lisp              ↗
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
