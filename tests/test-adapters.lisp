;;;; tests/test-adapters.lisp — Phase 8 OS adapters (temp dirs only)

(in-package #:automa-gp/tests)

(def-suite adapters-suite :in automa-gp-suite)
(in-suite adapters-suite)

;;; ---------------------------------------------------------------------------
;;; Fixtures (also used by tests/test-domains.lisp)
;;; ---------------------------------------------------------------------------

(defun %call-with-adapter-directory (thunk)
  "Call THUNK with a new, empty directory under the temporary directory.
The directory and everything in it are deleted afterwards. Its name holds
the PID, so two test runs at the same time do not share it."
  (let ((dir (uiop:ensure-directory-pathname
              (merge-pathnames
               (format nil "automa-gp-adapters-~D-~36R/"
                       (current-process-id) (random (expt 36 8)))
               (uiop:temporary-directory)))))
    (ensure-directories-exist dir)
    (unwind-protect (funcall thunk dir)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(defmacro %with-adapter-directory ((dir) &body body)
  "Run BODY with DIR bound to a temporary directory of its own."
  `(%call-with-adapter-directory (lambda (,dir) ,@body)))

(defun %adapter-refusal (thunk)
  "The reason of the ACTION-FAILED that THUNK signals, or :RETURNED."
  (handler-case (progn (funcall thunk) :returned)
    (action-failed (c) (action-failed-reason c))))

(defun %write-marker-operator (file content)
  "An operator whose :EXTERNAL spec writes CONTENT to FILE."
  (make-operator
   :name 'write-marker
   :preconditions '((path-ready ?name))
   :add-list '((file-created ?name))
   :meta (list :external
               (list :adapter :filesystem
                     :op :write-string
                     :args (list :path file :content content)))))

;;; ---------------------------------------------------------------------------
;;; The adapters stay off unless an execute asks for them
;;; ---------------------------------------------------------------------------

(test filesystem-primitives-temp
  (%with-adapter-directory (dir)
    (let ((file (merge-pathnames "marker.txt" dir)))
      (adapter-ensure-directory dir)
      (is-false (file-exists-p file))
      (adapter-write-file-string file "hello-gp")
      (is-true (file-exists-p file))
      (is (equal "hello-gp" (adapter-read-file-string file)))
      (is (plusp (length (directory-files dir "*.txt"))))
      (is-true (adapter-delete-file file))
      (is-false (file-exists-p file)))))

(test process-run-and-running-p
  (multiple-value-bind (out code)
      (run-program '("echo" "automa-gp") :output :string)
    (is (eql 0 code))
    (is (search "automa-gp" out)))
  ;; Current image PID must be running (ps -p). The name lookup of a
  ;; process that does run is tested below with a child of this test.
  (is-true (process-running-p (current-process-id)))
  (is-false (process-running-p "automa-gp-no-such-process-xyzzy")))

(test macos-dispatch-safe
  (let ((r (macos-dispatch :macos-p nil)))
    (is (getf r :ok))
    (is (eq (macos-p) (getf r :macos))))
  (let ((r (macos-dispatch :uname nil)))
    (is (getf r :ok))
    (is (stringp (getf r :uname)))))

(test simulate-never-invokes-adapters
  (%with-adapter-directory (dir)
    (let ((file (merge-pathnames "should-not-exist.txt" dir))
          (*invoke-adapters* t))
      (gp-clear-memory)
      (gp-reset)
      (gp-add-fact '(path-ready marker))
      (gp-add-operator (%write-marker-operator file "from-sim"))
      (gp-plan :goals '((file-created marker)))
      (gp-simulate)
      (is-false (file-exists-p file))
      (is (fact-p '(path-ready marker) (gp-facts))))))

(test execute-with-adapters-writes-temp-file
  (%with-adapter-directory (dir)
    (let ((file (merge-pathnames "created.txt" dir)))
      (flet ((plan-the-marker ()
               (gp-reset)
               (gp-add-fact '(path-ready marker))
               (gp-add-operator (%write-marker-operator file "from-execute"))
               (gp-plan :goals '((file-created marker)))))
        (gp-clear-memory)
        (gp-adapters nil)
        ;; adapters off → symbolic only
        (plan-the-marker)
        (gp-run :adapters nil)
        (is-false (file-exists-p file))
        (is (fact-p '(file-created marker) (gp-facts)))
        ;; reset facts and run with adapters
        (plan-the-marker)
        (let ((ex (gp-run :adapters t)))
          (is-true (execution-success ex))
          (is-true (file-exists-p file))
          (is (equal "from-execute" (adapter-read-file-string file)))
          (is (getf (first (execution-steps ex)) :external)))))))

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

;;; ---------------------------------------------------------------------------
;;; Filesystem
;;; ---------------------------------------------------------------------------

(test file-exists-p-sees-files-and-directories
  "FILE-EXISTS-P and the :FILE-EXISTS op answer for a directory as for a
file, with or without the trailing slash."
  (%with-adapter-directory (dir)
    (let ((file (merge-pathnames "here.txt" dir)))
      (adapter-write-file-string file "x")
      (loop for (path expected)
              in (list (list dir t)
                       (list (namestring dir) t)
                       (list (string-right-trim "/" (namestring dir)) t)
                       (list file t)
                       (list (namestring file) t)
                       (list (merge-pathnames "absent.txt" dir) nil)
                       (list (merge-pathnames "absent/" dir) nil))
            do (is (eq expected (file-exists-p path))
                   "FILE-EXISTS-P of ~S is not ~S" path expected)
               (is (equal (list :ok t :exists expected :path path)
                          (filesystem-dispatch :file-exists
                                               (list :path path))))))))

(test filesystem-dispatch-works-on-a-temporary-directory
  "Every filesystem op, through the dispatch, against real files."
  (%with-adapter-directory (dir)
    (let* ((nested (merge-pathnames "a/b/" dir))
           (file (merge-pathnames "note.txt" nested))
           (other (merge-pathnames "data.csv" nested))
           (deep (merge-pathnames "c/d/new.txt" dir)))
      (flet ((fs (op &rest args) (filesystem-dispatch op args))
             (names (files) (sort (mapcar #'file-namestring files) #'string<)))
        ;; :ensure-directory creates the parents; the slash is optional.
        (let ((r (fs :ensure-directory
                     :path (string-right-trim "/" (namestring nested)))))
          (is-true (getf r :ok))
          (is (uiop:pathname-equal nested (getf r :directory)))
          (is-true (uiop:directory-exists-p nested)))
        (is (equal '(:ok t :truename nil) (fs :probe :path file)))
        (is (null (getf (fs :directory-files :directory nested) :files)))
        ;; :write-string, :read-string, :probe.
        (is (uiop:pathname-equal
             file (getf (fs :write-string :path file :content "uno") :path)))
        (is (equal "uno" (getf (fs :read-string :path file) :string)))
        (is (equal (truename file) (getf (fs :probe :path file) :truename)))
        ;; :if-exists goes to OPEN: append, error, supersede (the default).
        (fs :write-string :path file :content "-due" :if-exists :append)
        (is (equal "uno-due" (adapter-read-file-string file)))
        (signals file-error
          (fs :write-string :path file :content "tre" :if-exists :error))
        (is (equal "uno-due" (adapter-read-file-string file)))
        (fs :write-string :path file :content "tre")
        (is (equal "tre" (adapter-read-file-string file)))
        ;; No :content writes an empty file; missing parents are created.
        (fs :write-string :path deep)
        (is (equal "" (adapter-read-file-string deep)))
        ;; :directory-files lists files, not subdirectories.
        (fs :write-string :path other :content "1,2")
        (fs :ensure-directory :path (merge-pathnames "sub/" nested))
        (loop for (pattern expected) in '((nil ("data.csv" "note.txt"))
                                          ("*.txt" ("note.txt"))
                                          ("*.md" ()))
              for r = (apply #'fs :directory-files :directory nested
                             (when pattern (list :pattern pattern)))
              do (is-true (getf r :ok))
                 (is (equal expected (names (getf r :files)))))
        (is (null (getf (fs :directory-files
                            :directory (merge-pathnames "absent/" dir))
                        :files)))
        ;; :read-string of a missing file is an error, not an empty string.
        (signals file-error
          (fs :read-string :path (merge-pathnames "absent.txt" nested)))
        ;; :delete-file deletes a file once and never a directory.
        (is (equal '(:ok t :deleted t) (fs :delete-file :path file)))
        (is-false (file-exists-p file))
        (is (equal '(:ok t :deleted nil) (fs :delete-file :path file)))
        (is (equal '(:ok t :deleted nil) (fs :delete-file :path nested)))
        (is-true (uiop:directory-exists-p nested))
        (is-true (file-exists-p other))))))

(test write-file-string-with-if-exists-nil-leaves-the-file-alone
  "OPEN returns no stream then: nothing is written, to the file or to
*STANDARD-OUTPUT*, and the value says so."
  (%with-adapter-directory (dir)
    (let ((file (merge-pathnames "kept.txt" dir))
          (value :unset))
      (is (uiop:pathname-equal
           file (adapter-write-file-string file "first" :if-exists nil)))
      (is (equal ""
                 (with-output-to-string (*standard-output*)
                   (setf value (adapter-write-file-string
                                file "second" :if-exists nil)))))
      (is (null value))
      (is (equal "first" (adapter-read-file-string file))))))

;;; ---------------------------------------------------------------------------
;;; Refusals
;;; ---------------------------------------------------------------------------

(test adapter-dispatch-refuses-what-it-cannot-do
  "An op the adapter does not have, a missing or misspelled argument and a
variable no step bound signal ACTION-FAILED naming what is wrong. None of
them comes back as an :OK result."
  (loop for (dispatch op args wanted)
          in '((filesystem-dispatch :file-exists () ":PATH")
               (filesystem-dispatch :file-exists (:file "/tmp") ":PATH")
               (filesystem-dispatch :file-exists (:path ?where) "?WHERE")
               (filesystem-dispatch :directory-files () ":DIRECTORY")
               (filesystem-dispatch :directory-files (:path "/tmp") ":DIRECTORY")
               (filesystem-dispatch :ensure-directory () ":PATH")
               (filesystem-dispatch :probe () ":PATH")
               (filesystem-dispatch :read-string () ":PATH")
               (filesystem-dispatch :write-string (:content "x") ":PATH")
               (filesystem-dispatch :delete-file (:path ?gone) "?GONE")
               (filesystem-dispatch :format-disk () ":FORMAT-DISK")
               (processes-dispatch :run () ":COMMAND")
               (processes-dispatch :run (:command "echo no shell") "echo no shell")
               (processes-dispatch :run (:command ("true") :force-shell t)
                ":FORCE-SHELL")
               (processes-dispatch :run (:command ("echo" ?word)) "?WORD")
               (processes-dispatch :run (:command ("echo" nil)) "NIL")
               (processes-dispatch :run (:command ("echo" ("nested"))) "nested")
               (processes-dispatch :running () ":NAME")
               (processes-dispatch :kill (:name 1) ":KILL")
               (macos-dispatch :open () ":TARGET")
               (macos-dispatch :reboot () ":REBOOT"))
        for reason = (%adapter-refusal (lambda () (funcall dispatch op args)))
        do (is (and (stringp reason) (search wanted reason))
               "~S ~S ~S gave ~S" dispatch op args reason)))

(test invoke-external-spec-reports-and-signals
  "The result plist comes back when the adapter succeeds. A failure is an
ACTION-FAILED that names the operator, unless the spec is :SOFT."
  (%with-adapter-directory (dir)
    (let* ((file (merge-pathnames "spec.txt" dir))
           (operator (make-operator :name 'write-spec))
           (write (list :adapter :filesystem :op :write-string
                        :args (list :path '?path :content '?text)))
           (bindings (list (cons '?path (namestring file))
                           (cons '?text "bound"))))
      ;; Bindings are substituted; the spec itself is left as written.
      (is-true (getf (invoke-external-spec write bindings) :ok))
      (is (equal "bound" (adapter-read-file-string file)))
      (is (eq '?path (getf (getf write :args) :path)))
      ;; A variable bound to another variable is followed to its value, as
      ;; the core does when it grounds the operator itself.
      (is-true (getf (invoke-external-spec
                      write (list (cons '?path '?where)
                                  (cons '?text '?words)
                                  (cons '?where (namestring file))
                                  (cons '?words "followed")))
                     :ok))
      (is (equal "followed" (adapter-read-file-string file)))
      ;; A failure: unknown adapter, unknown op, misspelled argument, an
      ;; argument still unbound, a program that fails or does not exist.
      (loop for (spec wanted)
              in `(((:adapter :telepathy :op :read) ":TELEPATHY")
                   ((:adapter :filesystem :op :shred) ":SHRED")
                   ((:adapter :filesystem :op :file-exists
                     :args (:file ,(namestring file)))
                    ":PATH")
                   (,write "?PATH")
                   ((:adapter :processes :op :run :args (:command ("false")))
                    "false")
                   ((:adapter :processes :op :run
                     :args (:command ("false") :ignore-error-status t))
                    ":EXIT-CODE 1")
                   ((:adapter :processes :op :run
                     :args (:command ("automa-gp-no-such-program-xyzzy")))
                    "automa-gp-no-such-program-xyzzy"))
            for failure = (handler-case
                              (progn (invoke-external-spec spec nil
                                                           :operator operator)
                                     :returned)
                            (action-failed (c) c))
            do (is (typep failure 'action-failed) "~S returned" spec)
               (when (typep failure 'action-failed)
                 (is (search wanted (action-failed-reason failure))
                     "~S gave ~S" spec (action-failed-reason failure))
                 (is (eq operator (gp-condition-operator failure))))
               ;; The same spec marked :SOFT returns the failure instead.
               (is (null (getf (invoke-external-spec (list* :soft t spec) nil)
                               :ok)))))))

;;; ---------------------------------------------------------------------------
;;; Processes
;;; ---------------------------------------------------------------------------

(test run-program-hands-arguments-to-the-program-as-they-are
  "No shell reads a list command: an argument with spaces, a dollar sign
or a star stays one argument. A non-zero exit is an error unless ignored."
  (is (equal (format nil "$HOME ; echo two *~%")
             (run-program '("echo" "$HOME ; echo two" "*") :output :string)))
  (is (equal '(nil 1)
             (multiple-value-list
              (run-program '("false") :ignore-error-status t))))
  (signals uiop:subprocess-error (run-program '("false"))))

(test process-running-p-tells-a-process-from-a-number
  "An integer that is not positive is no PID. PID 1 belongs to another user
and is running all the same. A lookup that could not be made says so."
  (loop for (designator expected)
          in `((0 nil)
               (-1 nil)
               (,(- (current-process-id)) nil)
               (2147483646 nil)
               (1 t)
               (,(current-process-id) t)
               ("" nil)
               ("automa-gp-no-such-process-xyzzy" nil))
        do (is (equal (list expected)
                      (multiple-value-list (process-running-p designator)))
               "PROCESS-RUNNING-P of ~S is not ~S" designator expected)
           (when (integerp designator)
             (is (equal (list :ok t :running expected)
                        (processes-dispatch :running
                                            (list :name designator))))))
  ;; pgrep cannot compile this name as a regular expression.
  (is (equal '(nil :unknown) (multiple-value-list (process-running-p "("))))
  (is (search "could not look up"
              (%adapter-refusal
               (lambda () (processes-dispatch :running '(:name "(")))))))

(test process-running-p-finds-a-child-by-pid-and-by-name
  "A child this test starts is found by PID, by exact name and by command
line, and is gone once it has been stopped."
  (let* ((child (uiop:launch-program '("sleep" "61")))
         (pid (uiop:process-info-pid child)))
    (unwind-protect
         (loop for designator in (list pid "sleep" "sleep 61")
               do (is-true (process-running-p designator)
                           "~S is not found running" designator)
                  (is (equal '(:ok t :running t)
                             (processes-dispatch :running
                                                 (list :name designator)))))
      (uiop:terminate-process child :urgent t)
      (uiop:wait-process child))
    (is (equal '(nil) (multiple-value-list (process-running-p pid))))))

(test processes-dispatch-run-takes-a-list-and-never-a-shell
  "Strings, symbols, numbers and pathnames each become one argument.
A string command and a command with :FORCE-SHELL are not run at all.
:OK follows the exit status even when the status is ignored."
  (%with-adapter-directory (dir)
    (let* ((file (merge-pathnames "made by a shell.txt" dir))
           (native (uiop:native-namestring file)))
      (is (equal (list :ok t
                       :output (format nil "MARKER 3 1.5 ~A $HOME~%" native)
                       :exit-code 0)
                 (processes-dispatch
                  :run (list :command
                             (list "echo" 'marker 3 1.5 file "$HOME")))))
      (loop for args in (list (list :command (format nil "touch '~A'" native))
                              (list :command (list "touch" native)
                                    :force-shell t))
            do (signals action-failed (processes-dispatch :run args))
               (is-false (file-exists-p file) "~S ran" args))
      (is (equal '(:ok nil :output "" :exit-code 1)
                 (processes-dispatch
                  :run '(:command ("false") :ignore-error-status t))))
      (signals uiop:subprocess-error
        (processes-dispatch :run '(:command ("false")))))))

;;; ---------------------------------------------------------------------------
;;; macOS
;;; ---------------------------------------------------------------------------

(test macos-adapter-answers-without-side-effects
  ":UNAME is what `uname -s` prints and :HOSTNAME is a name. :OPEN of a
file that does not exist opens nothing and fails."
  (is (equal (string-trim '(#\Newline)
                          (run-program '("uname" "-s") :output :string))
             (getf (macos-dispatch :uname nil) :uname)))
  (let ((host (getf (macos-dispatch :hostname nil) :hostname)))
    (is (and (stringp host) (plusp (length host)))))
  (let* ((target "/automa-gp-no-such-directory/absent.txt")
         (r (macos-dispatch :open (list :target target))))
    (is (null (getf r :ok)))
    (is (equal target (getf r :target)))
    (if (macos-p)
        (is (eql 1 (getf r :exit-code)))
        (is (eq :not-macos (getf r :error))))))

;;; ---------------------------------------------------------------------------
;;; External-action gates: which context, which facts
;;; ---------------------------------------------------------------------------

(defun %external-gate-fixture ()
  "A context with one operator that carries an :EXTERNAL spec, and the plan
for its goal. Returns (VALUES CONTEXT PLAN OPERATORS). The context is not
the session context."
  (let ((ctx (create-context :name 'gate-fixture)))
    (context-add-fact! ctx '(source ready))
    (register-operator!
     ctx (make-operator
          :name 'publish
          :preconditions '((source ready))
          :add-list '((published))
          :meta (list :external (list :adapter :filesystem
                                      :op :file-exists
                                      :args (list :path "/tmp")))))
    (let ((plan (plan-from-context ctx :goals '((published)))))
      (values ctx plan (context-planning-operators ctx)))))

(test external-gates-read-the-context-they-are-given
  "With a context, or with operators alone, the gates do not look at the
session; with neither they read the session and never create one."
  (multiple-value-bind (ctx plan operators) (%external-gate-fixture)
    (is-true (plan-success plan))
    (loop for session in (list nil (create-context :name 'unrelated-session))
          do (let ((*current-context* session))
               ;; Neither: the session, which does not know PUBLISH.
               (is (null (plan-external-actions plan)))
               (is (not (plan-external-actions-match-p plan)))
               (is (eq session *current-context*))
               ;; A context, or operators alone.
               (loop for keys in (list (list :context ctx)
                                       (list :operators operators))
                     do (is (= 1 (length (apply #'plan-external-actions
                                                plan keys))))
                        (is-true (apply #'plan-external-actions-match-p
                                        plan keys))
                        (is-true (apply #'plan-external-actions-supported-p
                                        plan keys))
                        (is (eq session *current-context*)))
               ;; So a simulation given the plan's operators and no context
               ;; is judged on the plan, whatever session is open.
               (is-true (execution-success
                         (simulate-plan plan :operators operators)))))))

(test external-support-is-judged-on-the-facts-supplied
  ":FACTS replaces the facts of the context: the answer is about the run
that starts from them."
  (multiple-value-bind (ctx plan operators) (%external-gate-fixture)
    (loop for (keys facts expected)
            in `(((:context ,ctx) ((source ready)) t)
                 ((:context ,ctx) () nil)
                 ((:operators ,operators) ((source ready)) t)
                 ((:operators ,operators) () nil))
          do (is (eq expected
                     (and (apply #'plan-external-actions-supported-p
                                 plan :facts facts keys)
                          t))
                 "~S from ~S is not ~S" (first keys) facts expected))
    ;; The live facts still decide when no facts are supplied.
    (context-remove-fact! ctx '(source ready))
    (is (not (plan-external-actions-supported-p plan :context ctx)))
    (is-true (plan-external-actions-supported-p
              plan :context ctx :facts '((source ready))))
    ;; Without a context the plan's own initial state does.
    (is-true (plan-external-actions-supported-p plan :operators operators))))
