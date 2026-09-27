;;;; memory/procedural.lisp — procedural memory (Phase 7)
;;;;
;;;; Reusable procedures derived from successful plans. Does not embed
;;;; persistence or planner logic — stores symbolic step sequences.

(in-package #:automa-gp)

(defclass gp-procedure ()
  ((name
    :initarg :name
    :accessor procedure-name
    :initform nil)
   (goals
    :initarg :goals
    :accessor procedure-goals
    :initform nil
    :documentation "Goals this procedure was built to achieve.")
   (steps
    :initarg :steps
    :accessor procedure-steps
    :initform nil
    :documentation "Ordered plan steps (operator + bindings plists).")
   (operators-used
    :initarg :operators-used
    :accessor procedure-operators-used
    :initform nil)
   (initial-state
    :initarg :initial-state
    :accessor procedure-initial-state
    :initform nil
    :documentation "Facts that held when the procedure succeeded.")
   (success-count
    :initarg :success-count
    :accessor procedure-success-count
    :initform 1)
   (failure-count
    :initarg :failure-count
    :accessor procedure-failure-count
    :initform 0
    :documentation "Replays that did not achieve the stored goals.")
   (last-success-at
    :initarg :last-success-at
    :accessor procedure-last-success-at
    :initform nil
    :documentation "Universal time of the last recorded success.")
   (last-failure-at
    :initarg :last-failure-at
    :accessor procedure-last-failure-at
    :initform nil)
   (meta
    :initarg :meta
    :accessor procedure-meta
    :initform nil))
  (:documentation "Reusable symbolic procedure (from a successful plan)."))

(defun procedure-p (object)
  (typep object 'gp-procedure))

(defclass procedural-memory ()
  ((procedures
    :initarg :procedures
    :accessor procedural-memory-procedures
    :initform nil
    :documentation "Alist or list of GP-PROCEDURE objects.")
   (meta
    :initarg :meta
    :accessor procedural-memory-meta
    :initform nil))
  (:documentation "Store of reusable procedures."))

(defun procedural-memory-p (object)
  (typep object 'procedural-memory))

(defvar *procedural-memory* nil
  "Session procedural memory. Also the in-memory procedure archive.")

(defvar *procedure-archive-path*
  (merge-pathnames ".automa-gp/procedure-archive.agp"
                   (user-homedir-pathname))
  "Durable archive of successful procedures (readable s-expression, .agp).")

(defvar *procedure-archive-autosave* t
  "When true, REMEMBER-PROCEDURE! and SCORE-PROCEDURE! write the archive file.")

(defvar *procedure-archive-autoload* t
  "When true, the first ENSURE-PROCEDURAL-MEMORY loads the archive file if it exists.")

(defvar *procedure-archive-loaded* nil
  "True after an autoload attempt or an explicit load/clear in this image.")

(defvar *loading-procedure-archive* nil
  "Bound during LOAD-PROCEDURE-ARCHIVE to avoid recursive autoload.")

(defun make-procedural-memory (&key procedures meta)
  (make-instance 'procedural-memory
                 :procedures (copy-list procedures)
                 :meta (copy-tree meta)))

(defun ensure-procedural-memory ()
  (unless (procedural-memory-p *procedural-memory*)
    (setf *procedural-memory* (make-procedural-memory)))
  (maybe-autoload-procedure-archive)
  *procedural-memory*)

(defun clear-procedural-memory ()
  "Drop in-memory procedures. The archive file is left on disk.
Does not autoload again until LOAD-PROCEDURE-ARCHIVE."
  (setf *procedural-memory* nil)
  (setf *procedure-archive-loaded* t)
  t)

(defun make-procedure (&key name goals steps operators-used initial-state
                         (success-count 1) (failure-count 0)
                         last-success-at last-failure-at meta)
  (make-instance 'gp-procedure
                 :name name
                 :goals (copy-list goals)
                 :steps (copy-tree steps)
                 :operators-used (copy-list operators-used)
                 :initial-state (copy-list initial-state)
                 :success-count (or success-count 1)
                 :failure-count (or failure-count 0)
                 :last-success-at last-success-at
                 :last-failure-at last-failure-at
                 :meta (copy-tree meta)))

(defun procedure-score (procedure)
  "Ranking score. Higher is better. Not a probability.
Laplace success rate (successes+1)/(successes+failures+2), times log(2+successes),
so repeated successes outrank a single success and failures pull the rate down."
  (let* ((s (max 0 (procedure-success-count procedure)))
         (f (max 0 (procedure-failure-count procedure)))
         (rate (/ (float (+ s 1)) (+ s f 2))))
    (* rate (log (+ 2 s)))))

(defun procedure-from-plan (plan &key name)
  "Turn a successful PLAN into a reusable GP-PROCEDURE.
Signals an error if PLAN is missing or unsuccessful."
  (unless (plan-p plan)
    (error "procedure-from-plan requires a PLAN"))
  (unless (plan-success plan)
    (error "procedure-from-plan requires a successful plan"))
  (make-procedure :name (or name
                            (intern (format nil "PROC-~A"
                                           (or (getf (plan-meta plan) :context)
                                               'unnamed))))
                  :goals (plan-goals plan)
                  :steps (plan-steps plan)
                  :operators-used (plan-operators-used plan)
                  :initial-state (plan-initial-state plan)
                  :meta (list :from-plan t
                              :context (getf (plan-meta plan) :context))))

(defun install-procedure! (procedure &optional (memory (ensure-procedural-memory)))
  "Store PROCEDURE as-is, replacing the same name. No score bump, no autosave."
  (let ((name (procedure-name procedure)))
    (setf (procedural-memory-procedures memory)
          (cons procedure
                (remove name (procedural-memory-procedures memory)
                        :key #'procedure-name :test #'equal)))
    procedure))

(defun remember-procedure! (procedure &optional (memory (ensure-procedural-memory)))
  "Store PROCEDURE. A previous procedure with the same name keeps its failure
count; successes add. Writes the archive file when autosave is on."
  (let* ((name (procedure-name procedure))
         (old (find name (procedural-memory-procedures memory)
                    :key #'procedure-name :test #'equal)))
    (when (and old (not (eq old procedure)))
      (setf (procedure-success-count procedure)
            (+ (procedure-success-count old)
               (max 1 (procedure-success-count procedure))))
      (setf (procedure-failure-count procedure)
            (procedure-failure-count old))
      (setf (procedure-last-failure-at procedure)
            (procedure-last-failure-at old)))
    (setf (procedure-last-success-at procedure) (get-universal-time))
    (install-procedure! procedure memory)
    (maybe-autosave-procedure-archive)
    procedure))

(defun score-procedure! (name &key (success t)
                               (memory (ensure-procedural-memory)))
  "Record a later replay of the procedure named NAME.
:SUCCESS T increments successes; NIL increments failures. Autosaves."
  (let ((procedure (find name (procedural-memory-procedures memory)
                         :key #'procedure-name :test #'equal)))
    (unless procedure
      (error "No procedure named ~S in the archive." name))
    (if success
        (progn
          (incf (procedure-success-count procedure))
          (setf (procedure-last-success-at procedure) (get-universal-time)))
        (progn
          (incf (procedure-failure-count procedure))
          (setf (procedure-last-failure-at procedure) (get-universal-time))))
    (maybe-autosave-procedure-archive)
    procedure))

(defun plan-reused-procedure-names (plan)
  "Names of archived procedures PLAN replayed.
One :FROM-PROCEDURE, or the :FROM-PROCEDURES of a plan built from several."
  (when (plan-p plan)
    (let ((one (getf (plan-meta plan) :from-procedure)))
      (if one
          (list one)
          (copy-list (getf (plan-meta plan) :from-procedures))))))

(defun record-procedure-outcome! (plan &key (success t))
  "If PLAN was reused from the archive, record one success or failure
for each procedure it replayed. No-op when none of those procedures
remain. Simulation must not call this — only a finished live execution.
Returns one scored procedure, or NIL when nothing was scored."
  (let ((scored nil))
    (dolist (name (plan-reused-procedure-names plan))
      (when (and name (find-procedure name))
        (push (score-procedure! name :success (and success t)) scored)))
    (first scored)))

(defun remember-procedure-from-plan! (plan &key name
                                          (memory (ensure-procedural-memory)))
  "Convert a successful PLAN into a procedure and store it."
  (remember-procedure! (procedure-from-plan plan :name name) memory))

(defun find-procedure (name &optional (memory (ensure-procedural-memory)))
  (find name (procedural-memory-procedures memory)
        :key #'procedure-name :test #'equal))

(defun procedures-for-goals (goals &optional (memory (ensure-procedural-memory)))
  "Procedures whose goal set equals GOALS (order-insensitive EQUAL)."
  (let ((g (copy-list goals)))
    (remove-if-not
     (lambda (p)
       (and (null (set-difference g (procedure-goals p) :test #'equal))
            (null (set-difference (procedure-goals p) g :test #'equal))))
     (procedural-memory-procedures memory))))

(defun rank-procedures (procedures)
  "Fresh list of PROCEDURES, highest PROCEDURE-SCORE first."
  (sort (copy-list procedures)
        (lambda (a b)
          (let ((sa (procedure-score a))
                (sb (procedure-score b)))
            (or (> sa sb)
                (and (= sa sb)
                     (> (procedure-success-count a)
                        (procedure-success-count b))))))))

(defun archive-best (goals &optional (memory (ensure-procedural-memory)))
  "Highest-scoring archived procedure whose goals equal GOALS, or NIL."
  (first (rank-procedures (procedures-for-goals goals memory))))

(defun maybe-autoload-procedure-archive ()
  "Load the archive file once per image, unless loading or explicitly cleared.
Prefers *PROCEDURE-ARCHIVE-PATH* (.agp); falls back to a sibling .sexp if present."
  (when (and *procedure-archive-autoload*
             (not *procedure-archive-loaded*)
             (not *loading-procedure-archive*)
             (or (probe-file *procedure-archive-path*)
                 (probe-file (make-pathname
                              :defaults *procedure-archive-path*
                              :type "sexp"))))
    (setf *procedure-archive-loaded* t)
    (load-procedure-archive *procedure-archive-path*)))

(defun maybe-autosave-procedure-archive ()
  "Write the archive file when autosave is enabled."
  (when *procedure-archive-autosave*
    (save-procedure-archive :path *procedure-archive-path*)
    (setf *procedure-archive-loaded* t)))

(defun procedure->plan (procedure &key (meta nil))
  "Rebuild a PLAN object from a stored PROCEDURE (does not re-run MEA).
Does not check that the steps still apply to the live state — use
PLAN-FROM-PROCEDURE for that."
  (make-instance 'plan
                 :goals (copy-list (procedure-goals procedure))
                 :steps (copy-tree (procedure-steps procedure))
                 :success t
                 :initial-state (copy-list (procedure-initial-state procedure))
                 :final-state nil
                 :remaining nil
                 :operators-used (copy-list (procedure-operators-used procedure))
                 :meta (list* :from-procedure (procedure-name procedure)
                              meta)))

(defun %facts-same-p (a b)
  "True when A and B contain the same facts, ignoring order."
  (and (null (set-difference a b :test #'equal))
       (null (set-difference b a :test #'equal))))

(defun %replay-step-copy (step &key effects-only stored-apply)
  "Copy STEP for a new plan. Replay flags are set only for this copy."
  (let ((copy (copy-list step)))
    (remf copy :effects-only)
    (remf copy :stored-apply)
    (when effects-only
      (setf (getf copy :effects-only) t))
    (when stored-apply
      (setf (getf copy :stored-apply) t))
    copy))

(defvar *procedure-repair-depth* 0
  "How many precondition repairs are already in progress.")

(defparameter *procedure-repair-archive-depth* 61
  "How many nested precondition repairs may reuse an archived procedure.
A deeper repair uses Means-Ends Analysis only.")

(defvar *procedures-in-replay* nil
  "Procedures currently being replayed, innermost first. Stops a repair from
reusing the procedure that is already running.")

(defun %repair-by-search (missing state operators)
  "Means-Ends Analysis for MISSING facts only.
Returns (VALUES NEW-STATE STEPS NIL) or NIL."
  (let ((*trace-enabled* nil))
    (multiple-value-bind (ok final steps left)
        (means-ends-analyze state missing operators)
      (when (and ok (null left))
        (values (or final state) steps nil)))))

(defun %goals-covered-p (goals procedure)
  "True when every fact in GOALS is one of PROCEDURE's goals."
  (null (set-difference goals (procedure-goals procedure) :test #'equal)))

(defun %goal-surplus (procedure goals)
  "How many of PROCEDURE's goals are not in GOALS."
  (length (set-difference (procedure-goals procedure) goals :test #'equal)))

(defun %procedure-name< (a b)
  (string< (princ-to-string (procedure-name a))
           (princ-to-string (procedure-name b))))

(defun %score-then-name< (a b)
  "True when A should precede B: higher score, then more successes, then name."
  (let ((score-a (procedure-score a))
        (score-b (procedure-score b)))
    (or (> score-a score-b)
        (and (= score-a score-b)
             (or (> (procedure-success-count a)
                    (procedure-success-count b))
                 (and (= (procedure-success-count a)
                         (procedure-success-count b))
                      (%procedure-name< a b)))))))

(defun %procedures-covering-goals (goals &optional (memory (ensure-procedural-memory)))
  "Procedures whose goals include GOALS.
Fewest extra goals first. Score, then success count, then name breaks a tie."
  (sort (remove-if-not (lambda (procedure)
                         (%goals-covered-p goals procedure))
                       (copy-list (procedural-memory-procedures memory)))
        (lambda (a b)
          (let ((extra-a (%goal-surplus a goals))
                (extra-b (%goal-surplus b goals)))
            (or (< extra-a extra-b)
                (and (= extra-a extra-b)
                     (%score-then-name< a b)))))))

(defun %goal-overlap (procedure goals)
  "How many facts in GOALS are also goals of PROCEDURE."
  (count-if (lambda (goal)
              (member goal (procedure-goals procedure) :test #'equal))
            goals))

(defun %procedures-partial-goals (goals &optional (memory (ensure-procedural-memory)))
  "Procedures whose goals are a non-empty part of GOALS, not the whole set.
Largest part first. Score, then success count, then name breaks a tie."
  (sort (remove-if-not
         (lambda (procedure)
           (let ((procedure-goals (procedure-goals procedure)))
             (and procedure-goals
                  (null (set-difference procedure-goals goals :test #'equal))
                  (not (%goals-covered-p goals procedure)))))
         (copy-list (procedural-memory-procedures memory)))
        (lambda (a b)
          (let ((count-a (length (procedure-goals a)))
                (count-b (length (procedure-goals b))))
            (or (> count-a count-b)
                (and (= count-a count-b)
                     (%score-then-name< a b)))))))

(defun %procedures-overlapping-goals (goals &optional (memory (ensure-procedural-memory)))
  "Procedures that achieve some of GOALS and also some other goal.
They do not cover every fact in GOALS. Most shared facts first, then fewest
extra goals. Score, then success count, then name breaks a tie."
  (sort (remove-if-not
         (lambda (procedure)
           (let ((procedure-goals (procedure-goals procedure)))
             (and procedure-goals
                  (not (%goals-covered-p goals procedure))
                  (plusp (%goal-overlap procedure goals))
                  (some (lambda (goal)
                          (not (member goal goals :test #'equal)))
                        procedure-goals))))
         (copy-list (procedural-memory-procedures memory)))
        (lambda (a b)
          (let ((overlap-a (%goal-overlap a goals))
                (overlap-b (%goal-overlap b goals)))
            (or (> overlap-a overlap-b)
                (and (= overlap-a overlap-b)
                     (let ((extra-a (%goal-surplus a goals))
                           (extra-b (%goal-surplus b goals)))
                       (or (< extra-a extra-b)
                           (and (= extra-a extra-b)
                                (%score-then-name< a b))))))))))

(defun %facts-still-missing (facts state)
  (remove-if (lambda (fact)
               (and (consp fact) (goal-holds-p fact state)))
             facts))

(defun %repair-gap-event (missing operator from-procedure)
  (list :kind :repair-gap
        :missing (copy-tree missing)
        :operator operator
        :from-procedure from-procedure))

(defun %combine-partial-repair (procedure plan rest state operators
                                for-operator used)
  "PROCEDURE restored part of the gap. Repair REST from STATE and join the steps.
Returns the same values as %REPAIR-ASSEMBLE, or NIL."
  (multiple-value-bind (rest-state rest-steps rest-name rest-events)
      (%repair-assemble rest state operators for-operator (cons procedure used))
    (when rest-state
      (values rest-state
              (append (plan-steps plan) rest-steps)
              nil
              (append (list (%repair-gap-event (procedure-goals procedure)
                                               for-operator
                                               (procedure-name procedure)))
                      (getf (plan-meta plan) :replay-events)
                      (if rest-name
                          (cons (%repair-gap-event rest for-operator rest-name)
                                rest-events)
                          (or rest-events
                              (mapcar (lambda (step)
                                        (list :kind :repair :step step))
                                      rest-steps))))))))

(defun %step-serves-goals-p (step goals)
  "True when STEP's goal or a recorded add is one of GOALS."
  (or (and (consp (getf step :goal))
           (member (getf step :goal) goals :test #'equal))
      (some (lambda (fact)
              (and (consp fact) (member fact goals :test #'equal)))
            (getf step :adds))))

(defun %procedure-focused (procedure goals)
  "Copy of PROCEDURE containing only steps that serve GOALS.
Returns (VALUES NARROWED OMITTED-STEPS). NARROWED is NIL when no step serves
GOALS. The copy keeps PROCEDURE's name and score."
  (let ((kept nil)
        (omitted nil))
    (dolist (step (procedure-steps procedure))
      (if (%step-serves-goals-p step goals)
          (push step kept)
          (push step omitted)))
    (values (when kept
              (make-procedure
               :name (procedure-name procedure)
               :goals (remove-if-not (lambda (goal)
                                       (member goal goals :test #'equal))
                                     (procedure-goals procedure))
               :steps (nreverse kept)
               :operators-used (procedure-operators-used procedure)
               :success-count (procedure-success-count procedure)
               :failure-count (procedure-failure-count procedure)))
            (nreverse omitted))))

(defun %plan-without-blocked-extras (procedure missing state operators
                                      &key context-name)
  "Replay PROCEDURE without steps that only serve goals outside MISSING.
Used when the full replay fails because those extra goals cannot be restored.
The omitted steps are left aside. Returns a PLAN, or NIL."
  (unless (plusp (%goal-surplus procedure missing))
    (return-from %plan-without-blocked-extras nil))
  (multiple-value-bind (narrow omitted)
      (%procedure-focused procedure missing)
    (unless (and narrow (procedure-goals narrow) omitted)
      (return-from %plan-without-blocked-extras nil))
    (plan-from-procedure narrow state operators
                         :context-name context-name
                         :aside omitted)))

(defun %repair-assemble (missing state operators for-operator used)
  "Restore MISSING by replaying archived procedures, then a search for
whatever those procedures did not achieve.
A procedure that covers every remaining fact is tried first, then one whose
goals stay inside those facts, then one that also achieves something else.
USED procedures are not replayed again.
Returns (VALUES NEW-STATE STEPS FROM-PROCEDURE REPLAY-EVENTS) or NIL.
FROM-PROCEDURE is set only when a single procedure achieved MISSING."
  (dolist (procedure (append (%procedures-covering-goals missing)
                             (%procedures-partial-goals missing)
                             (%procedures-overlapping-goals missing)))
    (unless (or (member procedure used :test #'eq)
                (member procedure *procedures-in-replay* :test #'eq))
      (let ((plan (or (plan-from-procedure procedure state operators)
                     (%plan-without-blocked-extras procedure missing
                                                   state operators))))
        (when plan
          (let* ((state2 (or (plan-final-state plan) state))
                 (rest (%facts-still-missing missing state2)))
            (when (< (length rest) (length missing))
              (return-from %repair-assemble
                (if (null rest)
                    (values state2
                            (plan-steps plan)
                            (procedure-name procedure)
                            (getf (plan-meta plan) :replay-events))
                    (%combine-partial-repair procedure plan rest state2
                                             operators for-operator used)))))))))
  (when used
    (multiple-value-bind (mea-state mea-steps)
        (%repair-by-search missing state operators)
      (when mea-state
        (values mea-state mea-steps nil
                (mapcar (lambda (step) (list :kind :repair :step step))
                        mea-steps))))))

(defun %repair-from-archive (missing state operators &optional for-operator)
  "Replay archived procedures that together achieve MISSING.
One procedure whose goals include every missing fact is preferred.
Otherwise procedures whose goals stay inside MISSING are combined, then
procedures that also achieve something else. A search restores any fact
they leave out. Skips procedures already on the
replay stack. Returns (VALUES NEW-STATE STEPS PROCEDURE-NAME REPLAY-EVENTS)
or NIL."
  (%repair-assemble missing state operators for-operator nil))

(defun %repair-missing (missing state operators &optional for-operator)
  "Restore MISSING facts. Up to *PROCEDURE-REPAIR-ARCHIVE-DEPTH* repairs
may consult the archive. A covering procedure is preferred, then procedures
whose goals stay inside the missing facts, then procedures that also
achieve something else. Anything still missing is a
Means-Ends search. A deeper repair uses only that search.
Returns (VALUES NEW-STATE STEPS FROM-PROCEDURE REPLAY-EVENTS) or NIL."
  (let ((*procedure-repair-depth* (1+ *procedure-repair-depth*)))
    (when (<= *procedure-repair-depth* *procedure-repair-archive-depth*)
      (multiple-value-bind (new-state steps name replay-events)
          (%repair-from-archive missing state operators for-operator)
        (when new-state
          (return-from %repair-missing
            (values new-state steps name replay-events)))))
    (multiple-value-bind (new-state steps name)
        (%repair-by-search missing state operators)
      (when new-state
        (values new-state steps name nil)))))

(defun %splice-replay-events (replay-events events)
  "Turn a reused procedure's replay events into repair events.
A nested missing-precondition gap is kept so its procedure name stays visible."
  (dolist (event replay-events)
    (case (getf event :kind)
      (:repair-gap
       (push event events))
      ((:repair :stored :apply :project)
       (push (list :kind :repair :step (getf event :step)) events))
      (:aside
       (push event events))))
  events)

(defun %splice-repair (missing state operators applied events for-operator)
  "Insert steps that achieve only MISSING, then return the updated lists.
Returns NIL when that fails."
  (multiple-value-bind (new-state repair-steps from-procedure replay-events)
      (%repair-missing missing state operators for-operator)
    (unless new-state
      (return-from %splice-repair nil))
    (push (list :kind :repair-gap
                :missing (copy-tree missing)
                :operator for-operator
                :from-procedure from-procedure)
          events)
    (dolist (repair-step repair-steps)
      (push repair-step applied))
    (if replay-events
        (setf events (%splice-replay-events replay-events events))
        (dolist (repair-step repair-steps)
          (push (list :kind :repair :step repair-step) events)))
    (values new-state applied events)))

(defun replay-procedure (procedure facts operators)
  "Symbolically replay PROCEDURE's stored steps on FACTS.
This is not a search: each step is the one already recorded.
A step whose :GOAL already holds, and whose effects are already in the
state, is skipped. If that goal holds but the effects would still change
the state, they are applied: as a normal step when the operator is
registered and its preconditions hold, otherwise as an :EFFECTS-ONLY step.
When the operator is no longer registered, the effects recorded on the step
are used. If the goal does not yet hold, the recorded preconditions must all
hold; the step is then marked :STORED-APPLY. A missing precondition is not
a new search over the procedure's goal. Up to sixty-one repairs consult the
archive. A procedure whose goals include every missing fact is preferred,
then procedures whose goals stay inside those facts, then procedures that
also achieve something else. When those extra goals cannot be restored,
the steps that serve the missing facts are kept and the others are left
aside. A search restores any fact they leave out. A sixty-second repair uses only
Means-Ends Analysis. The
stored step then continues. If the missing fact cannot be restored, the
procedure does not apply.
Returns (VALUES FINAL-FACTS APPLIED-STEPS EVENTS) when the procedure goals
hold at the end, otherwise (VALUES NIL NIL NIL).
EVENTS are plists (:KIND :SKIP, :APPLY, :PROJECT, :STORED, :REPAIR-GAP,
or :REPAIR, :STEP)."
  (let ((*procedures-in-replay* (cons procedure *procedures-in-replay*))
        (state (copy-list facts))
        (applied nil)
        (events nil))
    (dolist (step (procedure-steps procedure))
      (let* ((goal (getf step :goal))
             (name (getf step :operator))
             (op (find name operators :key #'operator-name :test #'equal))
             (goal-held (and (consp goal) (goal-holds-p goal state))))
        (cond
          ((and goal-held (not (operator-p op)))
           (if (getf step :effects-stored)
               (let ((projected (apply-stored-effects state
                                                      (getf step :adds)
                                                      (getf step :deletes))))
                 (if (%facts-same-p projected state)
                     (push (list :kind :skip :step step) events)
                     (progn
                       (setf state projected)
                       (push (%replay-step-copy step :effects-only t) applied)
                       (push (list :kind :project :step step) events))))
               (push (list :kind :skip :step step) events)))
          (goal-held
           (let* ((stored (bindings-from-step step))
                  (b-pre (extend-bindings-from-state
                          (operator-preconditions op) stored state))
                  (ready (null (precondition-subgoals op b-pre state))))
             (if ready
                 (let ((projected (apply-operator state op b-pre)))
                   (if (%facts-same-p projected state)
                       (push (list :kind :skip :step step) events)
                       (progn
                         (setf state projected)
                         (push (%replay-step-copy step) applied)
                         (push (list :kind :apply :step step) events))))
                 (let* ((b-fx (extend-bindings-from-state
                               (append (operator-preconditions op)
                                       (operator-add-list op)
                                       (operator-delete-list op))
                               stored state))
                        (projected (apply-operator state op b-fx)))
                   (if (%facts-same-p projected state)
                       (push (list :kind :skip :step step) events)
                       (progn
                         (setf state projected)
                         (push (%replay-step-copy step :effects-only t) applied)
                         (push (list :kind :project :step step) events)))))))
          ((operator-p op)
           (let* ((b (extend-bindings-from-state
                      (operator-preconditions op)
                      (bindings-from-step step)
                      state))
                  (missing (precondition-subgoals op b state)))
             (when missing
               (multiple-value-bind (new-state new-applied new-events)
                   (%splice-repair missing state operators applied events
                                   (operator-name op))
                 (unless new-state
                   (return-from replay-procedure (values nil nil nil)))
                 (setf state new-state
                       applied new-applied
                       events new-events))
               (setf b (extend-bindings-from-state
                        (operator-preconditions op)
                        (bindings-from-step step)
                        state))
               (when (precondition-subgoals op b state)
                 (return-from replay-procedure (values nil nil nil))))
             (setf state (apply-operator state op b))
             (push (%replay-step-copy step) applied)
             (push (list :kind :apply :step step) events)))
          ((and (getf step :effects-stored)
                (getf step :preconditions-stored))
           (let ((missing (missing-stored-preconditions step state)))
             (when missing
               (multiple-value-bind (new-state new-applied new-events)
                   (%splice-repair missing state operators applied events
                                   (getf step :operator))
                 (unless new-state
                   (return-from replay-procedure (values nil nil nil)))
                 (setf state new-state
                       applied new-applied
                       events new-events))
               (when (missing-stored-preconditions step state)
                 (return-from replay-procedure (values nil nil nil)))))
           (setf state (apply-stored-effects state
                                             (getf step :adds)
                                             (getf step :deletes)))
           (push (%replay-step-copy step :stored-apply t) applied)
           (push (list :kind :stored :step step) events))
          (t
           (return-from replay-procedure (values nil nil nil))))))
    (if (null (differences state (procedure-goals procedure)))
        (values state (copy-tree (nreverse applied)) (nreverse events))
        (values nil nil nil))))

(defun plan-from-procedure (procedure facts operators &key context-name aside)
  "PLAN from PROCEDURE when REPLAY-PROCEDURE succeeds on FACTS.
Records an honest trace: reused procedure, skipped goals, projected
effects, then each applied step. ASIDE steps are recorded as left aside
and are not executed. Returns NIL when the stored steps do not apply."
  (multiple-value-bind (final steps events)
      (replay-procedure procedure facts operators)
    (unless final
      (return-from plan-from-procedure nil))
    (setf events (append (mapcar (lambda (step)
                                   (list :kind :aside :step step))
                                 aside)
                         events))
    (with-trace (:plan :context-name context-name)
      (when context-name
        (trace-record :context :name context-name))
      (trace-record :reused-procedure
                    :name (procedure-name procedure)
                    :score (procedure-score procedure)
                    :successes (procedure-success-count procedure)
                    :failures (procedure-failure-count procedure))
      (trace-record :goals :goals (copy-list (procedure-goals procedure)))
      (trace-record :state :facts (copy-list facts))
      (dolist (event events)
        (let ((step (getf event :step)))
          (case (getf event :kind)
            (:aside
             (trace-record :step-set-aside
                           :operator (getf step :operator)
                           :goal (getf step :goal)))
            (:skip
             (trace-record :goal-already-satisfied
                           :goal (getf step :goal)
                           :operator (getf step :operator)))
            (:project
             (trace-record :projected-effects
                           :operator (getf step :operator)
                           :goal (getf step :goal)
                           :bindings (bindings-from-step step)))
            (:repair-gap
             (trace-record :missing-precondition
                           :operator (getf event :operator)
                           :goals (getf event :missing)
                           :from-procedure (getf event :from-procedure)))
            (:repair
             (trace-record :repair-step
                           :operator (getf step :operator)
                           :goal (getf step :goal)
                           :bindings (bindings-from-step step)))
            (:stored
             (trace-record :recorded-effects
                           :operator (getf step :operator)
                           :goal (getf step :goal)
                           :bindings (bindings-from-step step))
             (dolist (pre (getf step :preconditions))
               (trace-record :precondition
                             :goal pre
                             :status :satisfied
                             :operator (getf step :operator)))
             (trace-record :action
                           :operator (getf step :operator)
                           :bindings (bindings-from-step step)
                           :goal (getf step :goal)))
            (t
             (let ((op (find (getf step :operator) operators
                             :key #'operator-name :test #'equal))
                   (b (bindings-from-step step)))
               (trace-record :selected-operator
                             :operator (getf step :operator)
                             :bindings b
                             :from-procedure (procedure-name procedure))
               (when (operator-p op)
                 (dolist (pre (operator-preconditions op))
                   (let ((g (ground-pattern pre b)))
                     (unless (fail-p g)
                       (trace-record :precondition
                                     :goal g
                                     :status :satisfied
                                     :operator (operator-name op))))))
               (trace-record :action
                             :operator (getf step :operator)
                             :bindings b
                             :goal (getf step :goal)))))))
      (trace-record :plan-complete
                    :success t
                    :steps (length steps)
                    :remaining nil)
      (make-instance 'plan
                     :goals (copy-list (procedure-goals procedure))
                     :steps steps
                     :success t
                     :initial-state (copy-list facts)
                     :final-state (copy-list final)
                     :remaining nil
                     :operators-used
                     (remove-duplicates
                      (mapcar (lambda (s) (getf s :operator)) steps)
                      :test #'equal)
                     :meta (list :from-procedure (procedure-name procedure)
                                 :procedure-score (procedure-score procedure)
                                 :replay-events events
                                 :trace *current-trace*
                                 :context context-name
                                 :operators operators)))))

(defun %procedures-for-planning (goals &optional (memory (ensure-procedural-memory)))
  "Procedures that can answer a request for GOALS.
Exact matches come first, highest score first. Then procedures whose goals
include GOALS, fewest extra goals first. A procedure that restores only
part of GOALS is combined later, not in this ranking."
  (append (rank-procedures (procedures-for-goals goals memory))
          (remove-if (lambda (procedure)
                       (zerop (%goal-surplus procedure goals)))
                     (%procedures-covering-goals goals memory))))

(defun %trace-archived-step (step)
  (cond
    ((getf step :stored-apply)
     (trace-record :recorded-effects
                   :operator (getf step :operator)
                   :goal (getf step :goal)
                   :bindings (bindings-from-step step)))
    ((getf step :effects-only)
     (trace-record :projected-effects
                   :operator (getf step :operator)
                   :goal (getf step :goal)
                   :bindings (bindings-from-step step)))
    (t
     (trace-record :action
                   :operator (getf step :operator)
                   :goal (getf step :goal)
                   :bindings (bindings-from-step step)))))

(defun %plan-from-pieces (goals pieces final-state operators context-name
                          mea-steps initial)
  "One PLAN whose steps are the archived PIECES followed by MEA-STEPS.
The trace names each reused procedure. :FROM-PROCEDURE stays unset."
  (let ((steps (append (mapcan (lambda (plan)
                                 (copy-tree (plan-steps plan)))
                               pieces)
                       (copy-tree mea-steps))))
    (with-trace (:plan :context-name context-name)
      (when context-name
        (trace-record :context :name context-name))
      (trace-record :goals :goals (copy-list goals))
      (trace-record :state :facts (copy-list initial))
      (dolist (plan pieces)
        (trace-record :reused-procedure
                      :name (getf (plan-meta plan) :from-procedure)
                      :score (getf (plan-meta plan) :procedure-score))
        (dolist (event (getf (plan-meta plan) :replay-events))
          (when (eq (getf event :kind) :aside)
            (let ((step (getf event :step)))
              (trace-record :step-set-aside
                            :operator (getf step :operator)
                            :goal (getf step :goal)))))
        (dolist (step (plan-steps plan))
          (%trace-archived-step step)))
      (dolist (step mea-steps)
        (trace-record :selected-operator
                      :operator (getf step :operator)
                      :bindings (bindings-from-step step)
                      :goal (getf step :goal))
        (trace-record :action
                      :operator (getf step :operator)
                      :bindings (bindings-from-step step)
                      :goal (getf step :goal)))
      (trace-record :plan-complete
                    :success t
                    :steps (length steps)
                    :remaining nil)
      (make-instance 'plan
                     :goals (copy-list goals)
                     :steps steps
                     :success t
                     :initial-state (copy-list initial)
                     :final-state (copy-list final-state)
                     :remaining nil
                     :operators-used
                     (remove-duplicates
                      (mapcar (lambda (step) (getf step :operator)) steps)
                      :test #'equal)
                     :meta (list :from-procedures
                                 (mapcar (lambda (plan)
                                           (getf (plan-meta plan) :from-procedure))
                                         pieces)
                                 :trace *current-trace*
                                 :context context-name
                                 :operators operators)))))

(defun %procedures-within-request (request rest
                                   &optional (memory (ensure-procedural-memory)))
  "Procedures whose goals stay inside REQUEST and meet REST.
A procedure that already covers the whole REQUEST is omitted: planning
tried it before combining parts. One that covers REST comes first, then
the largest overlap. Score, then success count, then name breaks a tie."
  (sort (remove-if-not
         (lambda (procedure)
           (let ((procedure-goals (procedure-goals procedure)))
             (and procedure-goals
                  (not (%goals-covered-p request procedure))
                  (null (set-difference procedure-goals request :test #'equal))
                  (some (lambda (goal)
                          (member goal rest :test #'equal))
                        procedure-goals))))
         (copy-list (procedural-memory-procedures memory)))
        (lambda (a b)
          (let ((cover-a (if (%goals-covered-p rest a) 1 0))
                (cover-b (if (%goals-covered-p rest b) 1 0)))
            (or (> cover-a cover-b)
                (and (= cover-a cover-b)
                     (let ((overlap-a (%goal-overlap a rest))
                           (overlap-b (%goal-overlap b rest)))
                       (or (> overlap-a overlap-b)
                           (and (= overlap-a overlap-b)
                                (%score-then-name< a b))))))))))

(defun %procedures-overlapping-request (request rest
                                        &optional (memory (ensure-procedural-memory)))
  "Procedures that meet REST and also achieve a goal outside REQUEST.
They do not cover REQUEST. Most shared REST facts first, then fewest
goals outside REQUEST. Score, then success count, then name breaks a tie."
  (sort (remove-if-not
         (lambda (procedure)
           (let ((procedure-goals (procedure-goals procedure)))
             (and procedure-goals
                  (not (%goals-covered-p request procedure))
                  (some (lambda (goal)
                          (member goal rest :test #'equal))
                        procedure-goals)
                  (some (lambda (goal)
                          (not (member goal request :test #'equal)))
                        procedure-goals))))
         (copy-list (procedural-memory-procedures memory)))
        (lambda (a b)
          (let ((overlap-a (%goal-overlap a rest))
                (overlap-b (%goal-overlap b rest)))
            (or (> overlap-a overlap-b)
                (and (= overlap-a overlap-b)
                     (let ((extra-a (%goal-surplus a request))
                           (extra-b (%goal-surplus b request)))
                       (or (< extra-a extra-b)
                           (and (= extra-a extra-b)
                                (%score-then-name< a b))))))))))

(defun %plan-from-partial-procedures (goals state operators context-name
                                      &optional used initial pieces)
  "Combine procedures that achieve part of GOALS. Procedures whose goals
stay inside the request come first, then procedures that also achieve
something else; those extra goals are applied. A search restores a
remainder only after some procedure has already contributed.
Returns a PLAN, or NIL when the pieces do not achieve GOALS."
  (let ((rest (%facts-still-missing goals state))
        (initial (or initial state)))
    (unless rest
      (return-from %plan-from-partial-procedures
        (when pieces
          (%plan-from-pieces goals pieces state operators context-name
                             nil initial))))
    (dolist (procedure (append (%procedures-within-request goals rest)
                               (%procedures-overlapping-request goals rest)))
      (unless (member procedure used :test #'eq)
        (let ((plan (or (plan-from-procedure procedure state operators
                                            :context-name context-name)
                       (%plan-without-blocked-extras procedure goals state
                                                     operators
                                                     :context-name context-name))))
          (when plan
            (let* ((state2 (or (plan-final-state plan) state))
                   (left (%facts-still-missing goals state2)))
              (when (< (length left) (length rest))
                (let ((combined
                       (if (null left)
                           (%plan-from-pieces goals
                                              (append pieces (list plan))
                                              state2 operators context-name
                                              nil initial)
                           (%plan-from-partial-procedures
                            goals state2 operators context-name
                            (cons procedure used)
                            initial
                            (append pieces (list plan))))))
                  (when combined
                    (return-from %plan-from-partial-procedures combined)))))))))
    (when used
      (let ((mea-final nil)
            (mea-steps nil))
        (let ((*trace-enabled* nil))
          (multiple-value-bind (ok final steps left)
              (means-ends-analyze state rest operators)
            (when (and ok (null left))
              (setf mea-final (or final state)
                    mea-steps steps))))
        (when mea-final
          (%plan-from-pieces goals pieces mea-final operators context-name
                             mea-steps initial))))))

(defun plan-from-ranked-procedures (context goals operators)
  "Archived procedure for GOALS whose steps replay on CONTEXT.
An exact goal match is preferred. Otherwise a procedure whose goals include
GOALS is used, fewest extra goals first, and those extra goals are applied.
When no such procedure applies, procedures that each achieve part of GOALS
are combined: goals that stay inside the request first, then procedures
that also achieve something else. When those extra goals cannot be
restored, the steps that serve the request are kept and the others are
left aside. A search fills anything they leave.
The next procedure is tried when a higher-ranked one does not apply."
  (let ((facts (context-all-facts context))
        (context-name (context-name context)))
    (or (dolist (procedure (%procedures-for-planning goals))
          (let ((plan (or (plan-from-procedure procedure facts operators
                                               :context-name context-name)
                          (%plan-without-blocked-extras
                           procedure goals facts operators
                           :context-name context-name))))
            (when plan
              (return plan))))
        (%plan-from-partial-procedures goals facts operators context-name))))

(defun plan-consulting-archive (context &key goals operators (archive t))
  "Plan for CONTEXT. When ARCHIVE is true, try a scored procedure whose
goals include the request and whose steps still apply; an exact match
comes first. Otherwise combine procedures that each achieve part of the
request, those with no extra goals first. If those do not apply,
Means-Ends Analysis."
  (let* ((g (normalize-planning-goals (or goals (goals-of context))))
         (ops (or operators (context-planning-operators context)))
         (plan (or (and archive
                        (plan-from-ranked-procedures context g ops))
                   (plan-from-context context :goals g :operators ops))))
    (when plan
      (remember-plan-external-actions plan :context context :operators ops))
    plan))
