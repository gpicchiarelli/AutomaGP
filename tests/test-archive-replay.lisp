;;;; tests/test-archive-replay.lisp — replaying an archived procedure and repairing its missing preconditions

(in-package #:automa-gp/tests)

(def-suite archive-replay-suite :in automa-gp-suite)
(in-suite archive-replay-suite)

(test archive-replay-applies-step-when-residual-effects-remain
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'from-off)
  (gp-add-fact '(power-state interface-01 on))
  (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
    (is (eq 'from-off (getf (plan-meta plan) :from-procedure)))
    (is (= 2 (plan-length plan)))
    (is (eq 'power-on (getf (first (plan-steps plan)) :operator)))
    (is (null (getf (first (plan-steps plan)) :effects-only)))
    (is (not (fact-p '(power-state interface-01 off) (plan-final-state plan))))
    (is (fact-p '(power-state interface-01 on) (plan-final-state plan))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (not (fact-p '(power-state interface-01 off) (gp-facts))))
    (is (fact-p '(connection interface-01 computer) (gp-facts)))))

(test archive-replay-projects-effects-when-preconditions-are-gone
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (install-procedure!
   (make-procedure
    :name 'charge-then-use
    :goals '((in-use interface-01))
    :operators-used '(charge use-device)
    :success-count 1
    :steps (list
            (list :operator 'charge
                  :bindings '((?d . interface-01))
                  :goal '(charge-state interface-01 full))
            (list :operator 'use-device
                  :bindings '((?d . interface-01))
                  :goal '(in-use interface-01)))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(charge-state interface-01 full))
  (let ((plan (gp-use-procedure :name 'charge-then-use)))
    (is (= 2 (plan-length plan)))
    (is (eq 'charge (getf (first (plan-steps plan)) :operator)))
    (is (eq t (getf (first (plan-steps plan)) :effects-only)))
    (is (fact-p '(ready interface-01) (plan-final-state plan)))
    (is (fact-p '(in-use interface-01) (plan-final-state plan))))
  (let ((text (gp-explain :plan nil)))
    (is (search "Projected effects" text))
    (is (search "CHARGE" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (eq :projected (getf (first (execution-steps sim)) :status)))
    (is (not (fact-p '(ready interface-01) (gp-facts)))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(ready interface-01) (gp-facts)))
    (is (fact-p '(in-use interface-01) (gp-facts)))
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts))))))

(defun %remember-charge-procedure (&key (risk :low))
  "Plan charge-then-use from an empty device and archive it."
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))
                  :risk risk))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use))

(test archive-replay-uses-stored-effects-without-operator
  (gp-clear-memory)
  (let ((proc (%remember-charge-procedure)))
    (let ((step (first (procedure-steps proc))))
      (is (eq 'charge (getf step :operator)))
      (is (eq t (getf step :effects-stored)))
      (is (member '(ready interface-01) (getf step :adds) :test #'equal))
      (is (member '(charge-state interface-01 empty) (getf step :deletes)
                  :test #'equal))))
  (let ((path (merge-pathnames "automa-gp-stored-effects.agp"
                               (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (gp-archive-save path)
           (gp-clear-memory)
           (gp-archive-load path)
           (is (member '(ready interface-01)
                       (getf (first (procedure-steps
                                     (gp-find-procedure 'charge-then-use)))
                             :adds)
                       :test #'equal)))
      (ignore-errors (delete-file path))))
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-fact '(ready interface-01))
  (let ((plan (gp-use-procedure :name 'charge-then-use)))
    (is (eq t (getf (first (plan-steps plan)) :effects-only)))
    (is (eq 'charge (getf (first (plan-steps plan)) :operator)))
    (is (not (fact-p '(charge-state interface-01 empty) (plan-final-state plan))))
    (is (fact-p '(charge-state interface-01 full) (plan-final-state plan)))
    (is (fact-p '(in-use interface-01) (plan-final-state plan))))
  (let ((text (gp-explain :plan nil)))
    (is (search "Projected effects" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (eq :projected (getf (first (execution-steps sim)) :status)))
    (is (fact-p '(charge-state interface-01 empty) (gp-facts))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts))))
    (is (fact-p '(charge-state interface-01 full) (gp-facts)))
    (is (fact-p '(in-use interface-01) (gp-facts)))))

(test archive-stored-effects-confirm-when-operator-is-gone
  (gp-clear-memory)
  (%remember-charge-procedure :risk :high)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-fact '(ready interface-01))
  (gp-use-procedure :name 'charge-then-use)
  (let ((run (gp-run)))
    (is (not (execution-success run))))
  (is (fact-p '(charge-state interface-01 empty) (gp-facts)))
  (let ((run (gp-run :confirm t)))
    (is-true (execution-success run))
    (is (fact-p '(charge-state interface-01 full) (gp-facts)))))

(test archive-replay-applies-recorded-step-when-goal-is-open
  (gp-clear-memory)
  (let ((step (first (procedure-steps (%remember-charge-procedure)))))
    (is (eq t (getf step :preconditions-stored)))
    (is (member '(device interface-01) (getf step :preconditions) :test #'equal))
    (is (member '(charge-state interface-01 empty) (getf step :preconditions)
                :test #'equal)))
  (gp-remove-operator 'charge)
  (let* ((plan (gp-use-procedure :name 'charge-then-use))
         (step (find 'charge (plan-steps plan)
                     :key (lambda (s) (getf s :operator)))))
    (is (eq t (getf step :stored-apply)))
    (is (null (getf step :effects-only)))
    (is (fact-p '(ready interface-01) (plan-final-state plan)))
    (is (fact-p '(in-use interface-01) (plan-final-state plan)))
    (is (not (fact-p '(charge-state interface-01 empty) (plan-final-state plan)))))
  (let ((text (gp-explain :plan nil)))
    (is (search "Recorded effects" text))
    (is (search "CHARGE" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (eq :recorded (getf (first (execution-steps sim)) :status)))
    (is (fact-p '(charge-state interface-01 empty) (gp-facts))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts))))
    (is (fact-p '(charge-state interface-01 full) (gp-facts)))
    (is (fact-p '(in-use interface-01) (gp-facts)))))

(test archive-replay-repairs-a-missing-precondition
  (gp-clear-memory)
  (%remember-charge-procedure)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'fill
                  :preconditions '((device ?d))
                  :add-list '((charge-state ?d empty))))
  (let ((plan (gp-plan :goals '((in-use interface-01)))))
    (is (eq 'charge-then-use (getf (plan-meta plan) :from-procedure)))
    (is (eq 'fill (getf (first (plan-steps plan)) :operator)))
    (is (member 'charge (plan-operators-used plan)))
    (is (fact-p '(in-use interface-01) (plan-final-state plan)))
    (is (not (fact-p '(charge-state interface-01 empty) (plan-final-state plan)))))
  (let ((text (gp-explain :plan nil)))
    (is (search "Missing precondition" text))
    (is (search "FILL" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts)))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(ready interface-01) (gp-facts)))
    (is (fact-p '(in-use interface-01) (gp-facts)))))

(test archive-replay-repairs-then-uses-recorded-step
  (gp-clear-memory)
  (%remember-charge-procedure)
  (gp-remove-operator 'charge)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'fill
                  :preconditions '((device ?d))
                  :add-list '((charge-state ?d empty))))
  (let* ((plan (gp-use-procedure :name 'charge-then-use))
         (steps (plan-steps plan)))
    (is (eq 'fill (getf (first steps) :operator)))
    (is (eq 'charge (getf (second steps) :operator)))
    (is (eq t (getf (second steps) :stored-apply)))
    (is (fact-p '(in-use interface-01) (plan-final-state plan))))
  (is (search "Repair step" (gp-explain :plan nil)))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(in-use interface-01) (gp-facts)))
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts))))))

(test archive-repair-reuses-procedure-for-the-missing-fact
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (let* ((plan (gp-use-procedure :name 'charge-then-use))
         (steps (plan-steps plan)))
    (is (eq 'charge-then-use (getf (plan-meta plan) :from-procedure)))
    (is (eq 'pour (getf (first steps) :operator)))
    (is (eq t (getf (first steps) :stored-apply)))
    (is (eq 'charge (getf (second steps) :operator)))
    (is (fact-p '(in-use interface-01) (plan-final-state plan))))
  (let ((text (gp-explain :plan nil)))
    (is (search "reused procedure" text))
    (is (search "REFILL" text))
    (is (search "POUR" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (fact-p '(reservoir interface-01 full) (gp-facts)))
    (is (not (fact-p '(in-use interface-01) (gp-facts)))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(in-use interface-01) (gp-facts)))
    (is (fact-p '(ready interface-01) (gp-facts)))
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts))))
    (is (not (fact-p '(reservoir interface-01 full) (gp-facts))))))

(test archive-repair-reuses-a-nested-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'prime
                  :preconditions '((device ?d) (tank ?d sealed))
                  :add-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(tank interface-01 sealed))
  (gp-plan :goals '((reservoir interface-01 full)) :archive nil)
  (gp-remember-procedure :name 'prime-reservoir)
  (gp-remove-operator 'prime)
  (gp-add-fact '(reservoir interface-01 full))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'refill)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(reservoir interface-01 full))
  (let* ((plan (gp-use-procedure :name 'charge-then-use))
         (steps (plan-steps plan)))
    (is (eq 'prime (getf (first steps) :operator)))
    (is (eq t (getf (first steps) :stored-apply)))
    (is (eq 'pour (getf (second steps) :operator)))
    (is (eq t (getf (second steps) :stored-apply)))
    (is (eq 'charge (getf (third steps) :operator)))
    (is (fact-p '(in-use interface-01) (plan-final-state plan))))
  (let ((text (gp-explain :plan nil)))
    (is (search "reused procedure" text))
    (is (search "REFILL" text))
    (is (search "PRIME-RESERVOIR" text))
    (is (search "PRIME" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (fact-p '(tank interface-01 sealed) (gp-facts)))
    (is (not (fact-p '(reservoir interface-01 full) (gp-facts))))
    (is (not (fact-p '(in-use interface-01) (gp-facts)))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(in-use interface-01) (gp-facts)))
    (is (fact-p '(tank interface-01 sealed) (gp-facts)))
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts))))
    (is (not (fact-p '(reservoir interface-01 full) (gp-facts))))))

(test archive-repair-reuses-procedures-up-to-the-archive-depth
  "Using CHARGE-THEN-USE repairs one missing precondition per archived
procedure, at every depth the archive allows; the plan, the explanation,
a simulation and a live run all reflect the repaired chain."
  (loop for depth from 1 to *procedure-repair-archive-depth*
        do (gp-clear-memory)
           (let* ((chain (%build-repair-chain depth))
                  (plan (gp-use-procedure :name 'charge-then-use))
                  (steps (plan-steps plan)))
             (is (eq 'charge-then-use (getf (plan-meta plan) :from-procedure))
                 "depth ~D: plan is not from CHARGE-THEN-USE" depth)
             (loop for link in (getf chain :links)
                   for step in steps
                   do (is (eq link (getf step :operator))
                          "depth ~D: expected ~A, got ~A"
                          depth link (getf step :operator))
                      (is (eq t (getf step :stored-apply))
                          "depth ~D: ~A is not a stored apply" depth link))
             (is (eq 'charge (getf (nth depth steps) :operator))
                 "depth ~D: CHARGE does not follow the repaired links" depth)
             (is (fact-p (getf chain :in-use) (plan-final-state plan))
                 "depth ~D: final state lacks IN-USE" depth)
             (let ((text (gp-explain :plan nil)))
               (is (search "reused procedure" text)
                   "depth ~D: explanation does not say a procedure was reused"
                   depth)
               (dolist (name (getf chain :procedures))
                 (is (search (symbol-name name) text)
                     "depth ~D: explanation does not mention ~A" depth name)))
             (let ((sim (gp-simulate)))
               (is-true (execution-success sim)
                        "depth ~D: simulation failed" depth)
               (is (fact-p (getf chain :root) (gp-facts))
                   "depth ~D: simulation removed the root fact" depth)
               (dolist (fact (getf chain :removed))
                 (is (not (fact-p fact (gp-facts)))
                     "depth ~D: simulation asserted ~A" depth fact))
               (is (not (fact-p (getf chain :in-use) (gp-facts)))
                   "depth ~D: simulation asserted IN-USE" depth))
             (let ((run (gp-run)))
               (is-true (execution-success run) "depth ~D: run failed" depth)
               (is (fact-p (getf chain :in-use) (gp-facts))
                   "depth ~D: run did not reach IN-USE" depth)
               (is (not (fact-p (getf chain :consumed) (gp-facts)))
                   "depth ~D: the innermost link did not consume ~A"
                   depth (getf chain :consumed))
               (dolist (fact (getf chain :restored))
                 (is (fact-p fact (gp-facts))
                     "depth ~D: ~A was not restored" depth fact))
               (is (not (fact-p (getf chain :charge-empty) (gp-facts)))
                   "depth ~D: CHARGE-STATE EMPTY survived the run" depth)))))

(test archive-repair-stops-past-the-archive-depth
  "One level past *PROCEDURE-REPAIR-ARCHIVE-DEPTH* the repair is refused,
the goal stays open and the root fact is untouched."
  (gp-clear-memory)
  (let ((chain (%build-repair-chain (1+ *procedure-repair-archive-depth*))))
    (signals error (gp-use-procedure :name 'charge-then-use))
    (is (not (fact-p (getf chain :in-use) (gp-facts))))
    (is (fact-p (getf chain :root) (gp-facts)))))

(test archive-repair-reuses-procedure-that-covers-the-missing-fact
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty) (note ?d poured))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((charge-state interface-01 empty)
                    (note interface-01 poured))
           :archive nil)
  (gp-remember-procedure :name 'refill-noted)
  (gp-remove-operator 'pour)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (let* ((plan (gp-use-procedure :name 'charge-then-use))
         (steps (plan-steps plan)))
    (is (eq 'pour (getf (first steps) :operator)))
    (is (eq t (getf (first steps) :stored-apply)))
    (is (fact-p '(note interface-01 poured) (plan-final-state plan)))
    (is (fact-p '(in-use interface-01) (plan-final-state plan))))
  (let ((text (gp-explain :plan nil)))
    (is (search "REFILL-NOTED" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (fact-p '(reservoir interface-01 full) (gp-facts)))
    (is (not (fact-p '(note interface-01 poured) (gp-facts)))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(in-use interface-01) (gp-facts)))
    (is (fact-p '(note interface-01 poured) (gp-facts)))
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts))))
    (is (not (fact-p '(reservoir interface-01 full) (gp-facts))))))

(test archive-repair-prefers-exact-goals-over-a-larger-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'pour-exact
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'exact-refill)
  (gp-remove-operator 'pour-exact)
  (gp-add-operator
   (make-operator :name 'pour-wide
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty) (note ?d poured))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)
                    (note interface-01 poured))
           :archive nil)
  (gp-remember-procedure :name 'wide-refill)
  (gp-score-procedure 'wide-refill :success t)
  (gp-score-procedure 'wide-refill :success t)
  (gp-remove-operator 'pour-wide)
  (is (> (procedure-score (gp-find-procedure 'wide-refill))
         (procedure-score (gp-find-procedure 'exact-refill))))
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (let* ((plan (gp-use-procedure :name 'charge-then-use))
         (steps (plan-steps plan)))
    (is (eq 'pour-exact (getf (first steps) :operator)))
    (is (not (fact-p '(note interface-01 poured) (plan-final-state plan)))))
  (let ((text (gp-explain :plan nil)))
    (is (search "EXACT-REFILL" text))
    (is (not (search "WIDE-REFILL" text)))))

(test archive-repair-combines-procedures-that-each-cover-part
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'fill-empty)
  (gp-remove-operator 'pour)
  (gp-add-operator
   (make-operator :name 'attach
                  :preconditions '((device ?d) (socket ?d free))
                  :add-list '((cable ?d connected))
                  :delete-list '((socket ?d free))))
  (gp-add-fact '(socket interface-01 free))
  (gp-plan :goals '((cable interface-01 connected)) :archive nil)
  (gp-remember-procedure :name 'plug-cable)
  (gp-remove-operator 'attach)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-fact '(cable interface-01 connected))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d)
                                   (charge-state ?d empty)
                                   (cable ?d connected))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(cable interface-01 connected))
  (let* ((plan (gp-use-procedure :name 'charge-then-use))
         (steps (plan-steps plan)))
    (is (eq 'pour (getf (first steps) :operator)))
    (is (eq t (getf (first steps) :stored-apply)))
    (is (eq 'attach (getf (second steps) :operator)))
    (is (eq t (getf (second steps) :stored-apply)))
    (is (eq 'charge (getf (third steps) :operator)))
    (is (fact-p '(in-use interface-01) (plan-final-state plan))))
  (let ((text (gp-explain :plan nil)))
    (is (search "FILL-EMPTY" text))
    (is (search "PLUG-CABLE" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (fact-p '(reservoir interface-01 full) (gp-facts)))
    (is (fact-p '(socket interface-01 free) (gp-facts)))
    (is (not (fact-p '(in-use interface-01) (gp-facts)))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(in-use interface-01) (gp-facts)))
    (is (fact-p '(cable interface-01 connected) (gp-facts)))
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts))))
    (is (not (fact-p '(reservoir interface-01 full) (gp-facts))))
    (is (not (fact-p '(socket interface-01 free) (gp-facts))))))

(test archive-repair-prefers-one-covering-procedure-over-parts
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'fill-empty)
  (gp-score-procedure 'fill-empty :success t)
  (gp-remove-operator 'pour)
  (gp-add-operator
   (make-operator :name 'attach
                  :preconditions '((device ?d) (socket ?d free))
                  :add-list '((cable ?d connected))
                  :delete-list '((socket ?d free))))
  (gp-add-fact '(socket interface-01 free))
  (gp-plan :goals '((cable interface-01 connected)) :archive nil)
  (gp-remember-procedure :name 'plug-cable)
  (gp-score-procedure 'plug-cable :success t)
  (gp-remove-operator 'attach)
  (gp-add-operator
   (make-operator :name 'prep-both
                  :preconditions '((device ?d) (reservoir ?d full) (socket ?d free))
                  :add-list '((charge-state ?d empty) (cable ?d connected))
                  :delete-list '((reservoir ?d full) (socket ?d free))))
  (gp-plan :goals '((charge-state interface-01 empty)
                    (cable interface-01 connected))
           :archive nil)
  (gp-remember-procedure :name 'prep-all)
  (is (> (procedure-score (gp-find-procedure 'fill-empty))
         (procedure-score (gp-find-procedure 'prep-all))))
  (gp-remove-operator 'prep-both)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-fact '(cable interface-01 connected))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d)
                                   (charge-state ?d empty)
                                   (cable ?d connected))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(cable interface-01 connected))
  (let ((steps (plan-steps (gp-use-procedure :name 'charge-then-use))))
    (is (eq 'prep-both (getf (first steps) :operator))))
  (let ((text (gp-explain :plan nil)))
    (is (search "PREP-ALL" text))
    (is (not (search "FILL-EMPTY" text)))))

(test archive-repair-uses-search-for-the-part-left-over
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'fill-empty)
  (gp-remove-operator 'pour)
  (gp-add-operator
   (make-operator :name 'attach
                  :preconditions '((device ?d) (socket ?d free))
                  :add-list '((cable ?d connected))
                  :delete-list '((socket ?d free))))
  (gp-add-fact '(socket interface-01 free))
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-fact '(cable interface-01 connected))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d)
                                   (charge-state ?d empty)
                                   (cable ?d connected))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(cable interface-01 connected))
  (let ((steps (plan-steps (gp-use-procedure :name 'charge-then-use))))
    (is (eq 'pour (getf (first steps) :operator)))
    (is (eq t (getf (first steps) :stored-apply)))
    (is (eq 'attach (getf (second steps) :operator)))
    (is (not (getf (second steps) :stored-apply))))
  (is (search "FILL-EMPTY" (gp-explain :plan nil)))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(cable interface-01 connected) (gp-facts)))
    (is (fact-p '(in-use interface-01) (gp-facts)))))

(test archive-repair-reuses-procedure-with-an-extra-goal
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'pour-noted
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty) (note ?d poured))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((charge-state interface-01 empty)
                    (note interface-01 poured))
           :archive nil)
  (gp-remember-procedure :name 'fill-noted)
  (gp-remove-operator 'pour-noted)
  (gp-add-operator
   (make-operator :name 'attach
                  :preconditions '((device ?d) (socket ?d free))
                  :add-list '((cable ?d connected))
                  :delete-list '((socket ?d free))))
  (gp-add-fact '(socket interface-01 free))
  (gp-plan :goals '((cable interface-01 connected)) :archive nil)
  (gp-remember-procedure :name 'plug-cable)
  (gp-remove-operator 'attach)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-fact '(cable interface-01 connected))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d)
                                   (charge-state ?d empty)
                                   (cable ?d connected))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(cable interface-01 connected))
  (let* ((plan (gp-use-procedure :name 'charge-then-use))
         (steps (plan-steps plan)))
    (is (eq 'attach (getf (first steps) :operator)))
    (is (eq 'pour-noted (getf (second steps) :operator)))
    (is (eq t (getf (second steps) :stored-apply)))
    (is (fact-p '(note interface-01 poured) (plan-final-state plan)))
    (is (fact-p '(in-use interface-01) (plan-final-state plan))))
  (let ((text (gp-explain :plan nil)))
    (is (search "FILL-NOTED" text))
    (is (search "PLUG-CABLE" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (not (fact-p '(note interface-01 poured) (gp-facts)))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(note interface-01 poured) (gp-facts)))
    (is (fact-p '(in-use interface-01) (gp-facts)))
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts))))))

(test archive-repair-prefers-a-procedure-without-extra-goals
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'fill-empty)
  (gp-remove-operator 'pour)
  (gp-add-operator
   (make-operator :name 'pour-noted
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty) (note ?d poured))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)
                    (note interface-01 poured))
           :archive nil)
  (gp-remember-procedure :name 'fill-noted)
  (gp-score-procedure 'fill-noted :success t)
  (gp-score-procedure 'fill-noted :success t)
  (gp-remove-operator 'pour-noted)
  (is (> (procedure-score (gp-find-procedure 'fill-noted))
         (procedure-score (gp-find-procedure 'fill-empty))))
  (gp-add-operator
   (make-operator :name 'attach
                  :preconditions '((device ?d) (socket ?d free))
                  :add-list '((cable ?d connected))
                  :delete-list '((socket ?d free))))
  (gp-add-fact '(socket interface-01 free))
  (gp-plan :goals '((cable interface-01 connected)) :archive nil)
  (gp-remember-procedure :name 'plug-cable)
  (gp-remove-operator 'attach)
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-fact '(cable interface-01 connected))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d)
                                   (charge-state ?d empty)
                                   (cable ?d connected))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (gp-remove-fact '(cable interface-01 connected))
  (let* ((plan (gp-use-procedure :name 'charge-then-use))
         (steps (plan-steps plan)))
    (is (eq 'pour (getf (first steps) :operator)))
    (is (not (fact-p '(note interface-01 poured) (plan-final-state plan)))))
  (let ((text (gp-explain :plan nil)))
    (is (search "FILL-EMPTY" text))
    (is (not (search "FILL-NOTED" text)))))

(test archive-repair-keeps-useful-steps-when-an-extra-goal-is-blocked
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'stamp
                  :preconditions '((device ?d) (ink ?d ready))
                  :add-list '((note ?d poured))))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(ink interface-01 ready))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((note interface-01 poured)
                    (charge-state interface-01 empty))
           :archive nil)
  (gp-remember-procedure :name 'fill-noted)
  (is (= 2 (length (procedure-steps (gp-find-procedure 'fill-noted)))))
  (gp-remove-operator 'stamp)
  (gp-remove-operator 'pour)
  (gp-remove-fact '(ink interface-01 ready))
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (let* ((plan (gp-use-procedure :name 'charge-then-use))
         (steps (plan-steps plan))
         (operators (mapcar (lambda (step) (getf step :operator)) steps)))
    (is (eq 'pour (getf (first steps) :operator)))
    (is (not (member 'stamp operators)))
    (is (not (fact-p '(note interface-01 poured) (plan-final-state plan))))
    (is (fact-p '(in-use interface-01) (plan-final-state plan))))
  (let ((text (gp-explain :plan nil)))
    (is (search "Left aside" text))
    (is (search "STAMP" text))
    (is (search "FILL-NOTED" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (not (fact-p '(note interface-01 poured) (gp-facts))))
    (is (not (fact-p '(in-use interface-01) (gp-facts)))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(in-use interface-01) (gp-facts)))
    (is (not (fact-p '(note interface-01 poured) (gp-facts))) )
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts))))))

(test archive-repair-rejects-when-the-useful-step-is-also-blocked
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'stamp
                  :preconditions '((device ?d) (ink ?d ready))
                  :add-list '((note ?d poured))))
  (gp-add-operator
   (make-operator :name 'pour
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(ink interface-01 ready))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((note interface-01 poured)
                    (charge-state interface-01 empty))
           :archive nil)
  (gp-remember-procedure :name 'fill-noted)
  (gp-remove-operator 'stamp)
  (gp-remove-operator 'pour)
  (gp-remove-fact '(ink interface-01 ready))
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-add-fact '(charge-state interface-01 empty))
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (gp-plan :goals '((in-use interface-01)) :archive nil)
  (gp-remember-procedure :name 'charge-then-use)
  (gp-remove-fact '(charge-state interface-01 empty))
  (signals error (gp-use-procedure :name 'charge-then-use))
  (is (not (fact-p '(in-use interface-01) (gp-facts)))))

(test archive-recorded-step-rejects-missing-precondition
  (gp-clear-memory)
  (%remember-charge-procedure)
  (gp-remove-operator 'charge)
  (gp-remove-fact '(charge-state interface-01 empty))
  (signals error (gp-use-procedure :name 'charge-then-use)))

(test archive-recorded-step-confirms-high-risk
  (gp-clear-memory)
  (%remember-charge-procedure :risk :high)
  (gp-remove-operator 'charge)
  (gp-use-procedure :name 'charge-then-use)
  (let ((run (gp-run)))
    (is (not (execution-success run))))
  (is (fact-p '(charge-state interface-01 empty) (gp-facts)))
  (let ((run (gp-run :confirm t)))
    (is-true (execution-success run))
    (is (fact-p '(in-use interface-01) (gp-facts)))))

(test archive-effects-only-still-confirms-high-risk
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'charge
                  :preconditions '((device ?d) (charge-state ?d empty))
                  :add-list '((charge-state ?d full) (ready ?d))
                  :delete-list '((charge-state ?d empty))
                  :risk :high))
  (gp-add-operator
   (make-operator :name 'use-device
                  :preconditions '((device ?d) (ready ?d))
                  :add-list '((in-use ?d))))
  (install-procedure!
   (make-procedure
    :name 'charge-then-use
    :goals '((in-use interface-01))
    :success-count 1
    :steps (list
            (list :operator 'charge
                  :bindings '((?d . interface-01))
                  :goal '(charge-state interface-01 full))
            (list :operator 'use-device
                  :bindings '((?d . interface-01))
                  :goal '(in-use interface-01)))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(charge-state interface-01 full))
  (gp-use-procedure :name 'charge-then-use)
  (let ((run (gp-run)))
    (is (not (execution-success run))))
  (is (not (fact-p '(ready interface-01) (gp-facts))))
  (let ((run (gp-run :confirm t)))
    (is-true (execution-success run))
    (is (fact-p '(ready interface-01) (gp-facts)))))

;;; --- Procedures made of recorded steps: no operator is registered, so
;;; --- only the archive can restore what a step needs.

(test archive-repair-tries-the-next-procedure-when-the-rest-cannot-follow
  "A-FIRST ranks first and uses up the token B-SECOND needs. The repair
must then try B-SECOND first instead of giving up."
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device d1))
  (gp-add-fact '(token d1 yes))
  (%install-recorded 'a-first '((a d1 yes))
                     (%recorded-step 'op-a '((token d1 yes)) '((a d1 yes))
                                     '((token d1 yes))))
  (%install-recorded 'b-second '((b d1 yes))
                     (%recorded-step 'op-b '((token d1 yes)) '((b d1 yes))))
  (%install-recorded 'top '((done d1 yes))
                     (%recorded-step 'op-top '((a d1 yes) (b d1 yes))
                                     '((done d1 yes))))
  (let ((plan (gp-use-procedure :name 'top)))
    (is (equal '(op-b op-a op-top) (%step-operators plan)))
    (is (fact-p '(done d1 yes) (plan-final-state plan))))
  (is-true (execution-success (gp-run)))
  (is (fact-p '(done d1 yes) (gp-facts))))

(test archive-narrowed-replay-does-not-reuse-its-own-procedure
  "KIT cannot run in full: OP-X needs a fact only OP-G1 produces later. The
replay narrowed to the request leaves OP-X aside; repairing OP-G2 inside it
must not bring the whole of KIT back in."
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device d1))
  (%install-recorded 'kit '((x d1 yes) (g1 d1 yes) (g2 d1 yes))
                     (%recorded-step 'op-x '((k d1 yes)) '((x d1 yes)))
                     (%recorded-step 'op-g1 '((device d1))
                                     '((g1 d1 yes) (k d1 yes)))
                     (%recorded-step 'op-g2 '((x d1 yes)) '((g2 d1 yes))))
  (let* ((plan (gp-plan :goals '((g1 d1 yes) (g2 d1 yes))))
         (operators (%step-operators plan)))
    (is (<= (count 'op-g2 operators) 1) "OP-G2 is planned twice: ~S" operators)
    (is (not (and (member 'op-x operators)
                  (search "Left aside" (gp-explain :plan nil))))
        "OP-X is both left aside and planned: ~S" operators)))

(test archive-combined-plan-records-an-empty-initial-state
  (gp-clear-memory)
  (gp-reset)
  (%install-recorded 'make-a '((a d1 yes))
                     (%recorded-step 'op-a nil '((a d1 yes))))
  (%install-recorded 'make-b '((b d1 yes))
                     (%recorded-step 'op-b nil '((b d1 yes))))
  (let ((plan (gp-plan :goals '((a d1 yes) (b d1 yes)))))
    (is (equal '(make-a make-b) (plan-reused-procedure-names plan)))
    (is (null (plan-initial-state plan)))
    (is (fact-p '(b d1 yes) (plan-final-state plan)))))

(test archive-plan-leaves-one-trace-however-many-procedures-it-replays
  "Nested repairs and combined pieces are replays inside one plan. A replay
that is tried and dropped leaves no trace at all."
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device d1))
  (%install-recorded 'make-a '((a d1 yes))
                     (%recorded-step 'op-a '((device d1)) '((a d1 yes))))
  (%install-recorded 'make-b '((b d1 yes))
                     (%recorded-step 'op-b '((a d1 yes)) '((b d1 yes))))
  (%install-recorded 'make-c '((c d1 yes))
                     (%recorded-step 'op-c '((b d1 yes)) '((c d1 yes))))
  (%install-recorded 'make-d '((d d1 yes))
                     (%recorded-step 'op-d1 '((a d1 yes)) '((half d1 yes)))
                     (%recorded-step 'op-d2 '((never d1 yes)) '((d d1 yes))))
  (flet ((traces () (length (gp-trace-history))))
    (let ((before (traces)))
      (is (equal '(op-a op-b op-c)
                 (%step-operators (gp-use-procedure :name 'make-c))))
      (is (= (1+ before) (traces)))
      (is (eq (gp-last-trace) (getf (plan-meta (gp-last-plan)) :trace))))
    (let ((before (traces)))
      (is (equal '(make-a make-b)
                 (plan-reused-procedure-names
                  (gp-plan :goals '((a d1 yes) (b d1 yes))))))
      (is (= (1+ before) (traces))))
    (let ((before (traces))
          (last (gp-last-trace)))
      (signals error (gp-use-procedure :name 'make-d))
      (is (= before (traces)))
      (is (eq last (gp-last-trace))))))

(test remembered-procedure-drops-the-marks-of-the-replay-it-came-from
  ":STORED-APPLY and :EFFECTS-ONLY describe one replay. Stored in the
archive they would make an unchecked plan skip the operator's own check."
  (gp-clear-memory)
  (%remember-charge-procedure)
  (gp-remove-operator 'charge)
  (let ((plan (gp-use-procedure :name 'charge-then-use)))
    (is (eq t (getf (first (plan-steps plan)) :stored-apply)))
    (let ((again (gp-remember-procedure :name 'again)))
      (is (notany (lambda (step)
                    (or (getf step :stored-apply) (getf step :effects-only)))
                  (procedure-steps again)))
      (is (eq t (getf (first (plan-steps plan)) :stored-apply))))))
