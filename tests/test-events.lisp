;;;; tests/test-events.lisp — Phase 10 context-bound events

(in-package #:automa-gp/tests)

(def-suite events-suite :in automa-gp-suite)
(in-suite events-suite)

(test emit-records-pending-event-and-fact
  (gp-clear-memory)
  (gp-reset)
  (let ((ev (gp-emit '(automa-gp::file-created "document.pdf"))))
    (is-true (event-p ev))
    (is (eq :pending (event-status ev)))
    (is (eq 'automa-gp::file-created (event-type ev)))
    (is (equal '("document.pdf") (event-data ev)))
    (is (= 1 (length (gp-events))))
    (is-true (fact-p '(automa-gp::file-created "document.pdf") (gp-facts)))))

(test reaction-adds-facts-and-goals
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction
    :name 'automa-gp::on-file
    :when '(automa-gp::file-created ?path)
    :assert '((automa-gp::document-source ?path)
              (automa-gp::classification-target automa-gp::report))
    :goals '((automa-gp::document-classified ?path automa-gp::report))))
  (gp-emit '(automa-gp::file-created "brief.pdf"))
  (let ((summary (gp-react)))
    (is (= 1 (getf summary :processed)))
    (is (member 'automa-gp::on-file (getf summary :matched) :test #'equal))
    (is-true (fact-p '(automa-gp::document-source "brief.pdf") (gp-facts)))
    (is-true (fact-p '(automa-gp::classification-target automa-gp::report)
                     (gp-facts)))
    (is (find '(automa-gp::document-classified "brief.pdf" automa-gp::report)
              (gp-goals) :test #'equal))
    (is (eq :processed (event-status (first (gp-events)))))))

(test event-driven-plan-file-created-to-classify
  "PROMPT §16 example shape: file-created → reaction → goal → plan."
  (gp-clear-memory)
  (gp-reset)
  (gp-load-domain :documents :seed-demo t)
  (gp-emit '(automa-gp::file-created "document.pdf") :react t :plan t)
  (let ((plan (gp-last-plan))
        (summary (gp-last-reaction)))
    (is-true (plan-p plan))
    (is-true (plan-success plan))
    (is (getf summary :plan))
    (is (find '(automa-gp::document-classified "document.pdf" automa-gp::report)
              (gp-goals) :test #'equal))
    (let ((names (mapcar (lambda (s) (string (getf s :operator)))
                         (plan-steps plan))))
      (is (equal '("INGEST-DOCUMENT" "CLASSIFY-DOCUMENT") names)))))

(test goal-directed-and-event-driven-coexist
  (gp-clear-memory)
  (gp-reset)
  (gp-load-domain :hardware :seed-demo t)
  (let ((plan (gp-plan :goals '((automa-gp::device-configured
                                 automa-gp::interface-01)))))
    (is-true (plan-success plan)))
  (gp-add-reaction
   (make-event-reaction
    :name 'automa-gp::on-ping
    :when '(automa-gp::device-ping ?d)
    :assert '((automa-gp::ping-seen ?d))
    :goals '((automa-gp::connection ?d automa-gp::host))))
  (gp-emit '(automa-gp::device-ping automa-gp::interface-01) :react t)
  (is-true (fact-p '(automa-gp::ping-seen automa-gp::interface-01) (gp-facts)))
  (is (find '(automa-gp::connection automa-gp::interface-01 automa-gp::host)
            (gp-goals) :test #'equal))
  (is-true (plan-p (gp-last-plan)))
  (is (>= (length (gp-goals)) 1)))

(test unmatched-event-marked-ignored
  (gp-clear-memory)
  (gp-reset)
  (gp-emit '(automa-gp::unknown-signal 1))
  (gp-react)
  (is (eq :ignored (event-status (first (gp-events)))))
  (is (null (getf (gp-last-reaction) :matched))))

(test events-roundtrip-persistence
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction
    :name 'automa-gp::persist-me
    :when '(automa-gp::tick ?n)
    :goals '((automa-gp::ticked ?n))))
  (gp-emit '(automa-gp::tick 3))
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-evt-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (path (merge-pathnames "ctx.agp" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-save-context path)
           (gp-reset)
           (gp-load-context path)
           (is (= 1 (length (gp-events))))
           (is (= 1 (length (gp-reactions))))
           (gp-react)
           (is (find '(automa-gp::ticked 3) (gp-goals) :test #'equal)))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

;;; ---------------------------------------------------------------------------
;;; Event ids
;;; ---------------------------------------------------------------------------

(test a-restored-event-id-is-never-issued-again
  (loop for (id counter) in '((automa-gp::evt-7 7)
                              (:evt-9 9)
                              (evt-12 12)
                              ;; Behind the counter, or not an EVT-n id at all:
                              ;; nothing to move past.
                              (automa-gp::evt-2 5)
                              (automa-gp::evt-x1 5)
                              (automa-gp::evt- 5)
                              (tick 5)
                              ("EVT-40" 5)
                              (40 5))
        do (let* ((*event-counter* 5)
                  (restored (make-event :type 'tick :id id)))
             (is (equal id (event-id restored)))
             (is (= counter *event-counter*) "~S moved the counter to ~A"
                 id *event-counter*)
             (let ((next (make-event :type 'tick)))
               (is (= (1+ counter) *event-counter*))
               (is (string= (format nil "EVT-~D" (1+ counter))
                            (symbol-name (event-id next))))))))

(test event-ids-stay-unique-across-a-save-and-a-fresh-image
  (let* ((*event-counter* 0)
         (ctx (create-context :name 'log)))
    (emit-event! ctx '(tick 1))
    (emit-event! ctx '(tick 2))
    (let* ((saved (serialize-context ctx))
           ;; A fresh image starts counting from zero again.
           (*event-counter* 0)
           (restored (deserialize-context saved)))
      (emit-event! restored '(tick 3))
      (let ((ids (mapcar #'event-id (events-of restored))))
        (is (= 3 (length ids)))
        (is (= 3 (length (remove-duplicates ids))) "duplicate ids in ~S" ids)))))

;;; ---------------------------------------------------------------------------
;;; The event log
;;; ---------------------------------------------------------------------------

(defun three-status-log ()
  "A context whose log holds one event in each status, oldest first."
  (let ((ctx (create-context :name 'log)))
    (loop for status in '(:pending :processed :ignored)
          for n from 1
          do (setf (event-status (emit-event! ctx (list 'tick n))) status))
    ctx))

(test a-nil-status-means-every-event
  (loop for (status . kept) in '((nil :pending :processed :ignored)
                                 (:pending :pending)
                                 (:processed :processed)
                                 (:ignored :ignored))
        do (let* ((ctx (three-status-log))
                  (listed (events-of ctx :status status)))
             (is (equal kept (mapcar #'event-status listed))
                 "EVENTS-OF :STATUS ~S" status)
             ;; A fresh list: the caller may keep it or cut it.
             (is (not (eq listed (context-events ctx))))
             ;; CLEAR-EVENTS! removes exactly what EVENTS-OF lists.
             (is (equal (remove-if (lambda (left) (member left kept))
                                   '(:pending :processed :ignored))
                        (mapcar #'event-status
                                (clear-events! ctx :status status)))
                 "CLEAR-EVENTS! :STATUS ~S" status)))
  (is (null (clear-events! (three-status-log)))))

(test posting-an-event-object
  (let* ((ctx (create-context :name 'log))
         (event (make-event :type 'tick :data '(1)
                            :status :processed
                            :meta '(:from :elsewhere))))
    ;; Posted as it is: same object, pending again, meta kept.
    (is (eq event (emit-event! ctx event)))
    (is (eq :pending (event-status event)))
    (is (equal '(:from :elsewhere) (event-meta event)))
    (is (equal (list event) (context-events ctx)))
    (is (fact-p '(tick 1) (context-facts ctx)))
    ;; Posted twice, it would be reacted to twice.
    (setf (event-status event) :processed)
    (signals error (emit-event! ctx event :meta '(:again t)))
    (is (equal (list event) (context-events ctx)))
    (is (eq :processed (event-status event)))
    (is (equal '(:from :elsewhere) (event-meta event))))
  ;; META, when supplied, replaces the event's own; NIL is a value too.
  (loop for (supplied . meta) in '((nil :kept t) (t :new t) (t))
        do (let ((ctx (create-context :name 'log))
                 (event (make-event :type 'tick :meta '(:kept t))))
             (if supplied
                 (emit-event! ctx event :meta meta)
                 (emit-event! ctx event))
             (is (equal meta (event-meta event))))))

;;; ---------------------------------------------------------------------------
;;; What a reaction reports
;;; ---------------------------------------------------------------------------

(test a-reaction-reports-only-what-it-changed
  (let ((ctx (create-context :name 'desk
                             :facts '((seen 1))
                             :goals '((handled 1)))))
    (register-event-reaction!
     ctx
     (make-event-reaction :name 'on-tick
                          :when '(tick ?n)
                          :assert '((seen ?n) (fresh ?n) (loose ?n ?other))
                          :goals '((handled ?n) (filed ?n) (sent ?n ?where))))
    (let* ((event (emit-event! ctx '(tick 1) :assert-fact nil))
           (summary (react-to-event! ctx event)))
      (is (eq :processed (event-status event)))
      (is (equal '(on-tick) (getf summary :matched)))
      ;; (SEEN 1) and (HANDLED 1) were already there.
      (is (equal '((fresh 1)) (getf summary :facts-added)))
      (is (equal '((filed 1)) (getf summary :goals-added)))
      ;; A pattern :WHEN left open is not asserted, and is not hidden either.
      (is (equal '((loose 1 ?other) (sent 1 ?where)) (getf summary :dropped)))
      (is (equal '((seen 1) (fresh 1)) (context-facts ctx)))
      (is (equal '((handled 1) (filed 1)) (context-goals ctx))))))

(test the-summary-lists-reaction-facts-before-inferred-ones
  (let ((ctx (create-context :name 'desk))
        (*last-reaction* nil))
    (register-event-reaction!
     ctx (make-event-reaction :name 'on-tick
                              :when '(tick ?n)
                              :assert '((seen ?n) (loose ?n ?other))))
    (register-rule! ctx (make-rule :name 'seen-is-known
                                   :if '(seen ?n)
                                   :then '(known ?n)))
    (emit-event! ctx '(tick 1) :assert-fact nil)
    (emit-event! ctx '(tick 2) :assert-fact nil)
    (let ((summary (process-pending-events! ctx :infer t)))
      (is (eq summary *last-reaction*))
      (is (= 2 (getf summary :processed)))
      (is (equal '((seen 1) (seen 2) (known 1) (known 2))
                 (getf summary :facts-added)))
      (is (equal '((loose 1 ?other) (loose 2 ?other)) (getf summary :dropped)))
      (is (= 2 (length (getf summary :results))))
      (is (null (pending-events ctx))))))

(test reacting-plans-only-for-an-open-goal
  (flet ((react (facts)
           (let ((ctx (create-context :name 'desk
                                      :facts facts
                                      :goals '((power-state d1 on) label))))
             (register-operator!
              ctx (make-operator :name 'power-on
                                 :preconditions '((device ?d))
                                 :add-list '((power-state ?d on))))
             (emit-event! ctx '(tick 1))
             (values (process-pending-events! ctx :plan t) ctx))))
    (let* ((previous (make-instance 'plan :goals '((earlier)) :success t))
           (*current-plan* previous)
           (*last-reaction* nil))
      ;; Every fact-like goal already holds: the earlier plan and the mode
      ;; stay, as with GP-PLAN.
      (multiple-value-bind (summary ctx)
          (react '((device d1) (power-state d1 on)))
        (is (null (getf summary :plan)))
        (is (eq previous *current-plan*))
        (is (eq :read (context-mode ctx))))
      ;; An open goal is planned.
      (multiple-value-bind (summary ctx) (react '((device d1)))
        (is-true (plan-p (getf summary :plan)))
        (is (eq (getf summary :plan) *current-plan*))
        (is-true (plan-success *current-plan*))
        (is (equal '(power-on)
                   (mapcar (lambda (step) (getf step :operator))
                           (plan-steps *current-plan*))))
        (is (eq :plan (context-mode ctx)))))))
