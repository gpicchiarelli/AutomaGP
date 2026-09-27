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
