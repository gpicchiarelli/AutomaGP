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
  (%with-adapter-directory (dir)
    (let ((marker (merge-pathnames "archived.txt" dir)))
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
        (is (equal "archived" (adapter-read-file-string marker)))))))

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

;;; ---------------------------------------------------------------------------
;;; What every pack has in common
;;; ---------------------------------------------------------------------------

(defun %pack-census (context)
  "What a pack left in CONTEXT itself: how many operators, rules, actions
and reactions, and the local facts."
  (list (length (context-operators context))
        (length (context-rules context))
        (length (context-actions context))
        (length (context-event-reactions context))
        (context-facts context)))

(test every-pack-installs-the-same-parts-however-often
  "Installing a pack again replaces its parts and adds nothing: the same
operators, rules, actions, reactions and seed facts, and one tag. A pack
is not installed into something that is not a context."
  (loop for (name . installer) in *known-domains*
        do (let ((ctx (create-context :name name)))
             (is (eq ctx (funcall installer ctx :seed-demo t)))
             (let ((census (%pack-census ctx)))
               (is (plusp (first census)) "~S installs no operator" name)
               (is-true (fifth census) "~S seeds no fact" name)
               (funcall installer ctx :seed-demo t)
               (is (equal census (%pack-census ctx))
                   "~S installed twice differs: ~S" name (%pack-census ctx)))
             (is (equal (list name) (getf (context-meta ctx) :domains)))
             (signals type-error (funcall installer name)))))

(test a-pack-does-not-copy-a-seed-fact-its-context-inherits
  "A seed fact the context already sees through its parent is not asserted
a second time in the child."
  (loop for (name . installer) in *known-domains*
        do (let* ((parent (create-context :name 'parent))
                  (child (create-context :name 'child :parent parent)))
             (funcall installer parent :seed-demo t)
             (funcall installer child :seed-demo t)
             (is (null (context-facts child))
                 "~S copied ~S into the child" name (context-facts child))
             (is (equal (context-facts parent) (context-all-facts child))))))

(test install-domain-pack-installs-a-pack-of-ones-own
  "The function the five packs are installed through takes any pack."
  (let ((ctx (create-context :name 'kitchen)))
    (flet ((install ()
             (install-domain-pack
              ctx :kitchen
              :operators (list (make-operator :name 'boil
                                              :preconditions '((kettle full))
                                              :add-list '((water hot))))
              :rules (list (make-rule :name 'tea-time
                                      :if '((water hot))
                                      :then '(tea possible)))
              :actions (list (make-action :name 'boil
                                          :preconditions '((kettle full))
                                          :effects '((water hot))))
              :event-reactions (list (make-event-reaction
                                      :name 'on-thirst
                                      :when '(thirsty ?who)
                                      :goals '((water hot))))
              :facts '((kettle full)))))
      (is (eq ctx (install)))
      (let ((census (%pack-census ctx)))
        (is (equal '(1 1 1 1 ((kettle full))) census))
        (install)
        (is (equal census (%pack-census ctx))))
      (is (equal '(:kitchen) (getf (context-meta ctx) :domains)))
      (is-true (plan-success (plan-from-context ctx :goals '((water hot)))))
      ;; A second pack adds its tag beside the first.
      (install-domain-pack ctx :pantry :facts '((tea-leaves present)))
      (is (equal '(:kitchen :pantry)
                 (sort (copy-list (getf (context-meta ctx) :domains))
                       #'string<)))
      (is (fact-p '(tea-leaves present) (context-facts ctx))))
    (signals type-error (install-domain-pack :kitchen :kitchen))))

;;; ---------------------------------------------------------------------------
;;; Software: actions and operators say the same thing
;;; ---------------------------------------------------------------------------

(test software-actions-say-what-the-operators-say
  "Each action of the software pack has the preconditions and effects of
the operator of the same name, and names an adapter only when that
operator carries an :EXTERNAL spec."
  (let ((ctx (create-context :name 'software)))
    (automa-gp/domain/software:install-software-domain ctx)
    (is (= 3 (length (actions-of ctx))))
    (dolist (action (actions-of ctx))
      (let ((operator (find-operator ctx (action-name action))))
        (is-true operator "no operator named ~S" (action-name action))
        (when operator
          (is (equal (operator-preconditions operator)
                     (action-preconditions action)))
          (is (equal (operator-add-list operator) (action-effects action)))
          (is (eq (getf (operator-external-spec operator) :adapter)
                  (action-adapter action))))))
    (is (equal '(:processes)
               (remove nil (mapcar #'action-adapter (actions-of ctx)))))))

;;; ---------------------------------------------------------------------------
;;; Documents: a real file write is confirmed
;;; ---------------------------------------------------------------------------

(test archive-document-with-a-path-asks-before-it-replaces-a-file
  "Without a path ARCHIVE-DOCUMENT only changes facts and runs unasked.
With a path it replaces a file: it is irreversible, the plan lists it as
risky, and a live run without confirmation stops before the file changes."
  (%with-adapter-directory (dir)
    (let ((marker (merge-pathnames "archived.txt" dir))
          (archived '(automa-gp::document-archived "note.txt")))
      (adapter-write-file-string marker "kept")
      ;; The path-less case comes first: it must leave the file alone.
      (loop for path in (list nil (namestring marker))
            do (let* ((ctx (create-context :name 'documents))
                      (plan (automa-gp/domain/documents:documents-demo-plan
                             ctx :source "note.txt" :archive-path path))
                      (operator (find-operator
                                 ctx 'automa-gp::archive-document)))
                 (is-true (plan-success plan))
                 (is (eq (not path) (operator-reversible operator)))
                 (is (eq (if path :medium :low) (operator-risk operator)))
                 (is (equal (when path '(automa-gp::archive-document))
                            (mapcar (lambda (risky) (getf risky :name))
                                    (plan-risky-operators plan ctx))))
                 (cond
                   (path
                    ;; Unconfirmed, the step is given up; asked to signal,
                    ;; the run signals the typed condition. Neither writes.
                    (let ((result (execute-plan! ctx plan :adapters t)))
                      (is-false (execution-success result))
                      (is (eq :aborted
                              (getf (first (last (execution-steps result)))
                                    :status))))
                    (let ((*plan-runner-default-abort* nil))
                      (signals confirmation-required
                        (execute-plan! ctx plan :adapters t)))
                    (is (not (fact-p archived (context-all-facts ctx))))
                    (is (equal "kept" (adapter-read-file-string marker)))
                    ;; Confirmed, the file is replaced.
                    (is-true (execution-success
                              (execute-plan! ctx plan
                                             :adapters t :confirm t)))
                    (is (fact-p archived (context-all-facts ctx)))
                    (is (equal "archived" (adapter-read-file-string marker))))
                   (t
                    (is-true (execution-success
                              (execute-plan! ctx plan :adapters t)))
                    (is (fact-p archived (context-all-facts ctx)))
                    (is (equal "kept" (adapter-read-file-string marker))))))))))

;;; ---------------------------------------------------------------------------
;;; The registry
;;; ---------------------------------------------------------------------------

(test gp-load-domain-installs-into-the-context-it-is-given
  "An explicit :CONTEXT receives the pack; the session and its
working-memory snapshot stay as they were. Without :CONTEXT the session
receives the pack and the snapshot follows."
  (gp-clear-memory)
  (gp-reset)
  (let ((other (create-context :name 'elsewhere))
        (session (gp-context))
        (snapshot *working-memory*))
    (is (eq other (gp-load-domain :music :context other)))
    (is (equal '(:music) (getf (context-meta other) :domains)))
    (is-true (find-operator other 'automa-gp::route-midi))
    (is (null (gp-domains)))
    (is (null (find-operator session 'automa-gp::route-midi)))
    (is (eq snapshot *working-memory*))
    (is (eq session (gp-load-domain :music)))
    (is (equal '(:music) (gp-domains)))
    (is (not (eq snapshot *working-memory*)))
    (is (eq (context-name session)
            (working-memory-context-name *working-memory*))))
  (signals error (gp-load-domain :astrology)))
