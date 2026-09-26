;;;; tests/test-domains.lisp — Phase 9 domain packs

(in-package #:automa-gp/tests)

(def-suite domains-suite :in automa-gp-suite)
(in-suite domains-suite)

(defun %op-names (plan)
  (mapcar (lambda (s) (string (getf s :operator))) (plan-steps plan)))

(test software-domain-demo-plan
  (gp-clear-memory)
  (gp-reset)
  (let ((plan (automa-gp/domain/software:software-demo-plan
               (gp-context) :project 'demo-app)))
    (is-true (plan-success plan))
    (is (equal '("FETCH-REPOSITORY" "COMPILE-PROJECT" "RUN-PROJECT-TESTS")
               (%op-names plan)))
    (is (member :software (gp-domains)))))

(test documents-domain-pipeline-plan
  (gp-clear-memory)
  (gp-reset)
  (let ((plan (automa-gp/domain/documents:documents-demo-plan
               (gp-context) :source "brief.pdf" :class 'report)))
    (is-true (plan-success plan))
    (is (equal '("INGEST-DOCUMENT" "CLASSIFY-DOCUMENT" "ARCHIVE-DOCUMENT")
               (%op-names plan)))))

(test documents-archive-with-adapter-temp
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-doc-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "archived.txt" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-clear-memory)
           (gp-reset)
           (let* ((plan (automa-gp/domain/documents:documents-demo-plan
                         (gp-context)
                         :source "note.txt"
                         :archive-path (namestring marker)))
                  (*current-plan* plan)
                  (ex (gp-run :plan plan :adapters t :confirm t)))
             (is-true (plan-success plan))
             (is-true (execution-success ex))
             (is-true (file-exists-p marker))
             (is (equal "archived" (adapter-read-file-string marker)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test hardware-domain-demo-plan
  (gp-clear-memory)
  (gp-reset)
  (let ((plan (automa-gp/domain/hardware:hardware-demo-plan (gp-context))))
    (is-true (plan-success plan))
    (is (>= (plan-length plan) 3))
    (is (equal "POWER-ON-DEVICE" (first (%op-names plan))))))

(test music-domain-demo-plan
  (gp-clear-memory)
  (gp-reset)
  (let ((plan (automa-gp/domain/music:music-demo-plan (gp-context))))
    (is-true (plan-success plan))
    (is (equal '("POWER-AUDIO-INTERFACE" "ROUTE-MIDI" "OPEN-MUSIC-SESSION")
               (%op-names plan)))))

(test geometry-domain-triangle-plan
  (gp-clear-memory)
  (gp-reset)
  (let ((plan (automa-gp/domain/geometry:geometry-demo-plan (gp-context))))
    (is-true (plan-success plan))
    (is (find "CLOSE-TRIANGLE" (%op-names plan) :test #'string=))
    (is (>= (plan-length plan) 7))))

(test gp-load-domain-registry
  (gp-clear-memory)
  (gp-reset)
  (gp-load-domain :hardware :seed-demo t)
  (is (member :hardware (gp-domains)))
  ;; Goals must use #:automa-gp symbols (domain packs intern predicates there).
  (let ((plan (gp-plan :goals '((automa-gp::device-configured
                                 automa-gp::interface-01)))))
    (is-true (plan-success plan))))
