;;;; tests/test-archive.lisp — persistent scored procedure archive: scoring, files, reuse in planning

(in-package #:automa-gp/tests)

(def-suite archive-suite :in automa-gp-suite)
(in-suite archive-suite)

(defun %archive-studio ()
  "Fresh context and a successful connect plan. Keeps the procedure archive."
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (gp-add-operator
   (make-operator :name 'connect
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((connection ?d computer))))
  (gp-plan :goals '((connection interface-01 computer))))

(defun %recorded-step (operator needs adds &optional deletes)
  "A plan step that replays from its record alone: OPERATOR need not be
registered. Its goal is the first of ADDS."
  (list :operator operator
        :goal (first adds)
        :adds adds
        :deletes deletes
        :effects-stored t
        :preconditions needs
        :preconditions-stored t))

(defun %install-recorded (name goals &rest steps)
  "Archive a procedure called NAME that achieves GOALS by STEPS."
  (install-procedure! (make-procedure :name name :goals goals :steps steps)))

(defun %step-operators (plan)
  (mapcar (lambda (step) (getf step :operator)) (plan-steps plan)))

(defun %procedure-names (&optional (procedures (gp-procedures)))
  "Names of PROCEDURES as strings, sorted."
  (sort (mapcar (lambda (procedure) (symbol-name (procedure-name procedure)))
                procedures)
        #'string<))

(defvar *archive-file-count* 0
  "Makes the archive files of one test run distinct.")

(defun %call-with-archive-file (function &key autoload)
  "Call FUNCTION on the path of an archive file that does not exist yet.
While it runs autosave is on, the session store is empty and has not read
the file, and autoload is AUTOLOAD. The file is deleted afterwards."
  (let* ((path (merge-pathnames
                (format nil "automa-gp-archive-~D-~D.agp"
                        (get-universal-time) (incf *archive-file-count*))
                (uiop:temporary-directory)))
         (*procedure-archive-path* path)
         (*procedure-archive-autosave* t)
         (*procedure-archive-autoload* autoload)
         (*procedural-memory* nil)
         (automa-gp::*procedure-archive-loaded* nil))
    (unwind-protect (funcall function path)
      (ignore-errors (delete-file path)))))

(defmacro with-archive-file ((path &key autoload) &body body)
  "Run BODY with PATH bound as %CALL-WITH-ARCHIVE-FILE describes."
  `(%call-with-archive-file (lambda (,path) ,@body) :autoload ,autoload))

(defun %write-archive-text (path text)
  (with-open-file (out path :direction :output :if-exists :supersede)
    (write-string text out)))

(defun %skip-archive (condition)
  (declare (ignore condition))
  (invoke-restart :skip))

(test archive-scores-repeat-success-above-a-failure
  (gp-clear-memory)
  (%archive-studio)
  (let ((once (gp-remember-procedure :name 'once)))
    (is (= 1 (procedure-success-count once)))
    (is (= 0 (procedure-failure-count once))))
  (%archive-studio)
  (let ((twice (gp-remember-procedure :name 'once)))
    (is (= 2 (procedure-success-count twice))))
  (gp-remember-procedure :name 'shaky)
  (gp-score-procedure 'shaky :success nil)
  (let ((best (gp-archive-best '((connection interface-01 computer)))))
    (is (eq 'once (procedure-name best)))
    (is (> (procedure-score (gp-find-procedure 'once))
           (procedure-score (gp-find-procedure 'shaky)))))
  (let ((ranked (gp-archive)))
    (is (eq 'once (procedure-name (first ranked))))))

(test archive-file-roundtrip-and-use-without-search
  (let* ((path (merge-pathnames
                (format nil "automa-gp-archive-~A.agp" (get-universal-time))
                (uiop:temporary-directory)))
         (*procedure-archive-path* path)
         (*procedure-archive-autosave* t)
         (*procedure-archive-autoload* nil))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (%archive-studio)
           (gp-remember-procedure :name 'connect-iface)
           (is (probe-file path))
           (gp-clear-memory)
           (is (null (gp-find-procedure 'connect-iface)))
           (gp-archive-load path)
           (let ((found (gp-find-procedure 'connect-iface)))
             (is (procedure-p found))
             (is (= 1 (procedure-success-count found)))
             (is (plusp (procedure-score found))))
           (gp-reset)
           (signals error (gp-use-procedure :name 'connect-iface))
           (gp-add-fact '(device interface-01))
           (gp-add-fact '(power-state interface-01 off))
           (gp-add-operator
            (make-operator :name 'power-on
                           :preconditions '((device ?d) (power-state ?d off))
                           :add-list '((power-state ?d on))
                           :delete-list '((power-state ?d off))))
           (gp-add-operator
            (make-operator :name 'connect
                           :preconditions '((device ?d) (power-state ?d on))
                           :add-list '((connection ?d computer))))
           (let ((plan (gp-use-procedure :name 'connect-iface)))
             (is-true (plan-success plan))
             (is (= 2 (plan-length plan)))
             (is (eq 'connect-iface (getf (plan-meta plan) :from-procedure)))
             (is (fact-p '(connection interface-01 computer)
                         (plan-final-state plan)))
             (is (eq plan (gp-last-plan))))
           (is (search "Reused procedure" (gp-explain :plan nil))))
      (ignore-errors (delete-file path)))))

(test archive-autoload-after-clear-image-memory
  (let* ((path (merge-pathnames
                (format nil "automa-gp-archive-auto-~A.agp" (get-universal-time))
                (uiop:temporary-directory)))
         (*procedure-archive-path* path)
         (*procedure-archive-autosave* t)
         (*procedure-archive-autoload* t))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (%archive-studio)
           (gp-remember-procedure :name 'auto-connect)
           (setf *procedural-memory* nil
                 automa-gp::*procedure-archive-loaded* nil)
           (is (eq 'auto-connect
                   (procedure-name (gp-find-procedure 'auto-connect)))))
      (ignore-errors (delete-file path)))))

(test archive-plan-reuses-applicable-procedure
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'once)
  (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
    (is (eq 'once (getf (plan-meta plan) :from-procedure)))
    (is (= 2 (plan-length plan)))
    (is (fact-p '(connection interface-01 computer) (plan-final-state plan)))
    (is (fact-p '(power-state interface-01 off) (gp-facts))))
  (multiple-value-bind (text tr) (gp-explain :plan nil)
    (is (deliberative-trace-p tr))
    (is (search "Reused procedure" text))
    (is (search "POWER-ON" text))))

(test archive-use-ends-plan-failed-listening
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'once)
  (let ((failed (gp-plan :goals '((ready interface-01)) :archive nil)))
    (is (not (plan-success failed)))
    (is (observation-active-p))
    (is (eq :plan-failed (getf (gp-observation) :reason))))
  (let ((plan (gp-use-procedure :name 'once)))
    (is (plan-success plan))
    (is (eq 'once (getf (plan-meta plan) :from-procedure)))
    (is (not (observation-active-p)))
    (is (null *observed-before*))
    (signals error (gp-induce-rule 'stale))
    (signals error (gp-learn-action 'stale)))
  (gp-listen :reason :manual)
  (is (observation-active-p))
  (gp-use-procedure :name 'once)
  (is (observation-active-p))
  (is (eq :manual (getf (gp-observation) :reason))))

(test archive-plan-reuses-procedure-whose-goals-include-the-request
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'draw-noted
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty) (note ?d poured))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((charge-state interface-01 empty)
                    (note interface-01 poured))
           :archive nil)
  (gp-remember-procedure :name 'wide-fill)
  (let ((plan (gp-plan :goals '((charge-state interface-01 empty)))))
    (is (eq 'wide-fill (getf (plan-meta plan) :from-procedure)))
    (is (eq 'draw-noted (getf (first (plan-steps plan)) :operator)))
    (is (fact-p '(note interface-01 poured) (plan-final-state plan)))
    (is (fact-p '(charge-state interface-01 empty) (plan-final-state plan)))
    (is (not (fact-p '(note interface-01 poured) (gp-facts)))))
  (let ((text (gp-explain :plan nil)))
    (is (search "WIDE-FILL" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (not (fact-p '(note interface-01 poured) (gp-facts))))
    (is (fact-p '(reservoir interface-01 full) (gp-facts))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(note interface-01 poured) (gp-facts)))
    (is (fact-p '(charge-state interface-01 empty) (gp-facts)))
    (is (not (fact-p '(reservoir interface-01 full) (gp-facts))))))

(test archive-plan-prefers-exact-goals-over-a-covering-procedure
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'draw
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((charge-state interface-01 empty)) :archive nil)
  (gp-remember-procedure :name 'exact-fill)
  (gp-add-operator
   (make-operator :name 'draw-noted
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty) (note ?d poured))
                  :delete-list '((reservoir ?d full))))
  (gp-plan :goals '((charge-state interface-01 empty)
                    (note interface-01 poured))
           :archive nil)
  (gp-remember-procedure :name 'wide-fill)
  (gp-score-procedure 'wide-fill :success t)
  (gp-score-procedure 'wide-fill :success t)
  (is (> (procedure-score (gp-find-procedure 'wide-fill))
         (procedure-score (gp-find-procedure 'exact-fill))))
  (let ((plan (gp-plan :goals '((charge-state interface-01 empty)))))
    (is (eq 'exact-fill (getf (plan-meta plan) :from-procedure)))
    (is (eq 'draw (getf (first (plan-steps plan)) :operator)))
    (is (not (fact-p '(note interface-01 poured) (plan-final-state plan))))))

(test archive-plan-skips-a-covering-procedure-that-does-not-apply
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator
   (make-operator :name 'draw-noted
                  :preconditions '((device ?d) (reservoir ?d full))
                  :add-list '((charge-state ?d empty) (note ?d poured))
                  :delete-list '((reservoir ?d full))))
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(reservoir interface-01 full))
  (gp-plan :goals '((charge-state interface-01 empty)
                    (note interface-01 poured))
           :archive nil)
  (gp-remember-procedure :name 'wide-fill)
  (gp-remove-operator 'draw-noted)
  (gp-remove-fact '(reservoir interface-01 full))
  (gp-add-fact '(bucket interface-01 full))
  (gp-add-operator
   (make-operator :name 'scoop
                  :preconditions '((device ?d) (bucket ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((bucket ?d full))))
  (let ((plan (gp-plan :goals '((charge-state interface-01 empty)))))
    (is (null (getf (plan-meta plan) :from-procedure)))
    (is (eq 'scoop (getf (first (plan-steps plan)) :operator)))
    (is (not (fact-p '(note interface-01 poured) (plan-final-state plan))))))

(test archive-plan-combines-procedures-that-each-cover-part
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
  (let* ((plan (gp-plan :goals '((charge-state interface-01 empty)
                                 (cable interface-01 connected))))
         (steps (plan-steps plan)))
    (is (null (getf (plan-meta plan) :from-procedure)))
    (is (equal '(fill-empty plug-cable)
               (getf (plan-meta plan) :from-procedures)))
    (is (eq 'pour (getf (first steps) :operator)))
    (is (eq t (getf (first steps) :stored-apply)))
    (is (eq 'attach (getf (second steps) :operator)))
    (is (eq t (getf (second steps) :stored-apply)))
    (is (fact-p '(charge-state interface-01 empty) (plan-final-state plan)))
    (is (fact-p '(cable interface-01 connected) (plan-final-state plan)))
    (is (not (fact-p '(charge-state interface-01 empty) (gp-facts)))))
  (let ((text (gp-explain :plan nil)))
    (is (search "FILL-EMPTY" text))
    (is (search "PLUG-CABLE" text)))
  (let ((fill-before (procedure-success-count (gp-find-procedure 'fill-empty)))
        (plug-before (procedure-success-count (gp-find-procedure 'plug-cable))))
    (let ((sim (gp-simulate)))
      (is-true (execution-success sim))
      (is (fact-p '(reservoir interface-01 full) (gp-facts)))
      (is (fact-p '(socket interface-01 free) (gp-facts)))
      (is (= fill-before (procedure-success-count (gp-find-procedure 'fill-empty)))))
    (let ((run (gp-run)))
      (is-true (execution-success run))
      (is (fact-p '(charge-state interface-01 empty) (gp-facts)))
      (is (fact-p '(cable interface-01 connected) (gp-facts)))
      (is (not (fact-p '(reservoir interface-01 full) (gp-facts))))
      (is (not (fact-p '(socket interface-01 free) (gp-facts))))
      (is (= (1+ fill-before)
             (procedure-success-count (gp-find-procedure 'fill-empty))))
      (is (= (1+ plug-before)
             (procedure-success-count (gp-find-procedure 'plug-cable)))))))

(test archive-plan-prefers-one-covering-procedure-over-parts
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
  (let* ((plan (gp-plan :goals '((charge-state interface-01 empty)
                                 (cable interface-01 connected))))
         (text (gp-explain :plan nil)))
    (is (eq 'prep-all (getf (plan-meta plan) :from-procedure)))
    (is (eq 'prep-both (getf (first (plan-steps plan)) :operator)))
    (is (search "PREP-ALL" text))
    (is (not (search "FILL-EMPTY" text)))))

(test archive-plan-uses-search-for-the-part-left-over
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
  (let* ((plan (gp-plan :goals '((charge-state interface-01 empty)
                                 (cable interface-01 connected))))
         (steps (plan-steps plan)))
    (is (null (getf (plan-meta plan) :from-procedure)))
    (is (eq 'pour (getf (first steps) :operator)))
    (is (eq t (getf (first steps) :stored-apply)))
    (is (eq 'attach (getf (second steps) :operator)))
    (is (null (getf (second steps) :stored-apply)))
    (is (fact-p '(cable interface-01 connected) (plan-final-state plan))))
  (is (search "FILL-EMPTY" (gp-explain :plan nil))))

(test archive-plan-rejects-a-search-that-undoes-a-reused-goal
  "MAKE-A achieves (A). The search for (B) finds only OP-B, which deletes
(A). Those pieces do not achieve the request: no plan may claim they do."
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device d1))
  (%install-recorded 'make-a '((a d1 yes))
                     (%recorded-step 'op-a '((device d1)) '((a d1 yes))))
  (gp-add-operator
   (make-operator :name 'op-b
                  :preconditions '((device ?d))
                  :add-list '((b ?d yes))
                  :delete-list '((a ?d yes))))
  (let ((plan (gp-plan :goals '((a d1 yes) (b d1 yes)))))
    (is-false (plan-success plan))
    (is (null (plan-reused-procedure-names plan)))))

(test archive-plan-combines-a-procedure-that-also-achieves-something-else
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
  (let* ((plan (gp-plan :goals '((charge-state interface-01 empty)
                                 (cable interface-01 connected))))
         (steps (plan-steps plan)))
    (is (null (getf (plan-meta plan) :from-procedure)))
    (is (eq 'attach (getf (first steps) :operator)))
    (is (eq t (getf (first steps) :stored-apply)))
    (is (eq 'pour-noted (getf (second steps) :operator)))
    (is (eq t (getf (second steps) :stored-apply)))
    (is (fact-p '(note interface-01 poured) (plan-final-state plan)))
    (is (fact-p '(cable interface-01 connected) (plan-final-state plan)))
    (is (not (fact-p '(note interface-01 poured) (gp-facts)))))
  (let ((text (gp-explain :plan nil)))
    (is (search "FILL-NOTED" text))
    (is (search "PLUG-CABLE" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (not (fact-p '(note interface-01 poured) (gp-facts))))
    (is (fact-p '(reservoir interface-01 full) (gp-facts))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(note interface-01 poured) (gp-facts)))
    (is (fact-p '(charge-state interface-01 empty) (gp-facts)))
    (is (fact-p '(cable interface-01 connected) (gp-facts)))
    (is (not (fact-p '(reservoir interface-01 full) (gp-facts))))
    (is (not (fact-p '(socket interface-01 free) (gp-facts))))))

(test archive-plan-prefers-a-part-without-extra-goals
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
  (let* ((plan (gp-plan :goals '((charge-state interface-01 empty)
                                 (cable interface-01 connected))))
         (text (gp-explain :plan nil)))
    (is (eq 'pour (getf (first (plan-steps plan)) :operator)))
    (is (not (fact-p '(note interface-01 poured) (plan-final-state plan))))
    (is (search "FILL-EMPTY" text))
    (is (not (search "FILL-NOTED" text)))))

(test archive-plan-keeps-useful-steps-when-extra-goals-are-blocked
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
  (let* ((plan (gp-plan :goals '((charge-state interface-01 empty))))
         (operators (mapcar (lambda (step) (getf step :operator))
                            (plan-steps plan))))
    (is (eq 'fill-noted (getf (plan-meta plan) :from-procedure)))
    (is (eq 'pour (getf (first (plan-steps plan)) :operator)))
    (is (not (member 'stamp operators)))
    (is (not (fact-p '(note interface-01 poured) (plan-final-state plan))))
    (is (fact-p '(charge-state interface-01 empty) (plan-final-state plan))))
  (let ((text (gp-explain :plan nil)))
    (is (search "Left aside" text))
    (is (search "STAMP" text))
    (is (search "FILL-NOTED" text)))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is (not (fact-p '(note interface-01 poured) (gp-facts))))
    (is (fact-p '(reservoir interface-01 full) (gp-facts))))
  (let ((run (gp-run)))
    (is-true (execution-success run))
    (is (fact-p '(charge-state interface-01 empty) (gp-facts)))
    (is (not (fact-p '(note interface-01 poured) (gp-facts))) )
    (is (not (fact-p '(reservoir interface-01 full) (gp-facts))))))

(test archive-plan-keeps-a-partial-step-when-its-extra-goal-is-blocked
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
  (gp-add-operator
   (make-operator :name 'attach
                  :preconditions '((device ?d) (socket ?d free))
                  :add-list '((cable ?d connected))
                  :delete-list '((socket ?d free))))
  (gp-add-fact '(socket interface-01 free))
  (gp-plan :goals '((cable interface-01 connected)) :archive nil)
  (gp-remember-procedure :name 'plug-cable)
  (gp-remove-operator 'attach)
  (let* ((plan (gp-plan :goals '((charge-state interface-01 empty)
                                 (cable interface-01 connected))))
         (steps (plan-steps plan))
         (operators (mapcar (lambda (step) (getf step :operator)) steps)))
    (is (eq 'attach (getf (first steps) :operator)))
    (is (eq 'pour (getf (second steps) :operator)))
    (is (not (member 'stamp operators)))
    (is (not (fact-p '(note interface-01 poured) (plan-final-state plan)))))
  (let ((text (gp-explain :plan nil)))
    (is (search "Left aside" text))
    (is (search "STAMP" text))
    (is (search "FILL-NOTED" text))
    (is (search "PLUG-CABLE" text))))

(test archive-plan-skips-a-procedure-whose-useful-step-is-also-blocked
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
  (gp-add-fact '(bucket interface-01 full))
  (gp-add-operator
   (make-operator :name 'scoop
                  :preconditions '((device ?d) (bucket ?d full))
                  :add-list '((charge-state ?d empty))
                  :delete-list '((bucket ?d full))))
  (let* ((plan (gp-plan :goals '((charge-state interface-01 empty))))
         (text (gp-explain :plan nil)))
    (is (null (getf (plan-meta plan) :from-procedure)))
    (is (eq 'scoop (getf (first (plan-steps plan)) :operator)))
    (is (not (fact-p '(note interface-01 poured) (plan-final-state plan))))
    (is (not (search "FILL-NOTED" text)))))

(test archive-plan-skips-steps-already-achieved
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'from-off)
  (gp-remove-fact '(power-state interface-01 off))
  (gp-add-fact '(power-state interface-01 on))
  (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
    (is (eq 'from-off (getf (plan-meta plan) :from-procedure)))
    (is (= 1 (plan-length plan)))
    (is (eq 'connect (getf (first (plan-steps plan)) :operator)))
    (is (fact-p '(connection interface-01 computer) (plan-final-state plan))))
  (let ((text (gp-explain :plan nil)))
    (is (search "already satisfied" text))
    (is (search "CONNECT" text))))

(test archive-plan-falls-back-when-steps-do-not-apply
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'from-off)
  (gp-remove-fact '(power-state interface-01 off))
  (gp-add-fact '(battery interface-01 charged))
  (gp-add-operator
   (make-operator :name 'boot
                  :preconditions '((device ?d) (battery ?d charged))
                  :add-list '((power-state ?d on))))
  (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
    (is-true (plan-success plan))
    (is (null (getf (plan-meta plan) :from-procedure)))
    (is (member 'boot (plan-operators-used plan)))))

(test archive-plan-can-skip-archive
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'once)
  (let ((plan (gp-plan :goals '((connection interface-01 computer))
                       :archive nil)))
    (is-true (plan-success plan))
    (is (null (getf (plan-meta plan) :from-procedure)))
    (is (>= (plan-length plan) 2))))

(test autonomy-reuses-archive-before-search
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'once)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (gp-add-operator
   (make-operator :name 'connect
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((connection ?d computer))))
  (gp-add-goal '(connection interface-01 computer))
  (let ((summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :simulate
                                                :prefer-archive t))))
    (is (eq :done (getf summary :status)))
    (is (eq 'once (getf (getf summary :plan) :from-procedure)))
    (is (eq 'once (getf (plan-meta (gp-last-plan)) :from-procedure)))
    (is (fact-p '(power-state interface-01 off) (gp-facts)))
    (is (= 1 (procedure-success-count (gp-find-procedure 'once))))
    (is (= 0 (procedure-failure-count (gp-find-procedure 'once))))))

(test archive-live-run-raises-score-simulation-does-not
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'once)
  (gp-plan :goals '((connection interface-01 computer)))
  (gp-simulate)
  (is (= 1 (procedure-success-count (gp-find-procedure 'once))))
  (is (= 0 (procedure-failure-count (gp-find-procedure 'once))))
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (gp-add-operator
   (make-operator :name 'connect
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((connection ?d computer))))
  (let ((run (gp-run :plan (gp-plan :goals '((connection interface-01 computer))))))
    (is-true (execution-success run))
    (is (= 2 (procedure-success-count (gp-find-procedure 'once))))
    (is (= 0 (procedure-failure-count (gp-find-procedure 'once)))))
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (gp-add-operator
   (make-operator :name 'connect
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((connection ?d computer))))
  (gp-plan :goals '((connection interface-01 computer)) :archive nil)
  (gp-run)
  (is (= 2 (procedure-success-count (gp-find-procedure 'once)))))

(test archive-live-failure-lowers-score
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'once)
  (gp-remove-fact '(device interface-01))
  (signals error (gp-use-procedure :name 'once))
  (gp-use-procedure :name 'once :unchecked t)
  (let ((run (with-failure-strategy (:abort)
               (gp-run))))
    (is (not (execution-success run))))
  (is (= 1 (procedure-success-count (gp-find-procedure 'once))))
  (is (= 1 (procedure-failure-count (gp-find-procedure 'once))))
  (is (< (procedure-score (gp-find-procedure 'once))
         (procedure-score
          (make-procedure :name 'baseline :success-count 1 :failure-count 0)))))

(test autonomy-execute-scores-reused-procedure
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'once)
  (gp-add-goal '(connection interface-01 computer))
  (let ((summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :execute
                                                :prefer-archive t
                                                :remember-procedure t))))
    (is (eq :done (getf summary :status)))
    (is (eq 'once (getf (getf summary :plan) :from-procedure)))
    (let ((proc (gp-find-procedure 'once)))
      (is (= 2 (procedure-success-count proc)))
      (is (= 0 (procedure-failure-count proc))))
    (is (= 1 (count-if (lambda (p)
                         (eq 'once (procedure-name p)))
                       (gp-procedures))))))

;;; --- The archive file ---

(test archive-autosave-keeps-procedures-the-session-no-longer-holds
  "Neither clearing memory nor starting with autoload off lets the next
autosave drop what the file already holds."
  (dolist (forget (list #'gp-clear-memory
                        (lambda ()
                          (setf *procedural-memory* nil
                                automa-gp::*procedure-archive-loaded* nil))))
    (with-archive-file (path)
      (%archive-studio)
      (gp-remember-procedure :name 'first)
      (gp-remember-procedure :name 'second)
      (funcall forget)
      (%archive-studio)
      (gp-remember-procedure :name 'third)
      (is (equal '("THIRD") (%procedure-names)))
      (gp-score-procedure 'third)
      (gp-clear-memory)
      (gp-archive-load path)
      (is (equal '("FIRST" "SECOND" "THIRD") (%procedure-names)))
      (is (= 2 (procedure-success-count (gp-find-procedure 'third)))))))

(test remembering-into-another-store-leaves-the-archive-file-alone
  (with-archive-file (path)
    (let ((other (make-procedural-memory)))
      (remember-procedure! (make-procedure :name 'elsewhere :goals '((a b c)))
                           other)
      (score-procedure! 'elsewhere :success nil :memory other)
      (is (= 1 (procedure-failure-count (find-procedure 'elsewhere other))))
      (is (null (probe-file path)))
      (is (null (gp-find-procedure 'elsewhere))))))

(test archive-autosave-failure-is-typed-and-keeps-the-change
  (with-archive-file (blocker)
    ;; A regular file stands where the archive's directory should be.
    (%write-archive-text blocker "not a directory")
    (let ((*procedure-archive-path*
            (format nil "~A/archive.agp" (namestring blocker))))
      (%archive-studio)
      (handler-case (progn (gp-remember-procedure :name 'kept)
                           (fail "the autosave did not signal"))
        (procedure-archive-error (c)
          (is (eq :write (procedure-archive-error-action c)))
          (is (equal *procedure-archive-path* (procedure-archive-error-path c)))
          (is (typep (procedure-archive-error-cause c) 'file-error))))
      (is (procedure-p (gp-find-procedure 'kept)))
      (is (procedure-p (handler-bind ((procedure-archive-error #'%skip-archive))
                         (gp-score-procedure 'kept))))
      (is (= 2 (procedure-success-count (gp-find-procedure 'kept)))))))

(defvar *archive-code-ran* nil
  "Set by code smuggled into an archive file, if the reader evaluates it.")

(test unreadable-archive-file-is-reported-and-never-overwritten
  "A damaged archive is reported on every access until someone decides, is
never half loaded, runs no code, and is not replaced by a later autosave."
  (dolist (text '("(:kind :automa-gp-procedure-archive :procedures ((:procedure :name"
                  "(:kind :not-an-archive)"
                  "(:kind :automa-gp-procedure-archive
                    :procedures ((:procedure :name good :goals ((a))) 17))"
                  "(:kind :automa-gp-procedure-archive
                    :procedures #.(setf automa-gp/tests::*archive-code-ran* t))"))
    (with-archive-file (path :autoload t)
      (%write-archive-text path text)
      (setf *archive-code-ran* nil)
      (handler-case (progn (gp-procedures)
                           (fail "the autoload did not signal"))
        (procedure-archive-error (c)
          (is (eq :read (procedure-archive-error-action c)))
          (is (equal path (procedure-archive-error-path c)))))
      (signals procedure-archive-error (gp-find-procedure 'good))
      (is (null (handler-bind ((procedure-archive-error #'%skip-archive))
                  (gp-procedures))))
      (is (null (gp-procedures)))
      (is (null *archive-code-ran*))
      (%archive-studio)
      (signals procedure-archive-error (gp-remember-procedure :name 'new))
      (is (procedure-p (gp-find-procedure 'new)))
      (is (string= text (uiop:read-file-string path))))))

(test archive-error-handler-sees-session-memory
  "The file is read into a scratch store. A handler must find the session
store in its place, without the procedures read before the damage."
  (with-archive-file (path :autoload t)
    (%write-archive-text path "(:kind :automa-gp-procedure-archive
                                :procedures ((:procedure :name good :goals ((a))) 17))")
    (let ((seen :not-called))
      (handler-bind ((procedure-archive-error
                       (lambda (c)
                         (setf seen (list (procedural-memory-procedures
                                           *procedural-memory*)
                                          *read-eval*))
                         (%skip-archive c))))
        (is (null (gp-procedures))))
      (is (equal '(nil t) seen)))))

(test repaired-archive-file-is-read-on-retry
  (with-archive-file (path :autoload t)
    (%write-archive-text path "(")
    (let ((attempts 0))
      (is (equal '("MENDED")
                 (handler-bind
                     ((procedure-archive-error
                        (lambda (c)
                          (declare (ignore c))
                          (incf attempts)
                          (save-procedure-archive
                           :path path
                           :memory (make-procedural-memory
                                    :procedures (list (make-procedure
                                                       :name 'mended
                                                       :goals '((a))))))
                          (invoke-restart :retry))))
                   (%procedure-names))))
      (is (= 1 attempts)))))

;;; --- Names, counts and ranking ---

(test archive-is-not-consulted-when-nothing-is-requested
  "No fact-like goal means no request: no procedure is replayed."
  (dolist (goals '(nil (tidy-up)))
    (gp-clear-memory)
    (%archive-studio)
    (gp-remember-procedure :name 'once)
    (let ((plan (gp-plan :goals goals)))
      (is (null (plan-steps plan)) "goals ~S: the plan has steps" goals)
      (is (null (plan-reused-procedure-names plan))
          "goals ~S: a procedure was replayed" goals))
    (is (null (plan-from-ranked-procedures (gp-context) nil (gp-operators))))
    (signals error (gp-use-procedure :goals goals))))

(test default-procedure-name-ignores-package-and-print-case
  (gp-clear-memory)
  (let* ((plan (%archive-studio))
         (names (loop for package in '(:cl-user :automa-gp :automa-gp/tests :keyword)
                      append (loop for print-case in '(:upcase :downcase :capitalize)
                                   collect (let ((*package* (find-package package))
                                                 (*print-case* print-case))
                                             (procedure-name
                                              (procedure-from-plan plan)))))))
    (is (every (lambda (name) (eq name (first names))) names))
    (is (string= "PROC-DEFAULT" (symbol-name (first names))))
    (is (eq (find-package :automa-gp) (symbol-package (first names))))))

(test remembering-other-goals-under-a-name-starts-a-fresh-count
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'shared)
  (gp-score-procedure 'shared :success nil)
  (is (= 2 (procedure-success-count (gp-remember-procedure :name 'shared))))
  (is (= 1 (procedure-failure-count (gp-find-procedure 'shared))))
  (gp-plan :goals '((power-state interface-01 on)) :archive nil)
  (let ((replaced (gp-remember-procedure :name 'shared)))
    (is (equal '((power-state interface-01 on)) (procedure-goals replaced)))
    (is (= 1 (procedure-success-count replaced)))
    (is (= 0 (procedure-failure-count replaced)))
    (is (= 1 (length (gp-procedures))))))

(test unnamed-plans-for-different-goals-do-not-replace-each-other
  (gp-clear-memory)
  (%archive-studio)
  (let ((connect (gp-remember-procedure)))
    (gp-plan :goals '((power-state interface-01 on)) :archive nil)
    (let ((power (gp-remember-procedure)))
      (is (not (eq (procedure-name connect) (procedure-name power))))
      (is (eq connect (gp-find-procedure (procedure-name connect))))
      (is (eq (procedure-name power) (procedure-name (gp-remember-procedure))))
      (is (= 2 (procedure-success-count
                (gp-find-procedure (procedure-name power)))))
      (is (= 2 (length (gp-procedures)))))))

(test ranking-does-not-depend-on-the-order-procedures-arrive
  (let ((procedures (loop for name in '(zeta alpha mid)
                          collect (make-procedure :name name :goals '((a))))))
    (dolist (order (list procedures (reverse procedures)))
      (is (equal '(alpha mid zeta)
                 (mapcar #'procedure-name (rank-procedures order)))))))

(test outcome-of-a-combined-plan-scores-each-procedure-in-plan-order
  (with-archive-file (path)
    (install-procedure! (make-procedure :name 'zulu :goals '((a))))
    (install-procedure! (make-procedure :name 'alpha :goals '((b))))
    (multiple-value-bind (first all)
        (record-procedure-outcome!
         (make-instance 'plan :success t
                              :meta (list :from-procedures '(zulu gone alpha)))
         :success nil)
      (is (eq 'zulu (procedure-name first)))
      (is (equal '(zulu alpha) (mapcar #'procedure-name all))))
    (is (null (record-procedure-outcome! (make-instance 'plan :success t))))
    (gp-clear-memory)
    (gp-archive-load path)
    (dolist (name '(zulu alpha))
      (is (= 1 (procedure-failure-count (gp-find-procedure name)))))))

(test archive-misuse-signals-typed-conditions
  (gp-clear-memory)
  (install-procedure! (make-procedure :name 'known :goals '((a))))
  (handler-case (progn (score-procedure! 'missing)
                       (fail "scoring an unknown procedure did not signal"))
    (unknown-procedure (c)
      (is (eq 'missing (unknown-procedure-name c)))))
  (is (eq 'known
          (procedure-name
           (handler-bind ((unknown-procedure
                            (lambda (c)
                              (declare (ignore c))
                              (invoke-restart :use-value 'known))))
             (score-procedure! 'missing)))))
  (is (= 2 (procedure-success-count (gp-find-procedure 'known))))
  (%archive-studio)
  (let ((failed (gp-plan :goals '((ready interface-01)) :archive nil)))
    (signals unsuccessful-plan (procedure-from-plan failed))
    (signals unsuccessful-plan (remember-procedure-from-plan! failed :name 'nope)))
  (signals type-error (procedure-from-plan :not-a-plan))
  (is (null (gp-find-procedure 'nope))))

(test unchecked-plan-expects-the-state-its-procedure-recorded
  (gp-clear-memory)
  (%archive-studio)
  (gp-remember-procedure :name 'once)
  (let ((plan (gp-use-procedure :name 'once :unchecked t)))
    (is (fact-p '(connection interface-01 computer) (plan-final-state plan)))
    (is (fact-p '(power-state interface-01 on) (plan-final-state plan)))
    (is (not (fact-p '(power-state interface-01 off) (plan-final-state plan)))))
  (let ((sim (gp-simulate)))
    (is-true (execution-success sim))
    (is-true (getf (execution-divergences sim) :equal)))
  (is (null (plan-final-state
             (procedure->plan
              (make-procedure :name 'by-hand
                              :goals '((a))
                              :initial-state '((b))
                              :steps (list (list :operator 'op :goal '(a)))))))))
