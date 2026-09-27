# Changelog

All notable changes to AUTOMA GP are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows the incremental phases in `docs/PROMPT.md` §25.

## [0.123.0] — 2026-09-27

### Added

- `gp-notice-directory` looks once at the files in one directory. Each
  file a `file-created` reaction already models is asserted, and that
  reaction's facts and goals enter the context. Subdirectories are not
  entered. The call does not plan and does not run adapters. `gp-run`
  with adapters still performs an operator's external action afterward.
  `POST /api/notice-directory` is the same gate.

## [0.122.0] — 2026-09-27

### Changed

- An unknown first word is not declared when the other words already
  fit a goal and that word is not a term of the goal. Those goals are
  named and none is recorded. `spegni interface-01` does not name
  `power-off`. A word that is a term, such as `pronti system` for
  `(system pronto)`, can still be declared.

## [0.121.0] — 2026-09-27

### Changed

- A word whose stem is exactly the name of an operator, a reaction, or
  a rule is not offered as a new word. `power-one` is not `power-on`,
  and nothing is recorded. A new word such as `spegni` is still offered
  when the other words fit a goal.

## [0.120.0] — 2026-09-27

### Changed

- A noun in `-mento` shares the verb stem, so `accendimento` shares
  the stem of `accendi`. The name itself is not stemmed.

## [0.119.0] — 2026-09-27

### Changed

- A noun in `-sione` from a verb in `-ere` restores the final D, so
  `accensione` shares the stem of `accendi`. A regular `-zione` noun
  shares the verb stem, so `classificazione` shares `classifica`.
  `power-one` does not match `power-on`. The name itself is not stemmed.

## [0.118.0] — 2026-09-27

### Changed

- A stem drops one `-ezza` ending, so `prontezza` and `prontezze` share
  the stem of `pronto`. A different ending, such as `accensione`, still
  does not match. The name itself is not stemmed.

## [0.117.0] — 2026-09-27

### Changed

- A stem drops one `-mente` ending before the superlative, so
  `prontamente` shares the stem of `pronto`. A different ending, such
  as `accensione`, still does not match. The name itself is not stemmed.

## [0.116.0] — 2026-09-27

### Changed

- A stem drops one superlative ending before the usual ending, so
  `prontissimo` and `pronta` share the stem of `pronto`. A different
  stem, such as `accensione`, still does not match. The name itself is
  not stemmed.

## [0.115.0] — 2026-09-27

### Changed

- A word alone matches the same stem of a fixed term, so `pronti` and
  `pronta` name a goal whose term is `pronto`. The operator, reaction,
  or rule name stays exact, so `pronti` does not match `segnala-pronto`.

## [0.114.0] — 2026-09-27

### Changed

- A word alone names a goal with no variables only when that word is a
  fixed term of the goal, or one hyphenated piece of its name. A word
  that does not occur there is not a candidate. `power-one` does not
  match `power-on`.

## [0.113.0] — 2026-09-27

### Changed

- A word alone, when more than one goal has no variables, names those
  goals and records none. The word is not declared. One of those goals
  can still be recorded afterwards.

## [0.112.0] — 2026-09-27

### Changed

- A word alone is offered only when the context has exactly one goal
  with no variables. Several such goals are not listed, and nothing is
  recorded. The other words of a phrase can still fit more than one goal.

## [0.111.0] — 2026-09-27

### Changed

- A word alone can name a goal that has no variables left. The refusal
  lists those goals and records none of them. A goal that still has a
  variable is not offered until the other words are said. A word that
  someone already answers is not offered again.

## [0.110.0] — 2026-09-27

### Changed

- An unknown first word still records nothing. When the other words fit
  one or more goals, the refusal names those goals and who would receive
  the word. The workbench can declare it on the one you choose, then
  record that goal and plan. A word alone, or a word already in use,
  stays a refusal with no candidates.

## [0.109.0] — 2026-09-27

### Changed

- A phrase that fits two goals still records neither. The refusal names
  both goals. The workbench lists them, and **Usa questo** records the
  one you choose and plans for it. The plan does not execute.

## [0.108.0] — 2026-09-27

### Changed

- `gp-name-operator` accepts a kind. When an operator and a reaction share
  a name, the word is declared on the one you name. Without a kind, that
  shared name is still refused and nothing changes. The workbench sends
  the kind of the row you chose.

## [0.107.0] — 2026-09-27

### Changed

- The workbench lists every operator already in the context, together with
  the reactions and rules. **Chiama così** declares a word on the one you
  choose. The operator learned in this session keeps its own field.

## [0.106.0] — 2026-09-27

### Changed

- The workbench lists each reaction and rule already in the context.
  **Chiama così** declares a word on the one you choose. The list shows
  the words already declared. The operator learned in this session keeps
  its own field.

## [0.105.0] — 2026-09-27

### Changed

- `gp-name-operator` declares a word on a reaction or a rule when that
  name belongs to only one of them. `classifica` then asks for the
  reaction's goal, and the same stem counts. If an operator and a
  reaction share the name, the declaration is refused and nothing changes.

## [0.104.0] — 2026-09-27

### Changed

- `gp-ask` accepts a reaction name or a rule name the way it accepts an
  operator name. `classify note.txt` is the reaction's goal. The name
  stays exact. If an operator and a reaction share that name and their
  goals differ, the phrase is refused.

## [0.103.0] — 2026-09-27

### Added

- `gp-name-operator` declares one word on an existing operator. `spegnere`
  then names that operator in `gp-ask`, and so does the same stem. A
  command word is refused. If another operator already answers to the
  word, nothing changes.

## [0.102.0] — 2026-09-27

### Changed

- A word in an operator's `:ask` meta also matches the same stem.
  `accendere` names the operator that declares `accendi`. A different
  stem, such as `accensione`, does not. The operator's own name stays
  exact.

## [0.101.0] — 2026-09-27

### Changed

- `gp-ask` accepts the operator's name in place of the predicate.
  `power-on interface-01` is `(power-state interface-01 on)` when that
  operator adds it. A word listed in the operator's `:ask` meta names it
  the same way: the hardware operator `power-on-device` answers to
  `accendi`. Two operators that share the word are refused.

## [0.100.0] — 2026-09-27

### Changed

- `gp-ask` accepts a phrase that leaves a fixed term unsaid at the end of
  a shape the context already achieves. `power-state interface-01` is
  `(power-state interface-01 on)` when that is the only match. If two
  goals fit, the phrase is refused and nothing is recorded.

## [0.99.0] — 2026-09-27

### Changed

- `gp-learn-action` merges a second example when every constant is already
  the same. A different symbol or number is refused, the registered
  operator stays, and no variable is introduced. An operator that already
  uses variables is left unchanged.

## [0.98.0] — 2026-09-27

### Changed

- `gp-ask` no longer requires a leading verb. The remaining words are a
  goal when they match a shape the context already achieves. `fammi`,
  `ottieni`, and `rendi` are optional openings. A request to execute or
  delete is still refused.

## [0.97.0] — 2026-09-27

### Added

- A second `gp-induce-rule` with the same name merges when the example
  fits. An existing variable stays. A symbol that occurs at least twice
  and is renamed becomes the next variable. A differing number or a
  one-off value is refused, and the operator already registered stays.

## [0.96.0] — 2026-09-27

### Added

- `gp-ask` turns an Italian phrase into a goal when an operator add, a
  reaction goal, a rule consequent, or a current goal already has that
  shape. A phrase that asks to execute or delete is refused. The plan
  that follows does not change facts.

## [0.95.0] — 2026-09-27

### Added

- `gp-notice-path` asserts `(file-created path)` only when that file
  exists and a reaction already matches it. A directory, a missing path,
  and an unmodeled file are refused. An open listening session keeps its
  before-state. `POST /api/notice-path` is the same gate.

## [0.94.0] — 2026-09-27

### Changed

- The macOS workbench leads with one next step. Facts are a list you can
  edit. A failed plan suggests a rule name. Execute asks before it runs.
  `POST /api/remove-fact` retracts one fact by symbol name, so an edit
  from the window matches a fact asserted in another package.

## [0.93.0] — 2026-09-27

### Added

- A failed `gp-plan` opens a listening session on the current facts.
  `gp-induce-rule` turns the later manual change into an operator and lifts
  the shared object symbol to `?X0`. Numeric constants stay ground.

## [0.92.0] — 2026-09-27

### Added

- The macOS workbench (`macos/AutomaGPWorkbench`) shows the recorded
  deliberation, the procedure archive, and the simulate/execute gate.
  It speaks to the Lisp server on `127.0.0.1:47391`.
- `gp-narrate` turns a deliberative trace into Italian sentences and a
  node list. The sentences name only recorded entries.
- `gp-note-state` and `gp-learn-action` induce one ground operator from
  a before/after observation. Facts that do not share a term with the
  change are not preconditions.

## [0.91.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure sixty-one levels deep.
  The trace names each procedure. A sixty-second repair uses Means-Ends
  Analysis only.

## [0.90.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure sixty levels deep.
  The trace names each procedure. A sixty-first repair uses Means-Ends
  Analysis only.

## [0.89.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure fifty-nine levels deep.
  The trace names each procedure. A sixtieth repair uses Means-Ends
  Analysis only.

## [0.88.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure fifty-eight levels deep.
  The trace names each procedure. A fifty-ninth repair uses Means-Ends
  Analysis only.

## [0.87.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure fifty-seven levels deep.
  The trace names each procedure. A fifty-eighth repair uses Means-Ends
  Analysis only.

## [0.86.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure fifty-six levels deep.
  The trace names each procedure. A fifty-seventh repair uses Means-Ends
  Analysis only.

## [0.85.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure fifty-five levels deep.
  The trace names each procedure. A fifty-sixth repair uses Means-Ends
  Analysis only.

## [0.84.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure fifty-four levels deep.
  The trace names each procedure. A fifty-fifth repair uses Means-Ends
  Analysis only.

## [0.83.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure fifty-three levels deep.
  The trace names each procedure. A fifty-fourth repair uses Means-Ends
  Analysis only.

## [0.82.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure fifty-two levels deep.
  The trace names each procedure. A fifty-third repair uses Means-Ends
  Analysis only.

## [0.81.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure fifty-one levels deep.
  The trace names each procedure. A fifty-second repair uses Means-Ends
  Analysis only.

## [0.80.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure fifty levels deep.
  The trace names each procedure. A fifty-first repair uses Means-Ends
  Analysis only.

## [0.79.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure forty-nine levels deep.
  The trace names each procedure. A fiftieth repair uses Means-Ends
  Analysis only.

## [0.78.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure forty-eight levels deep.
  The trace names each procedure. A forty-ninth repair uses Means-Ends
  Analysis only.

## [0.77.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure forty-seven levels deep.
  The trace names each procedure. A forty-eighth repair uses Means-Ends
  Analysis only.

## [0.76.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure forty-six levels deep.
  The trace names each procedure. A forty-seventh repair uses Means-Ends
  Analysis only.

## [0.75.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure forty-five levels deep.
  The trace names each procedure. A forty-sixth repair uses Means-Ends
  Analysis only.

## [0.74.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure forty-four levels deep.
  The trace names each procedure. A forty-fifth repair uses Means-Ends
  Analysis only.

## [0.73.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure forty-three levels deep.
  The trace names each procedure. A forty-fourth repair uses Means-Ends
  Analysis only.

## [0.72.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure forty-two levels deep.
  The trace names each procedure. A forty-third repair uses Means-Ends
  Analysis only.

## [0.71.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure forty-one levels deep.
  The trace names each procedure. A forty-second repair uses Means-Ends
  Analysis only.

## [0.70.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure forty levels deep.
  The trace names each procedure. A forty-first repair uses Means-Ends
  Analysis only.

## [0.69.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure thirty-nine levels deep.
  The trace names each procedure. A fortieth repair uses Means-Ends
  Analysis only.

## [0.68.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure thirty-eight levels deep.
  The trace names each procedure. A thirty-ninth repair uses Means-Ends
  Analysis only.

## [0.67.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure thirty-seven levels deep.
  The trace names each procedure. A thirty-eighth repair uses Means-Ends
  Analysis only.

## [0.66.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure thirty-six levels deep.
  The trace names each procedure. A thirty-seventh repair uses Means-Ends
  Analysis only.

## [0.65.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure thirty-five levels deep.
  The trace names each procedure. A thirty-sixth repair uses Means-Ends
  Analysis only.

## [0.64.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure thirty-four levels deep.
  The trace names each procedure. A thirty-fifth repair uses Means-Ends
  Analysis only.

## [0.63.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure thirty-three levels deep.
  The trace names each procedure. A thirty-fourth repair uses Means-Ends
  Analysis only.

## [0.62.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure thirty-two levels deep.
  The trace names each procedure. A thirty-third repair uses Means-Ends
  Analysis only.

## [0.61.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure thirty-one levels deep.
  The trace names each procedure. A thirty-second repair uses Means-Ends
  Analysis only.

## [0.60.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure thirty levels deep.
  The trace names each procedure. A thirty-first repair uses Means-Ends
  Analysis only.

## [0.59.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure twenty-nine levels deep.
  The trace names each procedure. A thirtieth repair uses Means-Ends
  Analysis only.

## [0.58.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure twenty-eight levels deep.
  The trace names each procedure. A twenty-ninth repair uses Means-Ends
  Analysis only.

## [0.57.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure twenty-seven levels deep.
  The trace names each procedure. A twenty-eighth repair uses Means-Ends
  Analysis only.

## [0.56.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure twenty-six levels deep.
  The trace names each procedure. A twenty-seventh repair uses Means-Ends
  Analysis only.

## [0.55.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure twenty-five levels deep.
  The trace names each procedure. A twenty-sixth repair uses Means-Ends
  Analysis only.

## [0.54.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure twenty-four levels deep.
  The trace names each procedure. A twenty-fifth repair uses Means-Ends
  Analysis only.

## [0.53.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure twenty-three levels deep.
  The trace names each procedure. A twenty-fourth repair uses Means-Ends
  Analysis only.

## [0.52.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure twenty-two levels deep.
  The trace names each procedure. A twenty-third repair uses Means-Ends
  Analysis only.

## [0.51.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure twenty-one levels deep.
  The trace names each procedure. A twenty-second repair uses Means-Ends
  Analysis only.

## [0.50.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure twenty levels deep.
  The trace names each procedure. A twenty-first repair uses Means-Ends
  Analysis only.

## [0.49.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure nineteen levels deep.
  The trace names each procedure. A twentieth repair uses Means-Ends
  Analysis only.

## [0.48.0] — 2026-09-27

### Changed

- A precondition repair may reuse an archived procedure eighteen levels deep.
  The trace names each procedure. A nineteenth repair uses Means-Ends
  Analysis only.

## [0.47.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure seventeen levels deep.
  The trace names each procedure. An eighteenth repair uses Means-Ends
  Analysis only.

## [0.46.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure sixteen levels deep.
  The trace names each procedure. A seventeenth repair uses Means-Ends
  Analysis only.

## [0.45.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure fifteen levels deep.
  The trace names each procedure. A sixteenth repair uses Means-Ends
  Analysis only.

## [0.44.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure fourteen levels deep.
  The trace names each procedure. A fifteenth repair uses Means-Ends
  Analysis only.

## [0.43.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure thirteen levels deep.
  The trace names each procedure. A fourteenth repair uses Means-Ends
  Analysis only.

## [0.42.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure twelve levels deep.
  The trace names each procedure. A thirteenth repair uses Means-Ends
  Analysis only.

## [0.41.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure eleven levels deep.
  The trace names each procedure. A twelfth repair uses Means-Ends Analysis
  only.

## [0.40.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure ten levels deep.
  The trace names each procedure. An eleventh repair uses Means-Ends
  Analysis only.

## [0.39.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure nine levels deep.
  The trace names each procedure. A tenth repair uses Means-Ends Analysis
  only.

## [0.38.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure eight levels deep.
  The trace names each procedure. A ninth repair uses Means-Ends Analysis
  only.

## [0.37.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure seven levels deep.
  The trace names each procedure. An eighth repair uses Means-Ends Analysis
  only.

## [0.36.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure six levels deep.
  The trace names each procedure. A seventh repair uses Means-Ends Analysis
  only.

## [0.35.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure five levels deep.
  The trace names each procedure. A sixth repair uses Means-Ends Analysis
  only.

## [0.34.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure four levels deep.
  The trace names each procedure. A fifth repair uses Means-Ends Analysis
  only.

## [0.33.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure three levels deep.
  The trace names each procedure. A fourth repair uses Means-Ends Analysis
  only.

## [0.32.0] — 2026-09-26

### Changed

- When an archived procedure can answer part of a planning request but
  another of its goals cannot be restored, `gp-plan` keeps the steps that
  serve the request and leaves the other steps aside. The trace records
  `Left aside`. If the useful steps themselves do not apply, the procedure
  is still skipped.

## [0.31.0] — 2026-09-26

### Changed

- When `gp-plan` combines archived procedures, a procedure that achieves
  part of the request and also something else is used after procedures
  whose goals stay inside the request. Those extra goals are applied. A
  procedure with no extra goals is still preferred, even with a lower
  score. If the extra goals cannot be restored, that procedure is skipped.

## [0.30.0] — 2026-09-26

### Changed

- When no archived procedure covers a planning request, `gp-plan` combines
  procedures whose goals are a part of that request, largest part first.
  A search fills any fact they leave. The trace names each procedure. A
  live `gp-run` scores each of them. A procedure that also achieves
  something outside the request is not combined this way.

## [0.29.0] — 2026-09-26

### Changed

- `gp-plan` reuses an archived procedure whose goals include the requested
  facts. An exact match still comes first. Among procedures with extra
  goals, the smallest extra set comes first, and those extra goals are
  applied when the stored steps still work. A procedure that restores only
  part of the request is not used for that plan.

## [0.28.0] — 2026-09-26

### Changed

- When an archived procedure can restore a missing fact but another of its
  goals cannot be restored, replay keeps the steps that serve the missing
  facts and leaves the other steps aside. The trace records `Left aside`.
  If the useful steps themselves do not apply, the procedure is still
  rejected.

## [0.27.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure that achieves only
  some of the missing facts and also some other goal. Procedures that cover
  every missing fact still come first, then procedures whose goals stay
  inside the missing set. The extra goals are applied with the repair. A
  search restores any fact that remains.

## [0.26.0] — 2026-09-26

### Changed

- A precondition repair combines archived procedures that each achieve only
  part of the missing facts. A procedure that covers every missing fact is
  still preferred. Any fact those procedures leave out is restored by a
  Means-Ends search, then the stored steps continue. The trace names each
  reused procedure.

## [0.25.0] — 2026-09-26

### Changed

- A precondition repair may reuse an archived procedure whose goals include
  the missing facts and also some others. The smallest extra goal set is
  tried first; score breaks a tie. Planning still requires an exact goal
  match before it reuses a procedure for the whole problem.

## [0.24.0] — 2026-09-26

### Changed

- A procedure reused to repair a missing precondition may itself reuse one
  archived procedure for a precondition it still lacks. The trace records
  both `reused procedure` gaps. A third repair does not consult the archive.
  Each reused procedure's goals must still equal the missing facts exactly.

## [0.23.0] — 2026-09-26

### Changed

- The outermost repair of a missing precondition replays one archived
  procedure whose goals are exactly those facts, then continues the stored
  steps. The trace records `reused procedure` on that gap. A repair nested
  inside that procedure does not consult the archive again. If no such
  procedure applies, the repair is still a Means-Ends search for the missing
  fact only.

## [0.22.0] — 2026-09-26

### Changed

- When a stored step is missing a precondition, replay runs one Means-Ends
  search for that fact alone, inserts those steps, and continues with the
  recorded procedure. The search does not consult the archive. The trace
  records `Missing precondition` and each `Repair step`. If the fact cannot
  be restored, the procedure does not apply and planning falls back to a
  full search.

## [0.21.0] — 2026-09-26

### Changed

- A planned step also records its grounded preconditions. When the operator
  is no longer registered and the step's goal does not yet hold, replay
  applies the recorded effects if every recorded precondition still holds.
  The trace says `Recorded effects`. Live execution re-checks those
  preconditions and still asks for confirmation when the recorded risk is
  high or the step was irreversible. A step with no recorded preconditions
  still does not apply.

## [0.20.0] — 2026-09-26

### Changed

- A planned step records the symbolic effects it grounded (`:adds`,
  `:deletes`) together with the operator's risk. When a stored step's goal
  already holds and that operator is no longer registered, replay applies
  those recorded effects. Live execution still asks for confirmation when
  the recorded risk is high or the step was irreversible. A step remembered
  before this record existed is still skipped when its operator is gone.

## [0.19.0] — 2026-09-26

### Changed

- When a stored step's goal already holds, replay still applies that
  operator's symbolic effects if they are not already in the state. If the
  preconditions hold, the step runs as usual. If they do not, the plan keeps
  an effects-only step: simulation and live execution apply the add and
  delete lists and do not invoke adapters. A high-risk or irreversible
  operator still requires confirmation on a live run. A step whose effects
  are already present is still skipped.

## [0.18.0] — 2026-09-26

### Changed

- Replaying an archived procedure skips a stored step whose goal already
  holds, then continues with the remaining steps. The trace records
  `Goal already satisfied` for each skip. If a still-needed step has no
  operator or its preconditions fail, planning falls back to Means-Ends
  Analysis.

## [0.17.0] — 2026-09-26

### Changed

- `gp-use-procedure` and `POST /api/archive/use` replay the stored steps on
  the current facts. If a precondition does not hold, no plan is built.
  The successful replay records a deliberative trace (`Reused procedure`).
  `:unchecked t` still rebuilds the procedure without that check.

## [0.16.0] — 2026-09-26

### Added

- Operator API and console for the procedure archive:
  `GET /api/archive`, `POST /api/archive/remember`, `POST /api/archive/use`,
  `POST /api/archive/score`. The console lists procedures by score and can
  remember the current plan, reuse one by name, or record a success or failure.
- A plan payload includes `from_procedure` when it was rebuilt from the archive.
- `POST /api/plan` accepts a JSON array of goals. Previously a console
  request wrapped that array an extra time and the plan failed.

## [0.15.0] — 2026-09-26

### Added

- A live `gp-run` or autonomous `:EXECUTE` of a plan reused from the archive
  records one success or failure on that procedure and saves the archive.
  `gp-simulate` and autonomous `:SIMULATE` leave the score unchanged.
- A fresh Means-Ends plan does not change an existing procedure's score.
  When the reused procedure is still in the archive, autonomy does not
  store a second copy of it.

## [0.14.0] — 2026-09-26

### Added

- `gp-plan` and the autonomy loop consult the procedure archive before
  Means-Ends Analysis. The highest-scoring procedure with the same goals
  is reused only when every stored step still applies to the current facts.
  Otherwise planning falls back to MEA. `:archive nil` or
  `(gp-policy :prefer-archive nil)` keeps a fresh search.
- The deliberative trace records `Reused procedure` and then each stored
  step, so `gp-explain` reports the replay that actually ran.
- `gp-use-procedure` still rebuilds the named procedure without checking
  the live state.

## [0.13.0] — 2026-09-26

### Added

- Persistent procedure archive: successful procedures are written to
  `~/.automa-gp/procedure-archive.sexp` when remembered.
- Score: Laplace success rate times `log(2+successes)`. Failures lower the rate.
  Same name accumulates successes. `gp-archive` ranks by score.
- `gp-use-procedure` rebuilds a plan from the archive without a new search.
- `gp-score-procedure` records a later success or failure and saves again.
- The archive reloads on the next image (`gp-find-procedure` / `gp-archive`).
  `gp-clear-memory` drops the session copy only; the file remains, and
  `gp-archive-load` reads it back.

### Changed

- Version bump to 0.13.0.

## [0.12.0] — 2026-09-26

### Added

- Phase 12 controlled autonomy loop (PROMPT §28):
  `autonomous-step` / `autonomous-loop`, REPL `gp-autonomous-step` /
  `gp-autonomous-loop` / `gp-policy`.
- Explicit authority gates: `:READ` | `:SIMULATE` (default) | `:EXECUTE`.
- Confirmation required for irreversible / high-risk operators unless
  `auto-confirm` or `confirm-fn` authorizes.
- Web: `/api/autonomy`, `/api/autonomy/step`, `/api/autonomy/loop`.
- FiveAM `autonomy-suite`.

### Changed

- Version bump to 0.12.0 — 12-phase roadmap complete at scaffold + working-core.

### Honest limits

- Autonomy ≠ unattended OS destruction; default authority is `:SIMULATE`.
- Adapters remain opt-in; no remote bind / auth layer.

## [0.11.0] — 2026-09-26

### Added

- Phase 11 thin web operator console (Hunchentoot), system `automa-gp/web`.
- HTTP-agnostic JSON API in core: `web-api-handle` / minimal `lisp->json`.
- Console exposes context, facts, goals, plan, simulate, run, explain, events.
- Default bind `127.0.0.1:47391`; `scripts/run-web.sh`.
- FiveAM `web-suite` (handler/API tests, no browser).

### Changed

- Version bump to 0.11.0.

### Not yet

- Full autonomous operation (Phase 12); auth; remote bind by default.

## [0.10.0] — 2026-09-26

### Added

- Phase 10 context-bound event system (`gp-event`, event reactions).
- Flow: emit → reaction (assert facts / add goals) → optional plan.
- REPL: `gp-emit`, `gp-events`, `gp-react`, `gp-add-reaction`,
  `gp-reactions`, `gp-last-reaction`.
- Documents domain registers `file-created` → classify goal (PROMPT §16).
- Events/reactions included in context persistence.
- FiveAM `events-suite`.

### Changed

- Version bump to 0.10.0.

### Not yet

- Web UI (Phase 11), OS file watchers, full autonomy loop (Phase 12).

## [0.9.0] — 2026-09-26

### Added

- Phase 9 domain packs (knowledge/operators/actions without core changes):
  `software`, `documents`, `hardware`, `music`, `geometry`.
- `gp-load-domain` / `gp-domains` registry.
- Demo planners per domain; documents/software can hook Phase-8 adapters.
- FiveAM `domains-suite`.

### Changed

- Version bump to 0.9.0.

### Not yet

- Event system (Phase 10), web UI (Phase 11).

## [0.8.0] — 2026-09-26

### Added

- Phase 8 OS adapters (separated from symbolic core):
  `adapters/filesystem.lisp`, `adapters/processes.lisp`, `adapters/macos.lisp`.
- Abstract primitives via UIOP: `file-exists-p`, `directory-files`, `run-program`,
  `process-running-p`, plus safe helpers for temp-file I/O.
- Operator `:external` meta dispatch on EXECUTE when `*invoke-adapters*` /
  `(gp-run :adapters t)` / `gp-adapters`.
- SIMULATE never invokes adapters; default EXECUTE remains symbolic-only.
- FiveAM `adapters-suite` (temp directories only).

### Changed

- Version bump to 0.8.0.

### Not yet

- Full domain packs (Phase 9).
- Privileged macOS automation beyond thin `open` / hostname helpers.

## [0.7.0] — 2026-09-26

### Added

- Phase 7 multilevel memory: working, knowledge, episodic, procedural.
- Persistence service (separate from planner): `save-snapshot` / `load-snapshot`,
  `persist-context` / `restore-context`, readable sexp files via UIOP.
- Learn reusable procedures from successful plans:
  `gp-remember-procedure`, `procedure->plan`, `gp-find-procedure`.
- REPL: `gp-working`, `gp-knowledge*`, `gp-episodes`, `gp-procedures`,
  `gp-save` / `gp-load`, `gp-save-context` / `gp-load-context`, `gp-clear-memory`.
- Automatic episodic recording on `gp-plan` / `gp-simulate` / `gp-run`
  (disable with `:remember nil`).
- FiveAM `memory-suite`.

### Changed

- Version bump to 0.7.0.
- `gp-reset` clears working + episodic session memory (keeps knowledge/procedural).

### Not yet

- macOS adapters (Phase 8).
- Automatic planner use of procedural memory (retrieval is explicit).
- Parent/child context graph persistence (local context slots only).

## [0.6.0] — 2026-09-26

### Added

- Phase 6 deliberative trace and honest `gp-explain`.
- Workbench examples: tavolo-di-lavoro, Dynamic Context Pipeline framework.
- FiveAM explanation / tavolo / framework suites.

### Not yet

- Durable memory / persistence (Phase 7) — delivered in 0.7.0.
- macOS adapters (Phase 8).

## [0.5.0] — 2026-09-26

### Added

- Phase 5 condition hierarchy: `gp-condition`, `gp-error`, `precondition-failure`,
  `confirmation-required`, `unknown-operator`, `action-failed`.
- Restarts on step failures: `:retry`, `:skip`, `:abort-execution`, `:use-value`,
  `:ask-user`, `:use-alternative`; `:confirm` for irreversible execute.
- `call-with-gp-restarts`, deliberative strategy object, `with-failure-strategy`,
  `gp-failure-strategy`, strategy event log on `execution-result`.
- Plan runners use `handler-bind` + strategy (not catch-all `handler-case`).
- FiveAM `conditions-suite`.

### Changed

- Version bump to 0.5.0.
- Executor integrates Phase-5 restarts for simulate/execute steps.

### Not yet

- Full interactive debugger UX beyond `*ask-user-fn*`.
- Explanation / `gp-explain` (Phase 6).
- macOS adapters (Phase 8).

## [0.4.0] — 2026-09-26

- Phase 4 executor, simulation, state transition.

## [0.3.0] — 2026-09-26

- Phase 3 operators, MEA, planner.

## [0.2.0] — 2026-09-26

- Phase 2 matching, unification, rules, queries.

## [0.1.0] — 2026-09-26

- Phase 1 bootstrap.
