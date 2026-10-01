;;;; tests/test-explanation.lisp — Phase 6 deliberative trace & gp-explain

(in-package #:automa-gp/tests)

(def-suite explanation-suite :in automa-gp-suite)
(in-suite explanation-suite)

(defun %studio-ops ()
  (list (make-operator :name 'power-on
                       :preconditions '((device ?d) (power-state ?d off))
                       :add-list '((power-state ?d on))
                       :delete-list '((power-state ?d off)))
        (make-operator :name 'connect
                       :preconditions '((device ?d) (power-state ?d on))
                       :add-list '((connection ?d computer)))))

(test plan-attaches-real-trace
  (clear-trace-session)
  (let* ((facts '((device interface-01) (power-state interface-01 off)))
         (goals '((connection interface-01 computer)))
         (plan (plan-for facts goals (%studio-ops) :context-name 'studio-audio))
         (tr (trace-of plan)))
    (is-true (plan-success plan))
    (is (deliberative-trace-p tr))
    (is (eq :plan (trace-phase tr)))
    (is (eq 'studio-audio (trace-context-name tr)))
    (is (null (find-trace-entries :goal tr))) ; goals recorded as :goals
    (is (plusp (length (find-trace-entries :goals tr))))
    (is (plusp (length (find-trace-entries :difference tr))))
    (is (plusp (length (find-trace-entries :selected-operator tr))))
    (is (plusp (length (find-trace-entries :action tr))))
    (is (plusp (length (find-trace-entries :result tr))))
    (is (plusp (length (find-trace-entries :plan-complete tr))))
    (let ((text (format-explanation tr)))
      (is (search "STUDIO-AUDIO" text))
      (is (search "Selected operator" text))
      (is (search "POWER-ON" text))
      (is (search "CONNECT" text))
      (is (search "Difference" text))
      (is (search "Result" text)))))

(test explain-does-not-invent-without-trace
  (clear-trace-session)
  (multiple-value-bind (text tr) (explain-trace :last)
    (is (null tr))
    (is (search "No deliberative trace" text))))

(test simulate-and-execute-record-traces
  (clear-trace-session)
  (let ((ctx (create-context
              :name 'studio-audio
              :facts '((device interface-01) (power-state interface-01 off)))))
    (dolist (op (%studio-ops)) (register-operator! ctx op))
    (let* ((plan (plan-from-context
                  ctx :goals '((connection interface-01 computer))))
           (sim (simulate-plan plan :context ctx))
           (sim-tr (trace-of sim))
           (run (execute-plan! ctx plan :confirm t))
           (run-tr (trace-of run)))
      (is (deliberative-trace-p sim-tr))
      (is (eq :simulate (trace-phase sim-tr)))
      (is (plusp (length (find-trace-entries :execution-step sim-tr))))
      (is (deliberative-trace-p run-tr))
      (is (eq :execute (trace-phase run-tr)))
      (is (plusp (length (find-trace-entries :action run-tr))))
      (is (eq run-tr (last-trace)))
      (is (>= (length *trace-history*) 2)))))

(test gp-explain-from-plan-and-last
  (gp-reset)
  (gp-context :name 'studio-audio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (dolist (op (%studio-ops)) (gp-add-operator op))
  (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
    (is (deliberative-trace-p (trace-of plan)))
    (multiple-value-bind (text tr)
        (let ((*standard-output* (make-broadcast-stream)))
          (gp-explain :plan nil))
      (declare (ignore text))
      (is (eq tr (trace-of plan))))
    (gp-simulate)
    (multiple-value-bind (text tr)
        (gp-explain :execution nil)
      (is (deliberative-trace-p tr))
      (is (or (search "Execution" text)
              (search "execution" text)
              (search "SIMULATE" text)))
      (is (eq tr (trace-of (gp-last-execution)))))
    (is (deliberative-trace-p (gp-last-trace)))
    (is (consp (gp-trace-history)))))

(test with-trace-finalizes-chronological
  (clear-trace-session)
  (let ((tr
         (with-trace (:plan :context-name 'x)
           (trace-record :goal :goal '(a 1))
           (trace-record :result :status :ok)
           *current-trace*)))
    (is (not (trace-open-p tr)))
    (is (eq :begin (getf (first (trace-entries tr)) :kind)))
    (is (eq :goal (getf (second (trace-entries tr)) :kind)))
    (is (eq :result (getf (third (trace-entries tr)) :kind)))
    (is (eq tr (last-trace)))))

;;; ---------------------------------------------------------------------------
;;; Fixtures (also used by tests/test-narration.lisp, which loads after this)
;;; ---------------------------------------------------------------------------

(defun %recorded-trace (&rest entries)
  "A finished trace holding ENTRIES after its :BEGIN entry.
Each entry is (KIND . PLIST), recorded with TRACE-RECORD."
  (with-trace (:plan)
    (dolist (entry entries)
      (apply #'trace-record entry))
    *current-trace*))

(defun %studio-plan ()
  (plan-for '((device interface-01) (power-state interface-01 off))
            '((connection interface-01 computer))
            (%studio-ops)
            :context-name 'studio-audio))

(defun %occurrences (needle text)
  "How many times NEEDLE occurs in TEXT."
  (loop for start = (search needle text)
          then (search needle text :start2 (1+ start))
        while start
        count t))

(defparameter *sample-entries*
  '((:context :name garage)
    (:goal :goal (a 1))
    (:goals :goals ((a 1) (b 2)))
    (:goals :goals nil)
    (:state :facts ((a 1)))
    (:state :facts nil)
    (:difference :goal (a 1) :depth 0)
    (:differences :goals ((a 1) (b 2)))
    (:goal-already-satisfied :goal (a 1) :operator op)
    (:projected-effects :operator op :goal (a 1))
    (:recorded-effects :operator op :goal (a 1))
    (:missing-precondition :operator op :goals ((a 1)) :from-procedure fill)
    (:repair-step :operator op :goal (a 1))
    (:step-set-aside :operator op :goal (a 1))
    (:selected-operator :operator op :goal (a 1) :bindings ((?x . 1)))
    (:subgoal :goal (a 1) :for-operator op)
    (:precondition :goal (a 1) :status :satisfied :operator op)
    (:action :operator op :bindings ((?x . 1)) :goal (a 1))
    (:result :status :no-operator :goal (a 1))
    (:result :status :ok)
    (:operator-failed :operator op :reason :preconditions-unmet :missing ((a 1)))
    (:execution-step :mode :simulate :operator op :status :ok :flag nil)
    (:reused-procedure :name fill :score 0.5)
    (:plan-complete :success t :steps 1 :remaining nil)
    (:plan-complete :success nil :steps 0 :remaining ((a 1)))
    (:execution-complete :mode :execute :success t)
    (:event :action :emit :type file-created :data ("a.pdf") :id evt-1)
    (:event :action :react :type file-created :id evt-1
     :matched (on-file) :facts ((source "a.pdf")) :goals ((filed "a.pdf")))
    (:event :action :react :type file-created :id evt-1
     :matched nil :facts nil :goals nil)
    (:event :action :archived :type file-created)
    (:custom-note :about (a 1)))
  "One entry of every kind the core records, plus kinds no renderer knows.")

;;; ---------------------------------------------------------------------------
;;; Recording and publication
;;; ---------------------------------------------------------------------------

(test trace-ids-are-uninterned-and-distinct
  "An id interned in the current package would leak one symbol per trace."
  (dolist (name '(:cl-user :keyword :automa-gp))
    (let* ((*package* (find-package name))
           (one (trace-id (make-trace :phase :plan)))
           (other (trace-id (make-trace :phase :plan))))
      (is (null (symbol-package one)) "id interned in ~A" name)
      (is (null (find-symbol (symbol-name one) *package*)))
      (is (string/= (symbol-name one) (symbol-name other))))))

(test disabled-tracing-records-and-publishes-nothing
  (clear-trace-session)
  (let ((earlier (with-trace (:plan) *current-trace*)))
    (let ((*trace-enabled* nil))
      (is (null (with-trace (:plan :context-name 'x)
                  (trace-record :goal :goal '(a 1))
                  *current-trace*)))
      (let ((plan (%studio-plan)))
        (is-true (plan-success plan))
        (is (null (trace-of plan)))
        (let ((*current-plan* plan))
          (is (null (resolve-explain-topic :plan))
              "a plan without a trace was explained by an unrelated trace"))))
    (is (eq earlier (last-trace)))
    (is (equal (list earlier) *trace-history*))))

(test finalize-trace-publishes-once
  (clear-trace-session)
  (let ((tr (with-trace (:plan) *current-trace*)))
    (is (eq tr (finalize-trace tr)))
    (is (equal (list tr) *trace-history*)))
  (clear-trace-session)
  (let ((tr (with-trace (:plan)
              (trace-record :goal :goal '(a 1))
              (finalize-trace))))
    (is (not (trace-open-p tr)))
    (is (equal (list tr) *trace-history*))
    (is (equal '(:begin :goal)
               (mapcar (lambda (entry) (getf entry :kind)) (trace-entries tr))))))

(test finalizing-leaves-an-earlier-reading-intact
  "The entries a caller read from an open trace are not reordered under it."
  (let ((reading nil))
    (with-trace (:plan)
      (trace-record :goal :goal '(a 1))
      (setf reading (trace-entries *current-trace*)))
    (is (equal '(:goal :begin)
               (mapcar (lambda (entry) (getf entry :kind)) reading)))))

(test with-trace-evaluates-its-arguments-once
  (let ((phases 0)
        (names 0))
    (with-trace ((progn (incf phases) :plan)
                 :context-name (progn (incf names) 'ctx))
      nil)
    (is (= 1 phases))
    (is (= 1 names))))

(test with-trace-returns-values-and-finalizes-on-unwind
  (clear-trace-session)
  (is (equal '(1 2) (multiple-value-list (with-trace (:plan) (values 1 2)))))
  (let ((tr nil))
    (catch 'out
      (with-trace (:plan)
        (setf tr *current-trace*)
        (throw 'out nil)))
    (is (not (trace-open-p tr)))
    (is (eq tr (last-trace)))
    (is (null *current-trace*))))

(test trace-history-keeps-the-newest-within-the-limit
  (clear-trace-session)
  (let* ((*trace-history-limit* 2)
         (traces (loop repeat 3 collect (with-trace (:plan) *current-trace*))))
    (is (equal (reverse (rest traces)) *trace-history*))
    (is (eq (third traces) (last-trace)))))

(test unusable-history-limit-keeps-no-history
  "A bad limit must not signal from WITH-TRACE's cleanup."
  (dolist (limit '(-1 0 nil 2.5 :many))
    (clear-trace-session)
    (let ((*trace-history-limit* limit)
          (tr nil))
      (finishes (setf tr (with-trace (:plan) *current-trace*)))
      (is (and tr (eq tr (last-trace))) "limit ~S" limit)
      (is (null *trace-history*) "limit ~S" limit))))

;;; ---------------------------------------------------------------------------
;;; Rendering
;;; ---------------------------------------------------------------------------

(test rendered-text-ignores-package-and-printer-settings
  "A truncated or package-qualified explanation would hide or distort the record."
  (let* ((tr (trace-of (%studio-plan)))
         (explanation (with-standard-io-syntax (format-explanation tr)))
         (narration (with-standard-io-syntax (narrate-trace tr))))
    (is (search "(CONNECTION INTERFACE-01 COMPUTER)" explanation))
    (is (not (search "::" explanation)))
    (loop for (variable value) in `((*package* ,(find-package :cl-user))
                                    (*package* ,(find-package :keyword))
                                    (*print-length* 1)
                                    (*print-level* 1)
                                    (*print-case* :downcase)
                                    (*print-pretty* t)
                                    (*print-base* 2)
                                    (*print-radix* t))
          do (multiple-value-bind (explained narrated)
                 (progv (list variable) (list value)
                   (values (format-explanation tr)
                           (nth-value 0 (narrate-trace tr))))
               (is (string= explanation explained)
                   "explanation changes with ~S = ~S" variable value)
               (is (string= narration narrated)
                   "narration changes with ~S = ~S" variable value)))))

(test explanation-keeps-the-detail-of-a-term
  (let ((text (format-explanation
               (%recorded-trace
                '(:goals :goals ((path "a b" :mode (1 . 2)) (flag . on)))))))
    (is (search "(PATH \"a b\" :MODE (1 . 2))" text))
    (is (search "(FLAG . ON)" text))))

(test every-recorded-entry-is-explained-and-narrated
  "Neither renderer may drop a recorded entry or dump its raw plist."
  (dolist (entry *sample-entries*)
    (let* ((tr (%recorded-trace entry))
           (text (format-explanation tr))
           (nodes (nth-value 1 (narrate-trace tr))))
      ;; The header and the :BEGIN entry end one block; ENTRY adds its own.
      (is (= 2 (%occurrences (format nil "~%~%") text))
          "~S is not one block:~%~A" entry text)
      (is (not (search ":KIND" text)) "~S is dumped raw" entry)
      (is (not (search ":TIME" text)) "~S is dumped raw" entry)
      (is (= 2 (length nodes)) "~S is not narrated" entry))))

(test unknown-entry-kinds-are-shown-as-recorded
  (let ((tr (%recorded-trace '(:custom-note :about (a 1)))))
    (is (search (format nil "CUSTOM-NOTE:~%    (:ABOUT (A 1))")
                (format-explanation tr)))
    (is (search "CUSTOM-NOTE" (narrate-trace tr)))))

(test failed-plan-explanation-names-what-failed
  (let* ((plan (plan-for '((p 1)) '((q 1) (r 2)) nil))
         (text (format-explanation (trace-of plan))))
    (is-false (plan-success plan))
    (is (search "NO-OPERATOR for (Q 1)" text))
    (is (search "remaining (Q 1)" text))
    (is (search "remaining (R 2)" text))))

(test operator-failure-is-explained-with-its-reason
  (let ((text (format-explanation
               (%recorded-trace
                '(:operator-failed :operator op :reason :preconditions-unmet
                  :missing ((q 1) (r 2)))
                '(:operator-failed :operator bare)))))
    (is (search (format nil "~{~A~%~}" '("    OP (PRECONDITIONS-UNMET)"
                                          "    missing (Q 1)"
                                          "    missing (R 2)"))
                text))
    (is (search (format nil "Operator failed:~%    BARE~%") text))))

(test context-is-explained-once
  (let ((text (format-explanation (trace-of (%studio-plan)))))
    (is (= 1 (%occurrences "Context:" text)))
    (is (search "STUDIO-AUDIO" text)))
  (let ((text (format-explanation
               (with-trace (:plan :context-name 'studio-audio)
                 (trace-record :context :name 'studio-audio)
                 (trace-record :context :name 'garage)
                 *current-trace*))))
    (is (= 2 (%occurrences "Context:" text)))
    (is (search "GARAGE" text))))

(test events-are-explained-from-the-record
  (let* ((ctx (create-context :name 'inbox))
         (reaction (make-event-reaction
                    :name 'on-file
                    :when '(file-created ?path)
                    :assert '((document-source ?path))
                    :goals '((document-filed ?path))))
         (tr (with-trace (:react :context-name 'inbox)
               (let ((hit (emit-event! ctx '(file-created "brief.pdf")))
                     (miss (emit-event! ctx '(disk-full))))
                 (react-to-event! ctx hit :reactions (list reaction))
                 (react-to-event! ctx miss :reactions (list reaction)))
               *current-trace*))
         (text (format-explanation tr)))
    (is (= 2 (%occurrences "Event emitted:" text)))
    (is (search "(FILE-CREATED \"brief.pdf\")" text))
    (is (search "matched ON-FILE" text))
    (is (search "asserted (DOCUMENT-SOURCE \"brief.pdf\")" text))
    (is (search "goal (DOCUMENT-FILED \"brief.pdf\")" text))
    (is (search "no reaction matched" text))))

(test copied-empty-bindings-print-nothing
  (let ((text (format-explanation
               (%recorded-trace
                (list :action :operator 'plain :bindings *no-bindings*)
                (list :action :operator 'copied
                      :bindings (copy-tree *no-bindings*))
                '(:action :operator bound :bindings ((?d . unit) (?p . "a b")))))))
    (is (search (format nil "PLAIN~%") text))
    (is (search (format nil "COPIED~%") text))
    (is (not (search "T=T" text)))
    (is (search "BOUND ?D=UNIT ?P=\"a b\"" text))))

(test open-trace-is-explained-in-chronological-order
  "A trace inspected while it records (from the debugger) reads oldest first."
  (with-trace (:plan)
    (trace-record :goal :goal '(a 1))
    (trace-record :result :status :ok)
    (let ((text (format-explanation *current-trace*)))
      (is (< (search "Begin" text) (search "Goal:" text) (search "Result:" text))))
    (is (search "Inizio"
                (getf (first (nth-value 1 (narrate-trace *current-trace*))) :text)))
    (is (trace-open-p *current-trace*))))

(test explanation-follows-the-format-stream-convention
  (let* ((tr (%recorded-trace '(:goal :goal (a 1))))
         (text (format-explanation tr)))
    (is (search "Goal:" text))
    (dolist (render (list (lambda (stream) (format-explanation tr stream))
                          (lambda (stream) (explain-trace tr :stream stream))))
      (let (returned)
        (is (string= text (with-output-to-string (stream)
                            (setf returned (funcall render stream)))))
        (is (null returned))))
    (is (string= text (with-output-to-string (*standard-output*)
                        (format-explanation tr t))))
    (multiple-value-bind (returned trace) (explain-trace tr)
      (is (string= text returned))
      (is (eq tr trace)))))

(test explain-topics-resolve-to-their-own-trace
  (clear-trace-session)
  (let* ((plan (%studio-plan))
         (later (with-trace (:simulate) *current-trace*)))
    (is (eq later (resolve-explain-topic :last)))
    (is (eq later (resolve-explain-topic nil)))
    (is (eq later (resolve-explain-topic :history)))
    (is (eq (trace-of plan) (resolve-explain-topic plan)))
    (is (eq later (resolve-explain-topic later)))
    (is (null (resolve-explain-topic 'no-such-topic)))
    (let ((*current-plan* nil)
          (*last-execution* nil))
      (is (eq later (resolve-explain-topic :plan)))
      (is (eq later (resolve-explain-topic :execution))))
    (let ((*current-plan* plan))
      (is (eq (trace-of plan) (resolve-explain-topic :plan))))))
