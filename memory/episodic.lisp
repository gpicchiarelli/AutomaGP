;;;; memory/episodic.lisp — episodic memory (Phase 7)
;;;;
;;;; Past events, operations, and results (plans / simulations / executions).
;;;; Session buffer with a configurable limit — durable store is persistence.

(in-package #:automa-gp)

(defclass episode ()
  ((id
    :initarg :id
    :accessor episode-id
    :initform (gentemp "EP-"))
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
    :initform 256))
  (:documentation "Bounded store of past episodes."))

(defun episodic-memory-p (object)
  (typep object 'episodic-memory))

(defvar *episodic-memory* nil
  "Session episodic memory.")

(defparameter *episodic-memory-limit* 256
  "Default max episodes retained in session episodic memory.")

(defun make-episodic-memory (&key episodes (limit *episodic-memory-limit*))
  (make-instance 'episodic-memory
                 :episodes (copy-list episodes)
                 :limit limit))

(defun ensure-episodic-memory ()
  (unless (episodic-memory-p *episodic-memory*)
    (setf *episodic-memory*
          (make-episodic-memory :limit *episodic-memory-limit*)))
  *episodic-memory*)

(defun clear-episodic-memory ()
  (setf *episodic-memory* nil)
  t)

(defun %trim-episodes! (em)
  (let ((lim (episodic-memory-limit em)))
    (when (and lim (> (length (episodic-memory-episodes em)) lim))
      (setf (episodic-memory-episodes em)
            (subseq (episodic-memory-episodes em) 0 lim))))
  em)

(defun record-episode! (&key kind context-name summary success payload
                          (memory (ensure-episodic-memory)))
  "Push a new EPISODE onto MEMORY (newest first). Returns the episode."
  (let ((ep (make-instance 'episode
                           :kind kind
                           :context-name context-name
                           :summary summary
                           :success success
                           :payload (copy-tree payload)
                           :timestamp (get-universal-time))))
    (push ep (episodic-memory-episodes memory))
    (%trim-episodes! memory)
    ep))

(defun record-plan-episode! (plan &key (context-name nil)
                                    (memory (ensure-episodic-memory)))
  "Record a PLAN as an episode."
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
     :payload (list :goals (copy-list (plan-goals plan))
                    :steps (copy-tree (plan-steps plan))
                    :remaining (copy-list (plan-remaining plan))
                    :operators-used (copy-list (plan-operators-used plan)))
     :memory memory)))

(defun record-execution-episode! (result &key (memory (ensure-episodic-memory)))
  "Record an EXECUTION-RESULT as an episode."
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
                      :steps (copy-tree (execution-steps result))
                      :divergences (copy-tree (execution-divergences result))
                      :strategy-events (copy-tree (execution-strategy-events result)))
       :memory memory))))

(defun find-episodes (&key kind success context-name
                        (memory (ensure-episodic-memory)))
  "Filter episodes. Unsupplied keys are wildcards."
  (remove-if-not
   (lambda (ep)
     (and (or (null kind) (eq kind (episode-kind ep)))
          (or (null success) (eq success (episode-success ep)))
          (or (null context-name)
              (equal context-name (episode-context-name ep)))))
   (episodic-memory-episodes memory)))

(defun last-episode (&optional (memory (ensure-episodic-memory)))
  (first (episodic-memory-episodes memory)))
