;;;; tests/test-memory.lisp — Phase 7 multilevel memory & persistence

(in-package #:automa-gp/tests)

(def-suite memory-suite :in automa-gp-suite)
(in-suite memory-suite)

(defun %mem-studio ()
  (gp-clear-memory)
  (gp-reset)
  (gp-context :name 'studio-audio)
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
  (gp-context))

(test working-and-knowledge-memory
  (gp-clear-memory)
  (gp-reset)
  (gp-context :name 'lab)
  (gp-add-fact '(a 1))
  (gp-add-rule (make-rule :name 'r1 :if '((a ?x)) :then '(b ?x)))
  (let ((wm (gp-working)))
    (is (working-memory-p wm))
    (is (fact-p '(a 1) (working-memory-facts wm)))
    (is (eq 'lab (working-memory-context-name wm))))
  (gp-knowledge-add '(c 3))
  (gp-knowledge-add (make-rule :name 'kc :if '((c ?x)) :then '(d ?x)))
  (is (plusp (length (gp-knowledge-query '(c ?x)))))
  (setf *knowledge-memory* (knowledge-from-context (gp-context)))
  (gp-knowledge-merge)
  (is (fact-p '(a 1) (gp-facts))))

(test episodic-and-remember-procedure
  (%mem-studio)
  (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
    (is-true (plan-success plan))
    (is (plusp (length (gp-episodes :kind :plan))))
    (is (episode-p (gp-last-episode)))
    (let ((proc (gp-remember-procedure :name 'connect-interface)))
      (is (procedure-p proc))
      (is (eq 'connect-interface (procedure-name proc)))
      (is (= 2 (length (procedure-steps proc)))))
    (gp-simulate)
    (gp-run)
    (is (plusp (length (gp-episodes :kind :execute :success t))))
    (let* ((found (gp-find-procedure 'connect-interface))
           (reused (procedure->plan found)))
      (is (procedure-p found))
      (is (plan-p reused))
      (is (equal '(connection interface-01 computer)
                 (first (plan-goals reused))))
      (is (= 2 (plan-length reused)))))
  (gp-reset)
  (signals error (gp-remember-procedure))
  (%mem-studio)
  (let ((failed (gp-plan :goals '((ready interface-01)) :archive nil)))
    (is (not (plan-success failed)))
    (signals error (gp-remember-procedure :name 'nope))
    (is (null (gp-find-procedure 'nope)))))

(test persistence-snapshot-roundtrip
  (let* ((path (merge-pathnames
                (format nil "automa-gp-snap-~A.agp" (get-universal-time))
                (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (%mem-studio)
           (gp-add-rule (make-rule :name 'powered
                                   :if '((power-state ?d on))
                                   :then '(powered ?d)))
           (gp-plan :goals '((connection interface-01 computer)))
           (gp-remember-procedure :name 'connect-interface)
           (gp-knowledge-add '(studio ready))
           (gp-save path)
           (gp-clear-memory)
           (gp-reset)
           (is (null (gp-facts)))
           (is (null (gp-procedures)))
           (let ((bundle (gp-load path)))
             (is (consp bundle))
             (is (fact-p '(device interface-01) (gp-facts)))
             (is (gp-find-procedure 'connect-interface))
             (is (plusp (length (gp-episodes))))
             (is (plusp (length (gp-knowledge-query '(studio ?x)))))
             (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
               (is-true (plan-success plan)))))
      (ignore-errors (delete-file path)))))

(test persistence-isolated-from-planner
  "plan-for does not write snapshot files."
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames "automa-gp-plan-isolated/"
                                (uiop:temporary-directory))))
         (*default-snapshot-directory* dir))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (plan-for '((a 1)) '((a 1)) nil)
           (is (null (uiop:directory-files dir "*.agp"))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test context-only-persist
  (let ((path (merge-pathnames "automa-gp-ctx-only.agp"
                               (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (gp-reset)
           (gp-context :name 'solo)
           (gp-add-fact '(x 1))
           (gp-save-context path)
           (gp-reset)
           (gp-load-context path)
           (is (eq 'solo (context-name (gp-context))))
           (is (fact-p '(x 1) (gp-facts))))
      (ignore-errors (delete-file path)))))
