;;;; memory/episodic.lisp — episodic memory (Phase 7)
;;;;
;;;; Past events, operations, and results (plans / simulations / executions).
;;;; Session buffer with a configurable limit — durable store is persistence.

(in-package #:automa-gp)

(defvar *episode-counter* 0
  "The highest integer episode id made or restored in this Lisp image; a new
episode gets the next one.")

(defun %next-episode-id ()
  "A fresh episode id: the integer after *EPISODE-COUNTER*."
  (incf *episode-counter*))

(defclass episode ()
  ((id
    :initarg :id
    :accessor episode-id
    :initform (%next-episode-id)
    :documentation "An integer no episode made or restored earlier in this
image carries. An episode restored from a file keeps the id it was saved
with, which is a symbol in files written before ids were integers.")
   (kind
    :initarg :kind
    :accessor episode-kind
    :initform :event
    :documentation ":PLAN :SIMULATE :EXECUTE :EVENT or similar.")
   (context-name
    :initarg :context-name
    :accessor episode-context-name
    :initform nil)
   (summary
    :initarg :summary
    :accessor episode-summary
    :initform nil
    :documentation "Short symbolic description.")
   (success
    :initarg :success
    :accessor episode-success
    :initform nil)
   (payload
    :initarg :payload
    :accessor episode-payload
    :initform nil
    :documentation "Serializable plist of episode details.")
   (timestamp
    :initarg :timestamp
    :accessor episode-timestamp
    :initform (get-universal-time)))
  (:documentation "One remembered deliberative / operational episode."))

(defun episode-p (object)
  "True when OBJECT is an EPISODE."
  (typep object 'episode))

(defclass episodic-memory ()
  ((episodes
    :initarg :episodes
    :accessor episodic-memory-episodes
    :initform nil
    :documentation "Newest-first list of EPISODE objects.")
   (limit
    :initarg :limit
    :accessor episodic-memory-limit
    :initform 256
    :documentation "Most episodes kept, or NIL to keep them all."))
  (:documentation "Bounded store of past episodes."))

(defun episodic-memory-p (object)
  "True when OBJECT is an EPISODIC-MEMORY."
  (typep object 'episodic-memory))

(defvar *episodic-memory* nil
  "Session episodic memory.")

(defparameter *episodic-memory-limit* 256
  "Default max episodes retained in session episodic memory.")

(defun %trim-episodes! (em)
  "Drop the oldest episodes of EM beyond its limit. Returns EM."
  (let ((lim (episodic-memory-limit em)))
    (when (and lim (> (length (episodic-memory-episodes em)) lim))
      (setf (episodic-memory-episodes em)
            (subseq (episodic-memory-episodes em) 0 lim))))
  em)

(defun make-episodic-memory (&key episodes (limit *episodic-memory-limit*))
  "An EPISODIC-MEMORY of EPISODES (newest first), cut to its newest LIMIT.
LIMIT is a non-negative integer, or NIL to keep every episode."
  (check-type limit (or null (integer 0)))
  (%trim-episodes! (make-instance 'episodic-memory
                                  :episodes (copy-list episodes)
                                  :limit limit)))

(defun ensure-episodic-memory ()
  "Return *EPISODIC-MEMORY*, creating an empty one if needed."
  (unless (episodic-memory-p *episodic-memory*)
    (setf *episodic-memory*
          (make-episodic-memory :limit *episodic-memory-limit*)))
  *episodic-memory*)

(defun clear-episodic-memory ()
  "Drop the session episodic memory. Returns T."
  (setf *episodic-memory* nil)
  t)

(defun record-episode! (&key (kind :event) context-name summary success payload
                          (memory (ensure-episodic-memory)))
  "Push a new EPISODE onto MEMORY (newest first). Returns the episode.
SUMMARY and PAYLOAD are copied, so the episode shares no list with the caller."
  (let ((ep (make-instance 'episode
                           :kind kind
                           :context-name context-name
                           :summary (copy-tree summary)
                           :success success
                           :payload (copy-tree payload)
                           :timestamp (get-universal-time))))
    (push ep (episodic-memory-episodes memory))
    (%trim-episodes! memory)
    ep))

(defun record-plan-episode! (plan &key (context-name nil)
                                    (memory (ensure-episodic-memory)))
  "Record a PLAN as an episode. Returns it, or NIL when PLAN is not a plan."
  (when (plan-p plan)
    (record-episode!
     :kind :plan
     :context-name (or context-name
                       (getf (plan-meta plan) :context)
                       (and (deliberative-trace-p (trace-of plan))
                            (trace-context-name (trace-of plan))))
     :summary (list :goals (plan-goals plan)
                    :operators (plan-operators-used plan)
                    :length (plan-length plan))
     :success (plan-success plan)
     :payload (list :goals (plan-goals plan)
                    :steps (plan-steps plan)
                    :remaining (plan-remaining plan)
                    :operators-used (plan-operators-used plan))
     :memory memory)))

(defun record-execution-episode! (result &key (memory (ensure-episodic-memory)))
  "Record an EXECUTION-RESULT as an episode. Returns it, or NIL when RESULT
is not an execution result."
  (when (execution-result-p result)
    (let* ((plan (execution-plan result))
           (ctx (when (plan-p plan) (getf (plan-meta plan) :context))))
      (record-episode!
       :kind (execution-mode result)
       :context-name ctx
       :summary (list :mode (execution-mode result)
                      :steps (length (execution-steps result)))
       :success (execution-success result)
       :payload (list :mode (execution-mode result)
                      :steps (execution-steps result)
                      :divergences (execution-divergences result)
                      :strategy-events (execution-strategy-events result))
       :memory memory))))

(defun find-episodes (&key kind success context-name
                        (memory (ensure-episodic-memory)))
  "Episodes of MEMORY that pass every filter, newest first.
A filter left NIL selects everything. KIND and CONTEXT-NAME select the
episodes that carry that value. SUCCESS T selects the episodes that
succeeded and SUCCESS :FAILED those that did not."
  (remove-if-not
   (lambda (ep)
     (and (or (null kind) (eq kind (episode-kind ep)))
          (case success
            ((nil) t)
            (:failed (not (episode-success ep)))
            (t (episode-success ep)))
          (or (null context-name)
              (equal context-name (episode-context-name ep)))))
   (episodic-memory-episodes memory)))

(defun last-episode (&optional (memory (ensure-episodic-memory)))
  "The newest episode of MEMORY, or NIL when it holds none."
  (first (episodic-memory-episodes memory)))
