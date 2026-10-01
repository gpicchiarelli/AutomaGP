;;;; memory/procedural.lisp — procedural memory and the procedure archive
;;;;
;;;; Named, scored procedures taken from successful plans; the hooks that
;;;; keep the session store and the archive file together; and the reuse of
;;;; those procedures at planning time by symbolic replay. The file format
;;;; and the reading and writing themselves are in memory/persistence.lisp.

(in-package #:automa-gp)

;;; ---------------------------------------------------------------------------
;;; Conditions
;;; ---------------------------------------------------------------------------

(define-condition unknown-procedure (gp-error)
  ((name :initarg :name :reader unknown-procedure-name))
  (:report (lambda (c stream)
             (format stream "No procedure named ~S in the archive."
                     (unknown-procedure-name c))))
  (:documentation "A procedure was asked for by a name the store does not hold."))

(define-condition unsuccessful-plan (gp-error)
  ((plan :initarg :plan :reader unsuccessful-plan-plan))
  (:report "Only a successful plan can become a procedure.")
  (:documentation "A plan that did not succeed was offered as a procedure."))

(define-condition procedure-archive-error (gp-error)
  ((path :initarg :path :reader procedure-archive-error-path)
   (action :initarg :action :reader procedure-archive-error-action
           :documentation ":READ or :WRITE.")
   (cause :initarg :cause :reader procedure-archive-error-cause :initform nil
          :documentation "The condition signalled underneath, or NIL."))
  (:report (lambda (c stream)
             (format stream "Cannot ~(~A~) the procedure archive ~A~@[: ~A~]"
                     (procedure-archive-error-action c)
                     (procedure-archive-error-path c)
                     (procedure-archive-error-cause c))))
  (:documentation "The archive file could not be read or written.
Signalled with the restarts RETRY and SKIP in place; session memory is
coherent whichever is taken."))

;;; ---------------------------------------------------------------------------
;;; Procedures and the store
;;; ---------------------------------------------------------------------------

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
  "True when OBJECT is a GP-PROCEDURE."
  (typep object 'gp-procedure))

(defclass procedural-memory ()
  ((procedures
    :initarg :procedures
    :accessor procedural-memory-procedures
    :initform nil
    :documentation "GP-PROCEDURE objects, one per name, newest first.")
   (meta
    :initarg :meta
    :accessor procedural-memory-meta
    :initform nil))
  (:documentation "Store of reusable procedures."))

(defun procedural-memory-p (object)
  "True when OBJECT is a PROCEDURAL-MEMORY store."
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
  "True once this image has read the archive file, written it, or set it
aside (CLEAR-PROCEDURAL-MEMORY, the SKIP restart). Autoload then leaves
the file alone.")

(defvar *loading-procedure-archive* nil
  "Bound during LOAD-PROCEDURE-ARCHIVE to avoid recursive autoload.")

(defun make-procedural-memory (&key procedures meta)
  "A PROCEDURAL-MEMORY store holding PROCEDURES. The list and META are copied."
  (make-instance 'procedural-memory
                 :procedures (copy-list procedures)
                 :meta (copy-tree meta)))

(defun ensure-procedural-memory ()
  "The session store, created when missing. The first call in an image
also reads the archive file (see MAYBE-AUTOLOAD-PROCEDURE-ARCHIVE)."
  (unless (procedural-memory-p *procedural-memory*)
    (setf *procedural-memory* (make-procedural-memory)))
  (maybe-autoload-procedure-archive)
  *procedural-memory*)

(defun clear-procedural-memory ()
  "Drop in-memory procedures. The archive file is left on disk.
Does not autoload again until LOAD-PROCEDURE-ARCHIVE. A later autosave
adds to the file: the procedures dropped here stay in it."
  (setf *procedural-memory* nil)
  (setf *procedure-archive-loaded* t)
  t)

(defun make-procedure (&key name goals steps operators-used initial-state
                         (success-count 1) (failure-count 0)
                         last-success-at last-failure-at meta)
  "A GP-PROCEDURE. Every list argument is copied; nothing is stored in a
memory. A NIL count means the default: one success, no failure."
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

(defun find-procedure (name &optional (memory (ensure-procedural-memory)))
  "The procedure called NAME in MEMORY (names compare with EQUAL), or NIL."
  (find name (procedural-memory-procedures memory)
        :key #'procedure-name :test #'equal))

(defun %procedure-named (name memory)
  "The procedure called NAME in MEMORY.
Signals UNKNOWN-PROCEDURE when there is none; USE-VALUE supplies another name."
  (or (find-procedure name memory)
      (restart-case (error 'unknown-procedure :name name)
        (:use-value (other-name)
          :report "Use the procedure with another name."
          :interactive (lambda () (read-form-prompt "Procedure name"))
          (%procedure-named other-name memory)))))

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

;;; ---------------------------------------------------------------------------
;;; The archive file
;;; ---------------------------------------------------------------------------

(defmacro with-archive-errors ((action) &body body)
  "Run BODY. An error it signals becomes a PROCEDURE-ARCHIVE-ERROR for
ACTION (:READ or :WRITE) on *PROCEDURE-ARCHIVE-PATH*, the original as its cause."
  `(handler-bind (((and error (not procedure-archive-error))
                    (lambda (cause)
                      (error 'procedure-archive-error
                             :path *procedure-archive-path*
                             :action ,action
                             :cause cause))))
     ,@body))

(defun %call-with-archive-restarts (thunk retry-report skip-report)
  "Call THUNK and return its value.
While it runs, RETRY calls it again and SKIP returns NIL instead."
  (loop
    (restart-case (return (funcall thunk))
      (:retry ()
        :report (lambda (stream) (write-string retry-report stream)))
      (:skip ()
        :report (lambda (stream) (write-string skip-report stream))
        (return nil)))))

(defun %procedure-archive-file ()
  "The archive file to read, or NIL when there is none.
*PROCEDURE-ARCHIVE-PATH* itself; else, for an .agp path, its .sexp sibling
(an archive written before the rename)."
  (with-archive-errors (:read)
    (let ((path (pathname *procedure-archive-path*)))
      (or (probe-file path)
          (and (equalp (pathname-type path) "agp")
               (probe-file (make-pathname :defaults path :type "sexp")))))))

(defun %archive-file-procedures ()
  "Procedures in the archive file, in file order; NIL when there is no file.
The file is read with *READ-EVAL* off and into a scratch store, so a file
that cannot be read leaves session memory as it was.
Signals PROCEDURE-ARCHIVE-ERROR."
  (when (%procedure-archive-file)
    (let ((*procedural-memory* (make-procedural-memory))
          (*procedure-archive-loaded* t)
          (*read-eval* nil))
      (with-archive-errors (:read)
        (load-procedure-archive *procedure-archive-path*))
      (reverse (procedural-memory-procedures *procedural-memory*)))))

(defun maybe-autoload-procedure-archive ()
  "Read the archive file into session memory, once per image.
Nothing happens while autoload is off, once the file was read, written or
set aside, during a load, or when there is no file (*PROCEDURE-ARCHIVE-PATH*,
or a sibling .sexp of an .agp path).
A file that cannot be read signals PROCEDURE-ARCHIVE-ERROR and leaves
session memory untouched. RETRY reads it again; SKIP continues without it.
After any other exit the next call tries again."
  (when (and *procedure-archive-autoload*
             (not *procedure-archive-loaded*)
             (not *loading-procedure-archive*)
             (%procedure-archive-file))
    (let ((memory *procedural-memory*))
      (dolist (procedure (%call-with-archive-restarts
                          #'%archive-file-procedures
                          "Read the procedure archive file again."
                          "Continue without the procedure archive file."))
        (install-procedure! procedure memory)))
    (setf *procedure-archive-loaded* t)))

(defun maybe-autosave-procedure-archive (&optional (memory *procedural-memory*))
  "Write MEMORY to the archive file when autosave is on and MEMORY is the
session store; any other store is its owner's to save.
The write only adds to the file or updates it: a procedure in the file
whose name MEMORY does not hold is kept, so procedures this session never
read, or dropped with CLEAR-PROCEDURAL-MEMORY, are not lost.
When the file cannot be read or written this signals
PROCEDURE-ARCHIVE-ERROR. RETRY tries again; SKIP leaves the file as it is.
MEMORY keeps its change either way. Returns true when the file was written."
  (when (and *procedure-archive-autosave*
             memory
             (eq memory *procedural-memory*))
    (%call-with-archive-restarts
     (lambda ()
       (let ((only-in-file (remove-if (lambda (procedure)
                                        (find-procedure (procedure-name procedure)
                                                        memory))
                                      (%archive-file-procedures))))
         (with-archive-errors (:write)
           (save-procedure-archive
            :path *procedure-archive-path*
            :memory (make-procedural-memory
                     :procedures (append (procedural-memory-procedures memory)
                                         only-in-file))))
         (setf *procedure-archive-loaded* t)))
     "Try to write the procedure archive file again."
     "Keep the change in memory and leave the archive file as it is.")))

;;; ---------------------------------------------------------------------------
;;; Storing and scoring
;;; ---------------------------------------------------------------------------

(defun %default-procedure-name (context-name &optional (ordinal 1))
  "PROC-<CONTEXT-NAME>, with -ORDINAL appended after the first.
Interned in AUTOMA-GP, so the name does not depend on the caller's *PACKAGE*."
  (intern (format nil "PROC-~A~@[-~D~]"
                  (or context-name 'unnamed)
                  (when (> ordinal 1) ordinal))
          :automa-gp))

(defun procedure-from-plan (plan &key name)
  "Turn a successful PLAN into a reusable GP-PROCEDURE. Nothing is stored.
NAME defaults to PROC-<context>, interned in AUTOMA-GP whatever *PACKAGE* is.
Steps are stored without the :EFFECTS-ONLY and :STORED-APPLY marks of the
replay that produced them: those describe one replay, not the procedure.
Signals UNSUCCESSFUL-PLAN when PLAN did not succeed."
  (check-type plan plan)
  (unless (plan-success plan)
    (error 'unsuccessful-plan :plan plan))
  (let ((context-name (getf (plan-meta plan) :context)))
    (make-procedure :name (or name (%default-procedure-name context-name))
                    :goals (plan-goals plan)
                    :steps (mapcar #'%replay-step-copy (plan-steps plan))
                    :operators-used (plan-operators-used plan)
                    :initial-state (plan-initial-state plan)
                    :meta (list :from-plan t :context context-name))))

(defun install-procedure! (procedure &optional (memory (ensure-procedural-memory)))
  "Store PROCEDURE as-is, replacing the same name. No score bump, no autosave."
  (let ((name (procedure-name procedure)))
    (setf (procedural-memory-procedures memory)
          (cons procedure
                (remove name (procedural-memory-procedures memory)
                        :key #'procedure-name :test #'equal)))
    procedure))

(defun remember-procedure! (procedure &optional (memory (ensure-procedural-memory)))
  "Store PROCEDURE in MEMORY as one more success.
When MEMORY holds a procedure with the same name and the same goals, its
successes are added and its failures kept. Under the same name with other
goals PROCEDURE replaces it and keeps its own counts: the earlier history
says nothing about the new goals.
Session memory is then written to the archive file when autosave is on
(see MAYBE-AUTOSAVE-PROCEDURE-ARCHIVE for its condition and restarts)."
  (let ((old (find-procedure (procedure-name procedure) memory)))
    (when (and old
               (not (eq old procedure))
               (%facts-same-p (procedure-goals old) (procedure-goals procedure)))
      (setf (procedure-success-count procedure)
            (+ (procedure-success-count old)
               (max 1 (procedure-success-count procedure))))
      (setf (procedure-failure-count procedure)
            (procedure-failure-count old))
      (setf (procedure-last-failure-at procedure)
            (procedure-last-failure-at old)))
    (setf (procedure-last-success-at procedure) (get-universal-time))
    (install-procedure! procedure memory)
    (maybe-autosave-procedure-archive memory)
    procedure))

(defun score-procedure! (name &key (success t)
                               (memory (ensure-procedural-memory)))
  "Record a later replay of the procedure named NAME.
:SUCCESS T increments successes; NIL increments failures. Autosaves session
memory. Signals UNKNOWN-PROCEDURE when MEMORY has no such procedure;
USE-VALUE scores the procedure with another name."
  (let ((procedure (%procedure-named name memory)))
    (if success
        (progn
          (incf (procedure-success-count procedure))
          (setf (procedure-last-success-at procedure) (get-universal-time)))
        (progn
          (incf (procedure-failure-count procedure))
          (setf (procedure-last-failure-at procedure) (get-universal-time))))
    (maybe-autosave-procedure-archive memory)
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
for each procedure it replayed, and write the archive file once.
A procedure no longer in the archive is passed over. Procedures reused
only inside a precondition repair are not scored: the plan names them in
its trace, not as the procedures it was built from.
Simulation must not call this — only a finished live execution.
Returns (VALUES FIRST-SCORED ALL-SCORED), both in the order PLAN replayed
them; NIL when nothing was scored."
  (let ((scored (let ((*procedure-archive-autosave* nil))
                  (loop for name in (plan-reused-procedure-names plan)
                        when (and name (find-procedure name))
                          collect (score-procedure! name :success success)))))
    (when scored
      (maybe-autosave-procedure-archive))
    (values (first scored) scored)))

(defun %unclaimed-default-name (procedure memory)
  "First of PROC-<context>, PROC-<context>-2, … that MEMORY does not use
for goals other than PROCEDURE's."
  (loop with context-name = (getf (procedure-meta procedure) :context)
        for ordinal from 1
        for name = (%default-procedure-name context-name ordinal)
        for holder = (find-procedure name memory)
        when (or (null holder)
                 (%facts-same-p (procedure-goals holder)
                                (procedure-goals procedure)))
          return name))

(defun remember-procedure-from-plan! (plan &key name
                                          (memory (ensure-procedural-memory)))
  "Convert a successful PLAN into a procedure and store it.
Without NAME the procedure is called PROC-<context>. When that name already
belongs to a procedure for other goals, PROC-<context>-2, -3, … is used, so
an unnamed plan never replaces a procedure that achieves something else."
  (let ((procedure (procedure-from-plan plan :name name)))
    (unless name
      (setf (procedure-name procedure)
            (%unclaimed-default-name procedure memory)))
    (remember-procedure! procedure memory)))

;;; ---------------------------------------------------------------------------
;;; Ranking
;;; ---------------------------------------------------------------------------

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

(defun %rank-by (procedures &rest keys)
  "Fresh list of PROCEDURES, largest first by each of KEYS in turn.
Each key is a function from a procedure to a number. Score, then success
count, then name breaks a tie, so the order does not depend on the order
of PROCEDURES."
  (sort (copy-list procedures)
        (lambda (a b)
          (dolist (key keys (%score-then-name< a b))
            (let ((key-a (funcall key a))
                  (key-b (funcall key b)))
              (cond ((> key-a key-b) (return t))
                    ((< key-a key-b) (return nil))))))))

(defun rank-procedures (procedures)
  "Fresh list of PROCEDURES, highest PROCEDURE-SCORE first.
More successes, then the name, breaks a tie."
  (%rank-by procedures))

(defun procedures-for-goals (goals &optional (memory (ensure-procedural-memory)))
  "Procedures whose goal set equals GOALS (order-insensitive EQUAL)."
  (remove-if-not (lambda (procedure)
                   (%facts-same-p goals (procedure-goals procedure)))
                 (procedural-memory-procedures memory)))

(defun archive-best (goals &optional (memory (ensure-procedural-memory)))
  "Highest-scoring archived procedure whose goals equal GOALS, or NIL."
  (first (rank-procedures (procedures-for-goals goals memory))))

(defun %goals-covered-p (goals procedure)
  "True when every fact in GOALS is one of PROCEDURE's goals."
  (null (set-difference goals (procedure-goals procedure) :test #'equal)))

(defun %goal-surplus (procedure goals)
  "How many of PROCEDURE's goals are not in GOALS."
  (length (set-difference (procedure-goals procedure) goals :test #'equal)))

(defun %goal-overlap (procedure goals)
  "How many facts in GOALS are also goals of PROCEDURE."
  (count-if (lambda (goal)
              (member goal (procedure-goals procedure) :test #'equal))
            goals))

(defun %procedures-covering-goals (goals &optional (memory (ensure-procedural-memory)))
  "Procedures whose goals include every fact in GOALS.
None when GOALS is empty: nothing was asked for, so nothing is replayed.
Fewest extra goals first. Score, then success count, then name breaks a tie."
  (when goals
    (%rank-by (remove-if-not (lambda (procedure)
                               (%goals-covered-p goals procedure))
                             (procedural-memory-procedures memory))
              (lambda (procedure) (- (%goal-surplus procedure goals))))))

(defun %procedures-within-request (request &optional (rest request)
                                             (memory (ensure-procedural-memory)))
  "Procedures whose goals stay inside REQUEST and meet REST, the part of
REQUEST still open. A procedure that covers the whole REQUEST is omitted:
those are tried before parts are combined. One that covers REST comes
first, then the largest overlap with REST. Score, then success count, then
name breaks a tie."
  (%rank-by (remove-if-not
             (lambda (procedure)
               (and (not (%goals-covered-p request procedure))
                    (zerop (%goal-surplus procedure request))
                    (plusp (%goal-overlap procedure rest))))
             (procedural-memory-procedures memory))
            (lambda (procedure) (if (%goals-covered-p rest procedure) 1 0))
            (lambda (procedure) (%goal-overlap procedure rest))))

(defun %procedures-overlapping-request (request &optional (rest request)
                                                  (memory (ensure-procedural-memory)))
  "Procedures that meet REST, the part of REQUEST still open, and also
achieve a goal outside REQUEST. They do not cover REQUEST. Most shared REST
facts first, then fewest goals outside REQUEST. Score, then success count,
then name breaks a tie."
  (%rank-by (remove-if-not
             (lambda (procedure)
               (and (not (%goals-covered-p request procedure))
                    (plusp (%goal-surplus procedure request))
                    (plusp (%goal-overlap procedure rest))))
             (procedural-memory-procedures memory))
            (lambda (procedure) (%goal-overlap procedure rest))
            (lambda (procedure) (- (%goal-surplus procedure request)))))

(defun %procedures-for-planning (goals &optional (memory (ensure-procedural-memory)))
  "Procedures that can answer a request for GOALS; none when GOALS is empty.
Exact matches come first, highest score first. Then procedures whose goals
include GOALS, fewest extra goals first. A procedure that restores only
part of GOALS is combined later, not in this ranking."
  (when goals
    (append (rank-procedures (procedures-for-goals goals memory))
            (remove-if (lambda (procedure)
                         (zerop (%goal-surplus procedure goals)))
                       (%procedures-covering-goals goals memory)))))

;;; ---------------------------------------------------------------------------
;;; Plans rebuilt without a check
;;; ---------------------------------------------------------------------------

(defun %operators-in-steps (steps)
  "Operator names used by STEPS, each once."
  (remove-duplicates (mapcar (lambda (step) (getf step :operator)) steps)
                     :test #'equal))

(defun %recorded-final-state (procedure)
  "Facts after every step's recorded effects are applied to PROCEDURE's
initial state. NIL when a step carries no recorded effects: the final state
is then not known."
  (let ((state (copy-list (procedure-initial-state procedure))))
    (dolist (step (procedure-steps procedure) state)
      (unless (getf step :effects-stored)
        (return nil))
      (setf state (apply-stored-effects state
                                        (getf step :adds)
                                        (getf step :deletes))))))

(defun procedure->plan (procedure &key (meta nil))
  "Rebuild a PLAN object from a stored PROCEDURE (does not re-run MEA).
Does not check that the steps still apply to the live state — use
PLAN-FROM-PROCEDURE for that. The plan's initial state is the one the
procedure was recorded in, and its final state is that state after the
recorded effects of every step. A step without recorded effects (a
procedure built by hand) leaves the final state unknown, as NIL."
  (make-instance 'plan
                 :goals (copy-list (procedure-goals procedure))
                 :steps (copy-tree (procedure-steps procedure))
                 :success t
                 :initial-state (copy-list (procedure-initial-state procedure))
                 :final-state (%recorded-final-state procedure)
                 :remaining nil
                 :operators-used (copy-list (procedure-operators-used procedure))
                 :meta (list* :from-procedure (procedure-name procedure)
                              meta)))

;;; ---------------------------------------------------------------------------
;;; Replay and precondition repair
;;; ---------------------------------------------------------------------------

(defvar *procedure-repair-depth* 0
  "How many precondition repairs are already in progress.")

(defparameter *procedure-repair-archive-depth* 61
  "How many nested precondition repairs may reuse an archived procedure.
A deeper repair uses Means-Ends Analysis only. This bounds the work, not
termination: a repair never reuses a procedure that is already being
replayed, so the nesting cannot exceed the number of archived procedures.")

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

(defun %facts-still-missing (facts state)
  "The members of FACTS that do not hold in STATE.
A member that is not a list never holds, as in MISSING-STORED-PRECONDITIONS."
  (remove-if (lambda (fact)
               (and (consp fact) (goal-holds-p fact state)))
             facts))

(defun %repair-gap-event (missing operator from-procedure)
  (list :kind :repair-gap
        :missing (copy-tree missing)
        :operator operator
        :from-procedure from-procedure))

(defun %repair-step-events (steps)
  "One :REPAIR event for each of STEPS."
  (mapcar (lambda (step) (list :kind :repair :step step)) steps))

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
                              (%repair-step-events rest-steps))))))))

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

(defun %plan-from-replay (procedure facts operators &key context-name aside)
  "PLAN from PROCEDURE when REPLAY-PROCEDURE succeeds on FACTS, else NIL.
ASIDE steps are recorded as left aside and are not executed. The plan
carries its replay events and no deliberative trace: a caller that
returns it to the user adds one with %TRACE-REPLAYED-PLAN."
  (multiple-value-bind (final steps events)
      (replay-procedure procedure facts operators)
    (when final
      (make-instance 'plan
                     :goals (copy-list (procedure-goals procedure))
                     :steps steps
                     :success t
                     :initial-state (copy-list facts)
                     :final-state (copy-list final)
                     :remaining nil
                     :operators-used (%operators-in-steps steps)
                     :meta (list :from-procedure (procedure-name procedure)
                                 :procedure-score (procedure-score procedure)
                                 :replay-events
                                 (append (mapcar (lambda (step)
                                                   (list :kind :aside :step step))
                                                 aside)
                                         events)
                                 :context context-name
                                 :operators operators)))))

(defun %plan-without-blocked-extras (procedure missing state operators
                                      &key context-name)
  "Replay PROCEDURE without steps that only serve goals outside MISSING.
Used when the full replay fails because those extra goals cannot be restored.
The omitted steps are left aside. Returns a PLAN without a trace, or NIL."
  (when (plusp (%goal-surplus procedure missing))
    (multiple-value-bind (narrow omitted)
        (%procedure-focused procedure missing)
      (when (and narrow (procedure-goals narrow) omitted)
        ;; The narrowed copy is another object. PROCEDURE itself goes on the
        ;; replay stack, or a repair inside the copy would reuse it and
        ;; bring back the steps that were just left aside.
        (let ((*procedures-in-replay* (cons procedure *procedures-in-replay*)))
          (%plan-from-replay narrow state operators
                             :context-name context-name
                             :aside omitted))))))

(defun %repair-assemble (missing state operators for-operator used)
  "Restore MISSING by replaying archived procedures, then a search for
whatever those procedures did not achieve.
A procedure that covers every remaining fact is tried first, then one whose
goals stay inside those facts, then one that also achieves something else.
A procedure that restores a part counts only when the rest can be restored
after it; otherwise the next one is tried. USED procedures, and procedures
already being replayed, are not replayed again.
Returns (VALUES NEW-STATE STEPS FROM-PROCEDURE REPLAY-EVENTS) or NIL.
FROM-PROCEDURE is set only when a single procedure achieved MISSING."
  (dolist (procedure (append (%procedures-covering-goals missing)
                             (%procedures-within-request missing)
                             (%procedures-overlapping-request missing)))
    (unless (or (member procedure used :test #'eq)
                (member procedure *procedures-in-replay* :test #'eq))
      (let ((plan (or (%plan-from-replay procedure state operators)
                      (%plan-without-blocked-extras procedure missing
                                                    state operators))))
        (when plan
          (let* ((state2 (or (plan-final-state plan) state))
                 (rest (%facts-still-missing missing state2)))
            (when (< (length rest) (length missing))
              (multiple-value-bind (new-state steps name replay-events)
                  (if (null rest)
                      (values state2
                              (plan-steps plan)
                              (procedure-name procedure)
                              (getf (plan-meta plan) :replay-events))
                      (%combine-partial-repair procedure plan rest state2
                                               operators for-operator used))
                (when new-state
                  (return-from %repair-assemble
                    (values new-state steps name replay-events))))))))))
  (when used
    (multiple-value-bind (mea-state mea-steps)
        (%repair-by-search missing state operators)
      (when mea-state
        (values mea-state mea-steps nil (%repair-step-events mea-steps))))))

(defun %repair-missing (missing state operators &optional for-operator)
  "Restore MISSING facts. Up to *PROCEDURE-REPAIR-ARCHIVE-DEPTH* nested
repairs consult the archive (see %REPAIR-ASSEMBLE for the order). When the
archive does not restore them, and in any deeper repair, a Means-Ends
search is used.
Returns (VALUES NEW-STATE STEPS FROM-PROCEDURE REPLAY-EVENTS) or NIL."
  (let ((*procedure-repair-depth* (1+ *procedure-repair-depth*)))
    (when (<= *procedure-repair-depth* *procedure-repair-archive-depth*)
      (multiple-value-bind (new-state steps name replay-events)
          (%repair-assemble missing state operators for-operator nil)
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
    (push (%repair-gap-event missing for-operator from-procedure) events)
    (dolist (repair-step repair-steps)
      (push repair-step applied))
    (values new-state
            applied
            (%splice-replay-events (or replay-events
                                       (%repair-step-events repair-steps))
                                   events))))

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
a new search over the procedure's goal: it is repaired, and the stored step
then continues. The first *PROCEDURE-REPAIR-ARCHIVE-DEPTH* nested repairs
consult the archive. A procedure whose goals include every missing fact is
preferred, then procedures whose goals stay inside those facts, then
procedures that also achieve something else. When those extra goals cannot
be restored, the steps that serve the missing facts are kept and the others
are left aside. A search restores any fact they leave out. A deeper repair
uses only Means-Ends Analysis. If the missing fact cannot be restored, the
procedure does not apply.
No deliberative trace is written.
Returns (VALUES FINAL-FACTS APPLIED-STEPS EVENTS) when the procedure goals
hold at the end, otherwise (VALUES NIL NIL NIL).
EVENTS are plists (:KIND :SKIP, :APPLY, :PROJECT, :STORED, :REPAIR-GAP,
:REPAIR or :ASIDE, :STEP)."
  (let ((*procedures-in-replay* (cons procedure *procedures-in-replay*))
        (state (copy-list facts))
        (applied nil)
        (events nil))
    (labels ((note (kind step)
               (push (list :kind kind :step step) events))
             (advance (projected step kind &rest copy-flags)
               ;; A step that would change nothing is skipped, not applied.
               (cond ((%facts-same-p projected state)
                      (note :skip step))
                     (t
                      (setf state projected)
                      (push (apply #'%replay-step-copy step copy-flags) applied)
                      (note kind step))))
             (repair (missing for-operator)
               ;; True when the repair steps were spliced in.
               (multiple-value-bind (new-state new-applied new-events)
                   (%splice-repair missing state operators applied events
                                   for-operator)
                 (when new-state
                   (setf state new-state
                         applied new-applied
                         events new-events)
                   t)))
             (does-not-apply ()
               (return-from replay-procedure (values nil nil nil))))
      (dolist (step (procedure-steps procedure))
        (let* ((goal (getf step :goal))
               (op (find (getf step :operator) operators
                         :key #'operator-name :test #'equal))
               (goal-held (and (consp goal) (goal-holds-p goal state)))
               (stored (bindings-from-step step)))
          (cond
            ;; Goal holds, operator gone: only the recorded effects are left.
            ((and goal-held (not (operator-p op)))
             (if (getf step :effects-stored)
                 (advance (apply-stored-effects state
                                                (getf step :adds)
                                                (getf step :deletes))
                          step :project :effects-only t)
                 (note :skip step)))
            ;; Goal holds, operator registered: a normal step when its
            ;; preconditions hold, otherwise its leftover effects.
            (goal-held
             (let ((b (extend-bindings-from-state
                       (operator-preconditions op) stored state)))
               (if (null (precondition-subgoals op b state))
                   (advance (apply-operator state op b) step :apply)
                   (advance (apply-operator
                             state op
                             (extend-bindings-from-state
                              (append (operator-preconditions op)
                                      (operator-add-list op)
                                      (operator-delete-list op))
                              stored state))
                            step :project :effects-only t))))
            ;; Goal open, operator registered.
            ((operator-p op)
             (flet ((bindings ()
                      (extend-bindings-from-state
                       (operator-preconditions op) stored state)))
               (let ((missing (precondition-subgoals op (bindings) state)))
                 (when (and missing
                            (not (and (repair missing (operator-name op))
                                      (null (precondition-subgoals
                                             op (bindings) state)))))
                   (does-not-apply)))
               (setf state (apply-operator state op (bindings)))
               (push (%replay-step-copy step) applied)
               (note :apply step)))
            ;; Goal open, operator gone: the step as it was recorded.
            ((and (getf step :effects-stored)
                  (getf step :preconditions-stored))
             (let ((missing (missing-stored-preconditions step state)))
               (when (and missing
                          (not (and (repair missing (getf step :operator))
                                    (null (missing-stored-preconditions
                                           step state)))))
                 (does-not-apply)))
             (setf state (apply-stored-effects state
                                               (getf step :adds)
                                               (getf step :deletes)))
             (push (%replay-step-copy step :stored-apply t) applied)
             (note :stored step))
            (t
             (does-not-apply))))))
    (if (null (differences state (procedure-goals procedure)))
        (values state (copy-tree (nreverse applied)) (nreverse events))
        (values nil nil nil))))

;;; ---------------------------------------------------------------------------
;;; The trace of a replayed plan
;;; ---------------------------------------------------------------------------

(defun %trace-replay-event (event procedure-name operators)
  "Record one replay EVENT of the procedure PROCEDURE-NAME in the current trace."
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
                       :from-procedure procedure-name)
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

(defun %trace-replayed-plan (plan procedure)
  "Write the deliberative trace of PLAN, a replay of PROCEDURE, and attach
it to PLAN: the reused procedure, skipped goals, projected effects, then
each applied step. Returns PLAN.
Only the plan handed back to the user is traced, so a replay that was
tried and dropped, or that became one piece of a larger plan, leaves no
trace of its own in the session history."
  (let* ((meta (plan-meta plan))
         (name (getf meta :from-procedure))
         (context-name (getf meta :context))
         (operators (getf meta :operators)))
    (with-trace (:plan :context-name context-name)
      (when context-name
        (trace-record :context :name context-name))
      (trace-record :reused-procedure
                    :name name
                    :score (getf meta :procedure-score)
                    :successes (procedure-success-count procedure)
                    :failures (procedure-failure-count procedure))
      (trace-record :goals :goals (copy-list (plan-goals plan)))
      (trace-record :state :facts (copy-list (plan-initial-state plan)))
      (dolist (event (getf meta :replay-events))
        (%trace-replay-event event name operators))
      (trace-record :plan-complete
                    :success t
                    :steps (plan-length plan)
                    :remaining nil)
      (setf (getf (plan-meta plan) :trace) *current-trace*))
    plan))

(defun plan-from-procedure (procedure facts operators &key context-name aside)
  "PLAN from PROCEDURE when REPLAY-PROCEDURE succeeds on FACTS.
Records an honest trace: reused procedure, skipped goals, projected
effects, then each applied step. ASIDE steps are recorded as left aside
and are not executed. Returns NIL when the stored steps do not apply."
  (let ((plan (%plan-from-replay procedure facts operators
                                 :context-name context-name
                                 :aside aside)))
    (when plan
      (%trace-replayed-plan plan procedure))))

;;; ---------------------------------------------------------------------------
;;; Planning from the archive
;;; ---------------------------------------------------------------------------

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
                     :operators-used (%operators-in-steps steps)
                     :meta (list :from-procedures
                                 (mapcar (lambda (plan)
                                           (getf (plan-meta plan) :from-procedure))
                                         pieces)
                                 :trace *current-trace*
                                 :context context-name
                                 :operators operators)))))

(defun %plan-from-partial-procedures (goals state operators context-name
                                      &optional used (initial state) pieces)
  "Combine procedures that achieve part of GOALS. Procedures whose goals
stay inside the request come first, then procedures that also achieve
something else; those extra goals are applied. A search restores a
remainder only after some procedure has already contributed.
INITIAL is the state the whole plan starts from, PIECES the plans replayed
so far and USED their procedures.
Returns a PLAN, or NIL when the pieces do not achieve GOALS."
  (let ((rest (%facts-still-missing goals state)))
    (unless rest
      (return-from %plan-from-partial-procedures
        (when pieces
          (%plan-from-pieces goals pieces state operators context-name
                             nil initial))))
    (dolist (procedure (append (%procedures-within-request goals rest)
                               (%procedures-overlapping-request goals rest)))
      (unless (member procedure used :test #'eq)
        (let ((plan (or (%plan-from-replay procedure state operators)
                        (%plan-without-blocked-extras procedure goals state
                                                      operators))))
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
      (multiple-value-bind (mea-state mea-steps)
          (%repair-by-search rest state operators)
        (when mea-state
          (%plan-from-pieces goals pieces mea-state operators context-name
                             mea-steps initial))))))

(defun plan-from-ranked-procedures (context goals operators)
  "Archived procedure for GOALS whose steps replay on CONTEXT, or NIL.
An empty GOALS asks for nothing, so no procedure is replayed.
An exact goal match is preferred. Otherwise a procedure whose goals include
GOALS is used, fewest extra goals first, and those extra goals are applied.
When no such procedure applies, procedures that each achieve part of GOALS
are combined: goals that stay inside the request first, then procedures
that also achieve something else. When those extra goals cannot be
restored, the steps that serve the request are kept and the others are
left aside. A search fills anything they leave.
The next procedure is tried when a higher-ranked one does not apply."
  (when goals
    (let ((facts (context-all-facts context))
          (context-name (context-name context)))
      (or (dolist (procedure (%procedures-for-planning goals))
            (let ((plan (or (%plan-from-replay procedure facts operators
                                               :context-name context-name)
                            (%plan-without-blocked-extras
                             procedure goals facts operators
                             :context-name context-name))))
              (when plan
                (return (%trace-replayed-plan plan procedure)))))
          (%plan-from-partial-procedures goals facts operators context-name)))))

(defun plan-consulting-archive (context &key goals operators (archive t))
  "Plan for CONTEXT. When ARCHIVE is true, try a scored procedure whose
goals include the request and whose steps still apply; an exact match
comes first. Otherwise combine procedures that each achieve part of the
request, those with no extra goals first. If those do not apply, or the
request has no fact-like goal, Means-Ends Analysis."
  (let* ((g (normalize-planning-goals (or goals (goals-of context))))
         (ops (or operators (context-planning-operators context)))
         (reused (and archive (plan-from-ranked-procedures context g ops))))
    (cond
      (reused
       ;; PLAN-FROM-CONTEXT records the external actions of a searched plan.
       ;; A replayed plan needs the same record. The adapter that keeps it is
       ;; optional, as in core/planner.lisp.
       (when (fboundp 'remember-plan-external-actions)
         (funcall 'remember-plan-external-actions reused
                  :context context
                  :operators ops))
       reused)
      (t
       (plan-from-context context :goals g :operators ops)))))
