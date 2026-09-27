# AUTOMA GP

Context-centric **symbolic deliberative automaton** in Common Lisp (SBCL /
macOS). Not a chatbot.

```text
CONTEXT → REPRESENT → REASON → PLAN → ACT → OBSERVE → UPDATE
```

Spec: [`docs/PROMPT.md`](docs/PROMPT.md) · Architecture:
[`docs/architecture.md`](docs/architecture.md) · Roadmap: [`ROADMAP.md`](ROADMAP.md).

## Status (v0.123.0)

Working core through phase 12, plus a **persistent procedure archive**.
`gp-plan` reuses a stored procedure whose goals include the request. An
exact match comes first; extra goals of a larger procedure are applied
when its steps still work. Otherwise procedures that each achieve part of
the request are combined: no extra goals first, then procedures that also
achieve something else. Steps whose extra goals cannot be restored are
left aside. A search fills anything left. If a
precondition is missing, stored procedures
that achieve some of those facts restore it. A full cover comes first,
then procedures with no extra goals, then procedures that also achieve
something else. Steps whose extra goals cannot be restored are left aside.
A search fills anything left. That repair may itself reuse a stored
procedure, sixty-one levels deep. The stored steps then continue. A live
`gp-run` updates the score.

Autonomy defaults to `:SIMULATE`.

## Procedure archive (REPL)

```lisp
(gp-remember-procedure :name 'connect-iface)  ; also saves the archive
(gp-archive)                                  ; highest score first
(gp-plan :goals '((connection interface-01 computer))) ; archive, then MEA
(gp-run)                                      ; live result updates the score
(gp-score-procedure 'connect-iface :success t) ; manual score, still available
```

## Autonomy (REPL)

```lisp
(ql:quickload :automa-gp)
(in-package :automa-gp)

(gp-reset)
(gp-load-domain :documents)
(gp-emit '(file-created "document.pdf"))   ; pending event
(gp-policy :authority :simulate)           ; safe default
(gp-autonomous-step)                       ; react → plan → simulate
(gp-last-autonomy)

;; Live mutation only with explicit policy:
(gp-policy :authority :execute :auto-confirm t :adapters nil)
(gp-autonomous-loop :max-steps 4)
```

## Web console

```bash
./scripts/run-web.sh
# → http://127.0.0.1:47391/
```

Operator console includes Autonomy **Step** / **Loop** (authority selectable;
default simulate).

## macOS workbench

Native shell over the same server. The window leads with one next step:
while a plan is incomplete, edit the facts and induce the rule; otherwise
simulate, and confirm before execute. The full narration stays folded
under the trace. **Nota il file** adds one existing file when a reaction
already models it. **Chiedi** accepts a phrase such as
`voglio power-state interface-01 on` only when that goal shape already
exists. The same shape alone, without a leading verb, is enough.
A fixed term at the end, such as `on`, can be left unsaid when only one
goal fits. The operator's name can stand in for the predicate, and so can
a word listed in that operator's `:ask` meta (`accendi` on the hardware
operator `power-on-device`). The same stem counts, so `accendere` matches
`accendi`. `gp-name-operator` declares a word on an operator, and on a
reaction or a rule when that name is the only one. The workbench lists the operators already in the context, together with
those reactions and rules, and declares the word on the one you choose,
even when another of them has the same name. A phrase that fits two
goals names both and records neither; the workbench can record the one
you choose. An unknown first word does not get declared when the other words
already fit a goal and that word is not a term of it: those goals are
named and none is recorded.
A word alone can name a goal that has no variables left when that word
is a term of the goal, or the same stem of that term, including a
superlative such as `prontissimo`, or an adverb such as
`prontamente`, or an abstract noun such as `prontezza`. A noun such as `accensione`
shares the stem of `accendi`, and so does `accendimento`. A word whose stem is exactly a name, such
as `power-one` for `power-on`, is not offered as a new word. Or one exact
piece of its name, and that goal is the only one. When several such
goals contain the word, it names them and records none. The name itself
is not stemmed. A reaction name or a
rule name asks for that goal the same way an operator name does.
**Senza variabili** records the ground operator. A second example joins it
only when the constants stay the same.

```bash
./scripts/run-web.sh
cd macos/AutomaGPWorkbench && swift run
```

```lisp
(gp-narrate)
(gp-add-fact '(device interface-01))
(gp-add-fact '(power-state interface-01 off))
(gp-plan :goals '((power-state interface-01 on))) ; no operator yet: listening
(gp-remove-fact '(power-state interface-01 off))
(gp-add-fact '(power-state interface-01 on))
(gp-induce-rule 'power-on) ; INTERFACE-01 becomes ?X0
;; a second fitting example merges; a different number is refused
(gp-load-domain :documents :seed-demo t)
(gp-notice-path "/path/to/an/existing/file") ; only if a reaction matches
(gp-notice-directory "/path/to/a/directory") ; files only, one look, no run
(gp-ask "voglio power-state interface-01 on") ; only if that shape exists
```

## REPL (primary)

```lisp
(gp-reset)
(gp-load-domain :hardware :seed-demo t)
(gp-plan :goals '((device-configured interface-01)))
(gp-simulate)
(gp-explain)
```

## Tests

```bash
./scripts/run-tests.sh
```

## License

BSD-2-Clause. Copyright (c) 2026 Giacomo Picchiarelli.
