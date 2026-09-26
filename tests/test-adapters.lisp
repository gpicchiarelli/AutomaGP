;;;; tests/test-adapters.lisp — Phase 8 OS adapters (temp dirs only)

(in-package #:automa-gp/tests)

(def-suite adapters-suite :in automa-gp-suite)
(in-suite adapters-suite)

(test filesystem-primitives-temp
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-fs-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (file (merge-pathnames "marker.txt" dir)))
    (unwind-protect
         (progn
           (adapter-ensure-directory dir)
           (is-false (file-exists-p file))
           (adapter-write-file-string file "hello-gp")
           (is-true (file-exists-p file))
           (is (equal "hello-gp" (adapter-read-file-string file)))
           (is (plusp (length (directory-files dir "*.txt"))))
           (is-true (adapter-delete-file file))
           (is-false (file-exists-p file)))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test process-run-and-running-p
  (multiple-value-bind (out code)
      (run-program '("echo" "automa-gp") :output :string)
    (is (eql 0 code))
    (is (search "automa-gp" out)))
  ;; Current image PID must be running (kill -0).
  (is-true (process-running-p
            #+sbcl (sb-posix:getpid)
            #-sbcl (parse-integer
                    (string-trim '(#\Space #\Newline #\Return)
                                 (nth-value 0
                                  (run-program '("sh" "-c" "echo $$")
                                               :output :string))))))
  (is-false (process-running-p "automa-gp-no-such-process-xyzzy")))

(test macos-dispatch-safe
  (let ((r (macos-dispatch :macos-p nil)))
    (is (getf r :ok))
    (is (eq (macos-p) (getf r :macos))))
  (let ((r (macos-dispatch :uname nil)))
    (is (getf r :ok))
    (is (stringp (getf r :uname)))))

(test simulate-never-invokes-adapters
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames "automa-gp-sim-adapt/"
                                (uiop:temporary-directory))))
         (file (merge-pathnames "should-not-exist.txt" dir))
         (*invoke-adapters* t))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-clear-memory)
           (gp-reset)
           (gp-add-fact '(path-ready marker))
           (gp-add-operator
            (make-operator
             :name 'write-marker
             :preconditions '((path-ready ?name))
             :add-list '((file-created ?name))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path file
                                           :content "from-sim")))))
           (gp-plan :goals '((file-created marker)))
           (gp-simulate)
           (is-false (file-exists-p file))
           (is (fact-p '(path-ready marker) (gp-facts))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test execute-with-adapters-writes-temp-file
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-run-adapt-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (file (merge-pathnames "created.txt" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-clear-memory)
           (gp-reset)
           (gp-adapters nil)
           (gp-add-fact '(path-ready marker))
           (gp-add-operator
            (make-operator
             :name 'write-marker
             :preconditions '((path-ready ?name))
             :add-list '((file-created ?name))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path file
                                           :content "from-execute")))))
           (gp-plan :goals '((file-created marker)))
           ;; adapters off → symbolic only
           (gp-run :adapters nil)
           (is-false (file-exists-p file))
           (is (fact-p '(file-created marker) (gp-facts)))
           ;; reset facts and run with adapters
           (gp-reset)
           (gp-add-fact '(path-ready marker))
           (gp-add-operator
            (make-operator
             :name 'write-marker
             :preconditions '((path-ready ?name))
             :add-list '((file-created ?name))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path file
                                           :content "from-execute")))))
           (gp-plan :goals '((file-created marker)))
           (let ((ex (gp-run :adapters t)))
             (is-true (execution-success ex))
             (is-true (file-exists-p file))
             (is (equal "from-execute" (adapter-read-file-string file)))
             (is (getf (first (execution-steps ex)) :external))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test symbolic-path-unaffected-by-adapter-flag
  "Planner/MEA stay free of OS calls."
  (gp-clear-memory)
  (gp-reset)
  (let ((*invoke-adapters* t))
    (gp-add-fact '(device interface-01))
    (gp-add-fact '(power-state interface-01 off))
    (gp-add-operator
     (make-operator :name 'power-on
                    :preconditions '((device ?d) (power-state ?d off))
                    :add-list '((power-state ?d on))
                    :delete-list '((power-state ?d off))))
    (let ((plan (gp-plan :goals '((power-state interface-01 on)))))
      (is-true (plan-success plan))
      (is (fact-p '(power-state interface-01 off) (gp-facts))))))
