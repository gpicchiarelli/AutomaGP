;;;; tests/test-persistence.lisp — Phase 7 persistence service

(in-package #:automa-gp/tests)

(def-suite persistence-suite :in automa-gp-suite)
(in-suite persistence-suite)

(defun %persist-tmp (name)
  (uiop:merge-pathnames*
   (format nil "automa-gp-test-~A-~A.agp" name (get-universal-time))
   (uiop:temporary-directory)))

(test suspend-resume-context-roundtrip
  (let* ((ctx (create-context
               :name 'studio
               :facts '((device interface-01) (power-state interface-01 off))
               :goals '((connection interface-01 computer))
               :mode :plan))
         (_ (register-operator!
             ctx
             (make-operator :name 'power-on
                            :preconditions '((device ?d) (power-state ?d off))
                            :add-list '((power-state ?d on))
                            :delete-list '((power-state ?d off))))
             )
         (_r (register-rule!
              ctx
              (make-rule :name 'device-fact
                         :if '(device ?d)
                         :then '(tracked ?d))))
         (form (suspend-context ctx))
         (restored (resume-context form)))
    (declare (ignore _ _r))
    (is (eq :context (car form)))
    (is (context-p restored))
    (is (eq 'studio (context-name restored)))
    (is (fact-p '(device interface-01) (context-facts restored)))
    (is (= 1 (length (context-operators restored))))
    (is (= 1 (length (context-rules restored))))
    (is (eq :plan (context-mode restored)))))

(test persist-and-restore-context-file
  (let* ((path (%persist-tmp "ctx"))
         (ctx (create-context :name 'alpha
                              :facts '((ok true))
                              :goals '((done true)))))
    (unwind-protect
         (progn
           (persist-context ctx path)
           (let ((loaded (restore-context path)))
             (is (context-p loaded))
             (is (eq 'alpha (context-name loaded)))
             (is (fact-p '(ok true) (context-facts loaded)))
             (is (equal '((done true)) (context-goals loaded)))))
      (uiop:delete-file-if-exists path))))

(test snapshot-save-load-apply
  (gp-clear-memory)
  (gp-reset)
  (gp-context :name 'studio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (gp-add-operator
   (make-operator :name 'connect
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((connection ?d computer))))
  (gp-knowledge-add '(device spare-01))
  (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
    (gp-remember-procedure :plan plan :name 'connect-iface))
  (let ((path (%persist-tmp "snap")))
    (unwind-protect
         (progn
           (gp-save path)
           (gp-clear-memory)
           (gp-reset)
           (is (null (gp-facts)))
           (let ((bundle (gp-load path)))
             (is (context-p (getf bundle :context)))
             (is (eq 'studio (context-name (gp-context))))
             (is (fact-p '(device interface-01) (gp-facts)))
             (is (knowledge-memory-p (getf bundle :knowledge)))
             (is (fact-p '(device spare-01)
                         (knowledge-memory-facts (gp-knowledge))))
             (is (procedure-p (gp-find-procedure 'connect-iface)))
             (is (plusp (length (gp-episodes))))))
      (uiop:delete-file-if-exists path))))

(test persistence-separate-from-planner
  "Persistence helpers are callable without invoking the planner."
  (let* ((ctx (create-context :name 'x :facts '((a 1))))
         (path (%persist-tmp "sep")))
    (unwind-protect
         (progn
           (is (pathnamep (persist-context ctx path)))
           (is (context-p (restore-context path))))
      (uiop:delete-file-if-exists path))))
