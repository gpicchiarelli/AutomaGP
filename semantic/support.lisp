;;;; semantic/support.lisp — what "supported" means, and what proves it
;;;;
;;;; PROMPT-SEMANTICA §36: PARSED, REPRESENTED, VALIDATED,
;;;; SEMANTICALLY IMPLEMENTED, EXECUTABLE, CONFORMANT are six different
;;;; claims, and "we support OWL" is none of them until a level is named and
;;;; its evidence is on file. A level is claimed only on evidence for it and
;;;; for every level below it. Compiling is not evidence of anything.

(in-package #:automa-gp/semantic)

(defparameter *support-levels*
  '(:parsed :represented :validated :semantically-implemented
    :executable :conformant)
  "The levels of support, lowest first.
:PARSED the format can be read. :REPRESENTED a construct is kept without
loss. :VALIDATED a construct is checked by the rules of its standard.
:SEMANTICALLY-IMPLEMENTED the semantics the standard defines for it are
implemented. :EXECUTABLE that semantics runs in Common Lisp on SBCL.
:CONFORMANT the implementation passes the conformance tests of the standard.")

(defun support-level-p (object)
  "True when OBJECT is one of *SUPPORT-LEVELS*."
  (and (member object *support-levels* :test #'eq) t))

(defun support-level-rank (level)
  "1 for the lowest level up to the number of levels; 0 for NIL, which is
no support at all. Signals a TYPE-ERROR for anything else."
  (cond
    ((null level) 0)
    ((position level *support-levels* :test #'eq)
     (1+ (position level *support-levels* :test #'eq)))
    (t (error 'type-error :datum level
                          :expected-type `(or null (member ,@*support-levels*))))))

(defun support-level>= (level other)
  "True when LEVEL is at least as high as OTHER. NIL is below every level."
  (>= (support-level-rank level) (support-level-rank other)))

(defun lowest-support-level (levels)
  "The lowest of LEVELS, NIL when one of them is NIL, and NIL for none: a
set of constructs is only as supported as its weakest one, and a set with
nothing in it supports nothing."
  (if (or (null levels) (member nil levels))
      nil
      (first (sort (copy-list levels) #'< :key #'support-level-rank))))

(defun construct-status (level)
  "The answer PROMPT-SEMANTICA §2 asks for a construct at LEVEL:
:NOT-IMPLEMENTED with no support; :PARTIALLY-IMPLEMENTED while it can be
read, kept or checked and its semantics is not implemented yet;
:IMPLEMENTED from :SEMANTICALLY-IMPLEMENTED upward."
  (cond
    ((null level) :not-implemented)
    ((support-level>= level :semantically-implemented) :implemented)
    (t :partially-implemented)))

(defun conformance-verdict (passed failed unsupported)
  "PASS, FAIL or PARTIAL for a run of a conformance suite, or NONE for a run
that tested nothing. PASSED, FAILED and UNSUPPORTED count the tests that
passed, that failed, and that the implementation does not attempt. A run in
which nothing passed and nothing failed tested nothing, whatever it left out.
:PASS only when something passed and nothing failed or was left out."
  (check-type passed (integer 0))
  (check-type failed (integer 0))
  (check-type unsupported (integer 0))
  (cond
    ((and (zerop passed) (zerop failed)) :none)
    ((plusp failed) :fail)
    ((plusp unsupported) :partial)
    (t :pass)))

;;; ---------------------------------------------------------------------------
;;; Evidence
;;; ---------------------------------------------------------------------------

(defstruct (evidence (:constructor %make-evidence) (:predicate nil))
  "A record that backs a claim of support: which level, what kind of run,
what was run, how it came out, and where the report is."
  (level nil :type (member :parsed :represented :validated
                           :semantically-implemented :executable :conformant)
         :read-only t)
  (kind nil :type (member :test-run :build :conformance-report) :read-only t)
  (subject nil :read-only t)
  (passed 0 :type (integer 0) :read-only t)
  (failed 0 :type (integer 0) :read-only t)
  (unsupported 0 :type (integer 0) :read-only t)
  (reference nil :read-only t)
  (recorded-at nil :read-only t))

(defun evidence-p (object)
  "True if OBJECT is EVIDENCE."
  (typep object (quote evidence)))

(defun make-evidence (&key level kind subject (passed 0) (failed 0)
                        (unsupported 0) reference recorded-at)
  "EVIDENCE for LEVEL, of KIND :TEST-RUN, :BUILD or :CONFORMANCE-REPORT.
SUBJECT names what was run: a test suite, a system, an official suite.
PASSED, FAILED and UNSUPPORTED are the counts of that run. REFERENCE says
where the report is, RECORDED-AT when it was made (a universal time).
Which kind backs which level is EVIDENCE-ESTABLISHES-LEVEL-P's business."
  (%make-evidence :level level :kind kind :subject subject
                  :passed passed :failed failed :unsupported unsupported
                  :reference reference :recorded-at recorded-at))

(defun evidence-establishes-level-p (evidence)
  "True when EVIDENCE proves the level it names.
:PARSED to :SEMANTICALLY-IMPLEMENTED need a :TEST-RUN in which something
passed and nothing failed. :EXECUTABLE needs a :BUILD, the code loaded and
run on SBCL, that passed something and failed nothing. :CONFORMANT needs a
:CONFORMANCE-REPORT whose verdict is :PASS, of an official suite: a run in
which tests failed, or were left out, proves no conformance."
  (and (evidence-p evidence)
       (let ((passed (evidence-passed evidence))
             (failed (evidence-failed evidence))
             (unsupported (evidence-unsupported evidence)))
         (ecase (evidence-level evidence)
           ((:parsed :represented :validated :semantically-implemented)
            (and (eq :test-run (evidence-kind evidence))
                 (plusp passed) (zerop failed)))
           (:executable
            (and (eq :build (evidence-kind evidence))
                 (plusp passed) (zerop failed)))
           (:conformant
            (and (eq :conformance-report (evidence-kind evidence))
                 (eq :pass (conformance-verdict passed failed unsupported))))))))

(defun evidenced-level (evidence-list)
  "The highest level EVIDENCE-LIST proves, or NIL. A level counts only when
it and every level below it has evidence that establishes it: evidence for
:EXECUTABLE without evidence for :PARSED proves nothing."
  (let ((reached nil))
    (dolist (level *support-levels* reached)
      (if (some (lambda (evidence)
                  (and (eq level (evidence-level evidence))
                       (evidence-establishes-level-p evidence)))
                evidence-list)
          (setf reached level)
          (return reached)))))
