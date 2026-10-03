;;;; tests/test-notice.lisp — notices and watches over files, processes and terminals

(in-package #:automa-gp/tests)

(def-suite notice-suite :in automa-gp-suite)
(in-suite notice-suite)

(defun %test-tty-name-p (name)
  "True when NAME looks like a pty (ttys000, ttyv0, pts/0)."
  (and (stringp name)
       (plusp (length name))
       (or (search "tty" name :test #'char-equal)
           (and (>= (length name) 4)
                (string-equal "pts/" name :end2 4)))))

(defun %test-linux-script-p ()
  "util-linux script(1) needs -c; BSD/macOS take a trailing command."
  (eq (uiop:operating-system) :linux))

(defun %test-script-argv (typescript &rest command)
  "Argv that runs COMMAND under script(1) writing TYPESCRIPT."
  (if (%test-linux-script-p)
      (list "script" "-q" "-c" (uiop:escape-shell-command command) typescript)
      (list* "script" "-q" typescript command)))

(defun %test-session-tty (marker)
  "TTY name and pid of the process whose command contains MARKER."
  ;; -ww keeps BSD/Linux from truncating the marker off the command line.
  (let ((text (uiop:run-program '("ps" "-axww" "-o" "pid=" "-o" "tty=" "-o" "command=")
                                :output :string
                                :ignore-error-status t)))
    (dolist (line (uiop:split-string text :separator '(#\Newline #\Return)))
      (when (search marker line)
        (let* ((trim (string-left-trim '(#\Space #\Tab) line))
               (gap (position #\Space trim))
               (pid (and gap (subseq trim 0 gap)))
               (rest (and gap
                          (string-left-trim '(#\Space #\Tab)
                                            (subseq trim gap))))
               (gap2 (and rest (position #\Space rest)))
               (tty (and gap2 (subseq rest 0 gap2))))
          (when (and tty (%test-tty-name-p tty) pid)
            (return (values tty pid))))))))

(defun %test-typescript (marker)
  "Path of the typescript the PTY session named MARKER writes."
  (format nil "/tmp/automa-gp-script-~A" marker))

(defun %test-delete-typescripts (&rest markers)
  "Delete the typescripts the PTY sessions named MARKERS left behind."
  (dolist (marker markers)
    (ignore-errors (delete-file (%test-typescript marker)))))

(defun %test-open-pty-session (marker)
  "Launch a short-lived PTY session whose command line contains MARKER."
  ;; A real typescript path is more reliable than /dev/null on FreeBSD.
  (uiop:launch-program
   (%test-script-argv (%test-typescript marker) "perl" "-e"
                      (format nil "sleep 60; # ~A" marker))
   :output #P"/dev/null"
   :error-output #P"/dev/null"))

(defun %test-ensure-tty (marker &optional session)
  "Return (values TTY CHILD SESSION OVERRIDE). Allocates a PTY when possible;
otherwise OVERRIDE is a synthetic name for *NOTICE-OPEN-TERMINALS-OVERRIDE*."
  (let ((tty nil) (child nil) (sess session))
    (unless sess
      (setf sess (%test-open-pty-session marker)))
    (loop repeat 80
          until tty
          do (sleep 0.05)
             (setf (values tty child) (%test-session-tty marker)))
    (if (stringp tty)
        (values tty child sess nil)
        (let ((synthetic (format nil "pts/agp-~A"
                                 (subseq marker (max 0 (- (length marker) 12))))))
          (when (and sess (uiop:process-alive-p sess))
            (ignore-errors (uiop:terminate-process sess :urgent t)))
          (values synthetic nil nil synthetic)))))

(test notice-path-rejects-an-unmodeled-file
  (gp-clear-memory)
  (gp-reset)
  (uiop:with-temporary-file (:pathname path)
    (signals error (gp-notice-path (namestring path)))
    (is (null (gp-facts)))
    (is (null (gp-events)))))

(test notice-path-rejects-a-directory-and-a-missing-file
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'on-file
                        :when '(automa-gp::file-created ?path)))
  (signals error (gp-notice-path (namestring (uiop:temporary-directory))))
  (signals error (gp-notice-path "/tmp/automa-gp-notice-missing-file"))
  (is (null (gp-facts)))
  (is (null (gp-events))))

(test notice-path-keeps-the-listening-before-state
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'on-file
                        :when '(automa-gp::file-created ?path)))
  (gp-add-fact '(device interface-01))
  (gp-listen :reason :manual)
  (let ((before (copy-tree *observed-before*)))
    (uiop:with-temporary-file (:pathname path)
      (let* ((name (namestring path))
             (fact (gp-notice-path name)))
        (is (equal (list 'automa-gp::file-created name) fact))
        (is (fact-p fact (gp-facts)))
        (is (not (fact-p fact before)))
        (is (equal before *observed-before*))
        (is (observation-active-p))
        (is (= 1 (length (gp-events))))
        (gp-notice-path name)
        (is (= 1 (length (gp-events))))
        (is (= 1 (count 'automa-gp::file-created (gp-facts) :key #'car))))))
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'only-one
                        :when '(automa-gp::file-created "only-this.txt")))
  (uiop:with-temporary-file (:pathname path)
    (signals error (gp-notice-path (namestring path)))
    (is (null (gp-events)))))

(test notice-directory-applies-the-reaction-and-leaves-the-disk-to-run
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-notice-dir-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (source (merge-pathnames "note.txt" dir))
         (nested (merge-pathnames "nested/skip.txt" dir))
         (marker (merge-pathnames "marker.txt" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist nested)
           (adapter-write-file-string source "hello")
           (adapter-write-file-string nested "skip")
           (signals error (gp-notice-directory (namestring dir)))
           (is (null (gp-facts)))
           (gp-add-reaction
            (make-event-reaction :name 'on-file
                                 :when '(automa-gp::file-created ?path)
                                 :assert '((seen ?path))
                                 :goals '((noted ?path))))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((seen ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path (namestring marker)
                                           :content "noticed")))))
           (gp-add-fact '(bench clear))
           (gp-listen :reason :manual)
           (let ((before (copy-tree *observed-before*))
                 (name (namestring source)))
             (let ((noticed (gp-notice-directory (namestring dir))))
               (is (member (list 'automa-gp::file-created name) noticed :test #'equal))
               (is (member (list 'automa-gp::file-created (namestring nested))
                           noticed :test #'equal))
               (is (= 2 (length noticed)))
               (is (fact-p (list 'automa-gp::file-created name) (gp-facts)))
               (is (fact-p (list 'seen name) (gp-facts)))
               (is (fact-p (list 'automa-gp::file-created (namestring nested))
                           (gp-facts)))
               (is (member (list 'noted (namestring nested)) (gp-goals)
                           :test #'equal))
               (is (member (list 'noted name) (gp-goals) :test #'equal))
               (is (equal before *observed-before*))
               (is-false (file-exists-p marker))
               (gp-notice-directory (namestring dir))
               (is (= 2 (count 'automa-gp::file-created (gp-facts) :key #'car)))
               (is (= 2 (length (gp-events))))
               (let ((plan (gp-plan :goals (list (list 'noted name)))))
                 (is (plan-success plan))
                 (gp-simulate)
                 (is-false (file-exists-p marker))
                 (is (fact-p '(bench clear) (gp-facts)))
                 (let ((ex (gp-run :adapters t)))
                   (is-true (execution-success ex))
                   (is (equal "noticed" (adapter-read-file-string marker)))
                   (is (fact-p (list 'noted name) (gp-facts))))))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test plan-open-goals-uses-a-noticed-goal-without-running
  (gp-clear-memory)
  (gp-reset)
  (signals error (gp-plan-open-goals))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan-open-goals")
    (is (= 400 code))
    (is (search "no open goal" (getf body :error))))
  (gp-add-goal '(power-state interface-01 on))
  (gp-add-fact '(power-state interface-01 on))
  (signals error (gp-plan-open-goals))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/plan-open-goals")
    (is (= 400 code))
    (is (search "no open goal" (getf body :error))))
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-plan-open-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (source (merge-pathnames "note.txt" dir))
         (marker (merge-pathnames "marker.txt" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist source)
           (adapter-write-file-string source "hello")
           (gp-add-reaction
            (make-event-reaction :name 'on-file
                                 :when '(automa-gp::file-created ?path)
                                 :assert '((seen ?path))
                                 :goals '((noted ?path))))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((seen ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path (namestring marker)
                                           :content "noticed")))))
           (let ((name (namestring source)))
             (gp-notice-directory (namestring dir))
             (is (member (list 'noted name) (gp-goals) :test #'equal))
             (let ((facts (copy-tree (gp-facts)))
                   (plan (gp-plan-open-goals)))
               (is (plan-success plan))
               (is (eq 'note-file (getf (first (plan-steps plan)) :operator)))
               (is (equal facts (gp-facts)))
               (is (null (gp-last-execution)))
               (is-false (file-exists-p marker)))
             (multiple-value-bind (code body)
                 (web-api-handle :post "/api/plan-open-goals")
               (is (= 200 code))
               (is (eq t (getf (getf body :plan) :success)))
               (is (find 'note-file (getf (getf body :plan) :operators-used)))
               (is (not (getf body :execution)))
               (is (not (fact-p (list 'noted name) (gp-facts))))
               (is-false (file-exists-p marker)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test notice-directory-does-not-follow-a-linked-directory
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-notice-link-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (outside (uiop:ensure-directory-pathname
                   (merge-pathnames
                    (format nil "automa-gp-notice-outside-~A/" (get-universal-time))
                    (uiop:temporary-directory))))
         (secret (merge-pathnames "secret.txt" outside))
         (link (merge-pathnames "linked" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (ensure-directories-exist secret)
           (adapter-write-file-string secret "outside")
           (sb-posix:symlink (namestring outside) (namestring link))
           (gp-add-reaction
            (make-event-reaction :name 'on-file
                                 :when '(automa-gp::file-created ?path)))
           (gp-notice-directory (namestring dir))
           (is (not (find "secret.txt" (gp-facts)
                          :test (lambda (text fact)
                                  (and (consp fact)
                                       (stringp (second fact))
                                       (search text (second fact)))))))
           (is (null (gp-facts))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore)
      (uiop:delete-directory-tree outside :validate t :if-does-not-exist :ignore))))

(test notice-directory-rejects-a-file-and-a-missing-directory
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'on-file
                        :when '(automa-gp::file-created ?path)))
  (uiop:with-temporary-file (:pathname path)
    (signals error (gp-notice-directory (namestring path))))
  (signals error (gp-notice-directory "/tmp/automa-gp-notice-missing-dir"))
  (is (null (gp-facts))))

(test watch-directory-notices-a-file-that-appears-later
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-watch-dir-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (source (merge-pathnames "note.txt" dir))
         (nested (merge-pathnames "nested/skip.txt" dir))
         (later (merge-pathnames "later.txt" dir)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (ensure-directories-exist nested)
           (gp-add-reaction
            (make-event-reaction :name 'on-file
                                 :when '(automa-gp::file-created ?path)
                                 :assert '((seen ?path))
                                 :goals '((noted ?path))))
           (let ((noticed (gp-watch-directory (namestring dir) :interval 0.05)))
             (is (null noticed))
             (is (search (namestring dir) (gp-directory-watch))))
           (signals error (gp-watch-directory (namestring dir) :interval 0.05))
           (adapter-write-file-string source "hello")
           (adapter-write-file-string nested "skip")
           (let ((name (namestring source)))
             (loop repeat 40
                   until (and (fact-p (list 'automa-gp::file-created name) (gp-facts))
                              (fact-p (list 'automa-gp::file-created (namestring nested))
                                      (gp-facts)))
                   do (sleep 0.05))
             (gp-stop-directory-watch)
             (is (null (gp-directory-watch)))
             (is (fact-p (list 'automa-gp::file-created name) (gp-facts)))
             (is (fact-p (list 'seen name) (gp-facts)))
             (is (member (list 'noted name) (gp-goals) :test #'equal))
             (is (fact-p (list 'automa-gp::file-created (namestring nested))
                         (gp-facts)))
             (is (member (list 'noted (namestring nested)) (gp-goals) :test #'equal))
             (adapter-write-file-string later "later")
             (sleep 0.2)
             (is (not (find "later.txt" (gp-facts)
                            :test (lambda (text fact)
                                    (and (consp fact)
                                         (stringp (second fact))
                                         (search text (second fact))))))))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :post "/api/watch-directory"
                                    (format nil "{\"path\":~A,\"interval\":0.05}"
                                            (lisp->json (namestring dir))))
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search "\"ok\":true" json)))
           (let ((status (nth-value 2 (web-api-handle-json :get "/api/status"))))
             (is (search (namestring dir) status)))
           (gp-stop-directory-watch)
           (is (null (gp-directory-watch)))
           (gp-watch-directory (namestring dir) :interval 0.05)
           (gp-reset)
           (is (null (gp-directory-watch)))
           (is (not (find "automa-gp-directory-watch"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=))))
      (when (gp-directory-watch)
        (gp-stop-directory-watch))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test notice-processes-records-the-running-image
  (gp-clear-memory)
  (gp-reset)
  (signals error (gp-notice-processes))
  (is (null (gp-facts)))
  (let ((pid (current-process-id)))
    (gp-add-reaction
     (make-event-reaction :name 'on-self
                          :when (list 'automa-gp::process-running pid)
                          :assert '((lisp-image up))
                          :goals '((noted-image up))))
    (gp-add-reaction
     (make-event-reaction :name 'on-missing
                          :when '(automa-gp::process-running
                                  "automa-gp-no-such-process-xyzzy")))
    (gp-add-fact '(bench clear))
    (gp-listen :reason :manual)
    (let ((before (copy-tree *observed-before*)))
      (let ((noticed (gp-notice-processes)))
        (is (equal (list (list 'automa-gp::process-running pid)) noticed))
        (is (fact-p (list 'automa-gp::process-running pid) (gp-facts)))
        (is (fact-p '(lisp-image up) (gp-facts)))
        (is (equal '((noted-image up)) (gp-goals)))
        (is (not (find "xyzzy" (gp-facts)
                       :test (lambda (text fact)
                               (and (consp fact)
                                    (stringp (second fact))
                                    (search text (second fact)))))))
        (is (equal before *observed-before*))
        (gp-notice-processes)
        (is (= 1 (count 'automa-gp::process-running (gp-facts) :key #'car)))
        (is (= 1 (length (gp-events))))))
    (multiple-value-bind (code ctype json)
        (web-api-handle-json :post "/api/notice-processes" "{}")
      (declare (ignore ctype))
      (is (= 200 code))
      (is (search (princ-to-string pid) json))
      (is (search "LISP-IMAGE" json))
      (is (not (search "xyzzy" json)))))
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'only-var
                        :when '(automa-gp::process-running ?name)))
  (signals error (gp-notice-processes))
  (is (null (gp-facts))))

(test watch-processes-notices-a-process-that-appears-later
  (let* ((stamp (format nil "~A-~A" (get-universal-time) (random 100000)))
         (token (format nil "automa-gp-watch-proc-~A" stamp))
         (later (format nil "automa-gp-watch-later-~A" stamp))
         (born nil)
         (late nil))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (gp-reset)
           (gp-add-reaction
            (make-event-reaction :name 'on-token
                                 :when (list 'automa-gp::process-running token)
                                 :assert '((watched-process up))
                                 :goals '((noted-process up))))
           (let ((noticed (gp-watch-processes :interval 0.05)))
             (is (null noticed))
             (is (gp-process-watch)))
           (signals error (gp-watch-processes :interval 0.05))
           (setf born (uiop:launch-program
                       (list "perl" "-e"
                             (format nil "sleep 60; # ~A" token))
                       :output :stream :error-output :stream))
           (loop repeat 80
                 until (fact-p (list 'automa-gp::process-running token) (gp-facts))
                 do (sleep 0.05))
           (is (fact-p (list 'automa-gp::process-running token) (gp-facts)))
           (is (fact-p '(watched-process up) (gp-facts)))
           (is (equal '((noted-process up)) (gp-goals)))
           (gp-stop-process-watch)
           (is (not (gp-process-watch)))
           (gp-add-reaction
            (make-event-reaction :name 'on-later
                                 :when (list 'automa-gp::process-running later)))
           (setf late (uiop:launch-program
                       (list "perl" "-e"
                             (format nil "sleep 60; # ~A" later))
                       :output :stream :error-output :stream))
           (sleep 0.3)
           (is (not (fact-p (list 'automa-gp::process-running later) (gp-facts))))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :post "/api/watch-processes" "{\"interval\":0.05}")
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search "\"watching\":true" json)))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :get "/api/status" "")
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search "\"process-watch\":true" json)))
           (web-api-handle-json :post "/api/watch-processes/stop" "{}")
           (gp-watch-processes :interval 0.05)
           (gp-reset)
           (is (not (gp-process-watch)))
           (is (not (find "automa-gp-process-watch"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=))))
      (when (and born (uiop:process-alive-p born))
        (ignore-errors (uiop:terminate-process born :urgent t)))
      (when (and late (uiop:process-alive-p late))
        (ignore-errors (uiop:terminate-process late :urgent t)))
      (when (gp-process-watch)
        (ignore-errors (gp-stop-process-watch))))))

(test notice-terminals-records-an-open-session
  (let ((marker (format nil "automa-gp-tty-~A-~A"
                        (get-universal-time) (random 100000)))
        (session nil)
        (child nil)
        (tty nil)
        (override nil))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (gp-reset)
           (signals error (gp-notice-terminals))
           (is (null (gp-facts)))
           (setf (values tty child session override) (%test-ensure-tty marker))
           (is (stringp tty))
           (let ((automa-gp::*notice-open-terminals-override*
                  (if override (list override) :ps)))
             (gp-add-reaction
              (make-event-reaction :name 'on-tty
                                   :when (list 'automa-gp::terminal-open tty)
                                   :assert '((session up))
                                   :goals '((noted-terminal up))))
             (gp-add-reaction
              (make-event-reaction :name 'on-missing
                                   :when '(automa-gp::terminal-open
                                           "ttys-automa-gp-missing")))
             (gp-add-fact '(bench clear))
             (gp-listen :reason :manual)
             (let ((before (copy-tree *observed-before*)))
               (let ((noticed (gp-notice-terminals)))
                 (is (equal (list (list 'automa-gp::terminal-open tty)) noticed))
                 (is (fact-p (list 'automa-gp::terminal-open tty) (gp-facts)))
                 (is (fact-p '(session up) (gp-facts)))
                 (is (equal '((noted-terminal up)) (gp-goals)))
                 (is (not (find "ttys-automa-gp-missing" (gp-facts)
                                :test (lambda (text fact)
                                        (and (consp fact)
                                             (stringp (second fact))
                                             (search text (second fact)))))))
                 (is (equal before *observed-before*))
                 (gp-notice-terminals)
                 (is (= 1 (count 'automa-gp::terminal-open (gp-facts) :key #'car)))
                 (is (= 1 (length (gp-events))))))
             (multiple-value-bind (code ctype json)
                 (web-api-handle-json :post "/api/notice-terminals" "{}")
               (declare (ignore ctype))
               (is (= 200 code))
               (is (search tty json))
               (is (search "SESSION" json))
               (is (not (search "ttys-automa-gp-missing" json))))
             (when child
               (ignore-errors
                (uiop:run-program (list "kill" child) :ignore-error-status t)))
             (when (and session (uiop:process-alive-p session))
               (ignore-errors (uiop:terminate-process session :urgent t)))
             (setf session nil)
             (loop repeat 40
                   while (%test-session-tty marker)
                   do (sleep 0.05))
             (gp-reset)
             (gp-add-reaction
              (make-event-reaction :name 'on-closed
                                   :when (list 'automa-gp::terminal-open tty)))
             ;; Closed session / empty override: nothing to notice.
             (let ((automa-gp::*notice-open-terminals-override*
                    (if override nil :ps)))
               (is (null (gp-notice-terminals)))
               (is (null (gp-facts))))
             (gp-reset)
             (gp-add-reaction
              (make-event-reaction :name 'only-var
                                   :when '(automa-gp::terminal-open ?name)))
             (signals error (gp-notice-terminals))
             (is (null (gp-facts)))))
      (when child
        (ignore-errors
         (uiop:run-program (list "kill" "-9" child) :ignore-error-status t)))
      (when (and session (uiop:process-alive-p session))
        (ignore-errors (uiop:terminate-process session :urgent t)))
      (%test-delete-typescripts marker))))

(test watch-terminals-notices-a-terminal-that-opens-later
  (labels ((tty-open-p (name)
             (let ((text (uiop:run-program '("ps" "-axww" "-o" "tty=")
                                           :output :string
                                           :ignore-error-status t)))
               (find name (uiop:split-string text :separator '(#\Newline #\Return #\Space #\Tab))
                     :test #'string=)))
           (close-session (session child)
             (when child
               (ignore-errors
                (uiop:run-program (list "kill" child) :ignore-error-status t)))
             (when (and session (uiop:process-alive-p session))
               (ignore-errors (uiop:terminate-process session :urgent t)))))
    (let* ((stamp (format nil "~A-~A" (get-universal-time) (random 100000)))
           (probe (format nil "automa-gp-tty-probe-~A" stamp))
           (born-mark (format nil "automa-gp-tty-born-~A" stamp))
           (later (format nil "automa-gp-tty-later-~A" stamp))
           (session nil)
           (child nil)
           (tty nil)
           (override nil)
           (saved automa-gp::*notice-open-terminals-override*))
      (unwind-protect
           (progn
             (gp-clear-memory)
             (gp-reset)
             (setf (values tty child session override) (%test-ensure-tty probe))
             (is (stringp tty))
             (close-session session child)
             (setf session nil child nil)
             (when override
               (setf automa-gp::*notice-open-terminals-override* nil))
             (unless override
               (loop repeat 40
                     while (or (%test-session-tty probe) (tty-open-p tty))
                     do (sleep 0.05))
               (is (not (tty-open-p tty))))
             (gp-add-reaction
              (make-event-reaction :name 'on-tty
                                   :when (list 'automa-gp::terminal-open tty)
                                   :assert '((watched-terminal up))
                                   :goals '((noted-terminal up))))
             (let ((noticed (gp-watch-terminals :interval 0.05)))
               (is (null noticed))
               (is (gp-terminal-watch)))
             (signals error (gp-watch-terminals :interval 0.05))
             (if override
                 (setf automa-gp::*notice-open-terminals-override* (list tty))
                 (progn
                   (setf session (%test-open-pty-session born-mark))
                   (let ((opened nil))
                     (loop repeat 80
                           until opened
                           do (sleep 0.05)
                              (setf (values opened child)
                                    (%test-session-tty born-mark)))
                     (is (equal tty opened)))))
             (loop repeat 80
                   until (fact-p (list 'automa-gp::terminal-open tty) (gp-facts))
                   do (sleep 0.05))
             (is (fact-p (list 'automa-gp::terminal-open tty) (gp-facts)))
             (is (fact-p '(watched-terminal up) (gp-facts)))
             (is (equal '((noted-terminal up)) (gp-goals)))
             (gp-stop-terminal-watch)
             (is (not (gp-terminal-watch)))
             (gp-remove-fact (list 'automa-gp::terminal-open tty))
             (gp-remove-fact '(watched-terminal up))
             (close-session session child)
             (setf session nil child nil)
             (if override
                 (setf automa-gp::*notice-open-terminals-override* nil)
                 (loop repeat 40
                       while (or (%test-session-tty born-mark) (tty-open-p tty))
                       do (sleep 0.05)))
             (if override
                 (setf automa-gp::*notice-open-terminals-override* (list tty))
                 (progn
                   (setf session (%test-open-pty-session later))
                   (let ((opened nil))
                     (loop repeat 80
                           until opened
                           do (sleep 0.05)
                              (setf (values opened child)
                                    (%test-session-tty later)))
                     (is (equal tty opened)))))
             (sleep 0.3)
             (is (not (fact-p (list 'automa-gp::terminal-open tty) (gp-facts))))
             (multiple-value-bind (code ctype json)
                 (web-api-handle-json :post "/api/watch-terminals" "{\"interval\":0.05}")
               (declare (ignore ctype))
               (is (= 200 code))
               (is (search "\"watching\":true" json)))
             (multiple-value-bind (code ctype json)
                 (web-api-handle-json :get "/api/status" "")
               (declare (ignore ctype))
               (is (= 200 code))
               (is (search "\"terminal-watch\":true" json)))
             (web-api-handle-json :post "/api/watch-terminals/stop" "{}")
             (gp-watch-terminals :interval 0.05)
             (gp-reset)
             (is (not (gp-terminal-watch)))
             (is (not (find "automa-gp-terminal-watch"
                            (sb-thread:list-all-threads)
                            :key #'sb-thread:thread-name
                            :test #'string=))))
        (setf automa-gp::*notice-open-terminals-override* saved)
        (close-session session child)
        (%test-delete-typescripts probe born-mark later)
        (when (gp-terminal-watch)
          (ignore-errors (gp-stop-terminal-watch)))))))

(test notice-terminal-text-reads-a-named-line
  (let* ((stamp (format nil "~A-~A" (get-universal-time) (random 100000)))
         (token (format nil "automa-gp-line-~A" stamp))
         (path (format nil "/tmp/automa-gp-transcript-~A" stamp))
         (link (format nil "/tmp/automa-gp-transcript-link-~A" stamp)))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (gp-reset)
           (signals error (gp-notice-terminal-text))
           (is (null (gp-facts)))
           (uiop:run-program
            (%test-script-argv path "perl" "-e"
                               (format nil "print \"~A\\n\";" token))
            :output #P"/dev/null"
            :error-output #P"/dev/null"
            :ignore-error-status t)
           (sb-posix:symlink path link)
           (gp-add-reaction
            (make-event-reaction :name 'on-line
                                 :when (list 'automa-gp::terminal-text path token)
                                 :assert '((transcript heard))
                                 :goals '((noted-text up))))
           (gp-add-reaction
            (make-event-reaction :name 'on-missing
                                 :when (list 'automa-gp::terminal-text path
                                             "automa-gp-no-such-line")))
           (gp-add-reaction
            (make-event-reaction :name 'on-link
                                 :when (list 'automa-gp::terminal-text link token)))
           (gp-add-reaction
            (make-event-reaction :name 'on-device
                                 :when '(automa-gp::terminal-text "/dev/null" "x")))
           (gp-add-fact '(bench clear))
           (gp-listen :reason :manual)
           (let ((before (copy-tree *observed-before*)))
             (let ((noticed (gp-notice-terminal-text)))
               (is (equal (list (list 'automa-gp::terminal-text path token)) noticed))
               (is (fact-p (list 'automa-gp::terminal-text path token) (gp-facts)))
               (is (fact-p '(transcript heard) (gp-facts)))
               (is (equal '((noted-text up)) (gp-goals)))
               (is (not (find "automa-gp-no-such-line" (gp-facts)
                              :test (lambda (text fact)
                                      (and (consp fact)
                                           (some (lambda (term)
                                                   (and (stringp term)
                                                        (search text term)))
                                                 fact))))))
               (is (not (fact-p (list 'automa-gp::terminal-text link token) (gp-facts))))
               (is (not (fact-p '(automa-gp::terminal-text "/dev/null" "x") (gp-facts))))
               (is (equal before *observed-before*))
               (gp-notice-terminal-text)
               (is (= 1 (count 'automa-gp::terminal-text (gp-facts) :key #'car)))
               (is (= 1 (length (gp-events))))))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :post "/api/notice-terminal-text" "{}")
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search token json))
             (is (search "TRANSCRIPT" json))
             (is (not (search "automa-gp-no-such-line" json)))
             (is (not (search link json)))))
         (ignore-errors (delete-file link))
         (ignore-errors (delete-file path))))
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'only-var
                        :when '(automa-gp::terminal-text ?path ?text)))
  (signals error (gp-notice-terminal-text))
  (is (null (gp-facts))))

(test watch-terminal-text-notices-a-line-that-appears-later
  (let* ((stamp (format nil "~A-~A" (get-universal-time) (random 100000)))
         (token (format nil "automa-gp-watch-line-~A" stamp))
         (later (format nil "automa-gp-watch-later-~A" stamp))
         (path (format nil "/tmp/automa-gp-watch-text-~A" stamp)))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (gp-reset)
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "" out))
           (gp-add-reaction
            (make-event-reaction :name 'on-line
                                 :when (list 'automa-gp::terminal-text path token)
                                 :assert '((watched-text up))
                                 :goals '((noted-text up))))
           (let ((noticed (gp-watch-terminal-text :interval 0.05)))
             (is (null noticed))
             (is (gp-terminal-text-watch)))
           (signals error (gp-watch-terminal-text :interval 0.05))
           (with-open-file (out path :direction :output :if-exists :append)
             (write-line token out))
           (loop repeat 80
                 until (fact-p (list 'automa-gp::terminal-text path token) (gp-facts))
                 do (sleep 0.05))
           (is (fact-p (list 'automa-gp::terminal-text path token) (gp-facts)))
           (is (fact-p '(watched-text up) (gp-facts)))
           (is (equal '((noted-text up)) (gp-goals)))
           (gp-stop-terminal-text-watch)
           (is (not (gp-terminal-text-watch)))
           (gp-add-reaction
            (make-event-reaction :name 'on-later
                                 :when (list 'automa-gp::terminal-text path later)))
           (with-open-file (out path :direction :output :if-exists :append)
             (write-line later out))
           (sleep 0.3)
           (is (not (fact-p (list 'automa-gp::terminal-text path later) (gp-facts))))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :post "/api/watch-terminal-text" "{\"interval\":0.05}")
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search "\"watching\":true" json)))
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :get "/api/status" "")
             (declare (ignore ctype))
             (is (= 200 code))
             (is (search "\"terminal-text-watch\":true" json)))
           (web-api-handle-json :post "/api/watch-terminal-text/stop" "{}")
           (gp-watch-terminal-text :interval 0.05)
           (gp-reset)
           (is (not (gp-terminal-text-watch)))
           (is (not (find "automa-gp-terminal-text-watch"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=))))
      (ignore-errors (delete-file path))
      (when (gp-terminal-text-watch)
        (ignore-errors (gp-stop-terminal-text-watch))))))

(defun %test-slow-read (timeout)
  "A read that takes five seconds unless TIMEOUT or a stop cuts it short.
osascript where it exists, so the Terminal.app read itself is the one cut."
  (if (macos-p)
      (automa-gp::%osascript "delay 5" :timeout timeout)
      (automa-gp::%cancellable-program '("perl" "-e" "sleep 5")
                                       :timeout timeout :output t)))

(test notice-stop-drops-the-read-still-open
  (let ((started (get-internal-real-time)))
    (let ((automa-gp::*notice-halt* (lambda () t)))
      (is (null (%test-slow-read 2))))
    (is (< (/ (- (get-internal-real-time) started)
              internal-time-units-per-second)
           0.5)))
  (let ((box (list nil))
        (started (get-internal-real-time)))
    (let ((setter (sb-thread:make-thread
                   (lambda ()
                     (sleep 0.2)
                     (setf (car box) t))
                   :name "automa-gp-halt-setter")))
      (unwind-protect
           (let ((automa-gp::*notice-halt* (lambda () (car box))))
             (is (null (%test-slow-read 2)))
             (is (< (/ (- (get-internal-real-time) started)
                       internal-time-units-per-second)
                    1.5)))
        (setf (car box) t)
        (ignore-errors (sb-thread:join-thread setter :timeout 1)))))
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (ensure-directories-exist
               (pathname (format nil "/tmp/automa-gp-halt-walk-~D/" (random 1000000)))))
         (path (namestring (merge-pathnames "a-first.txt" dir))))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "a" out))
           (gp-add-reaction
            (make-event-reaction :name 'on-file
                                 :when '(automa-gp::file-created ?path)
                                 :assert '((seen ?path))
                                 :goals '((noted ?path))))
           (let ((automa-gp::*notice-halt* (lambda () t)))
             (is (null (gp-notice-directory (namestring dir))))
             (is (null (gp-facts)))
             (is (null (gp-goals)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test notice-stop-drops-a-process-check-and-a-transcript
  (is (eql 0 (automa-gp::%cancellable-program '("/usr/bin/true"))))
  (is (not (eql 0 (automa-gp::%cancellable-program '("/usr/bin/false")))))
  (let ((box (list nil))
        (started (get-internal-real-time)))
    (let ((setter (sb-thread:make-thread
                   (lambda ()
                     (sleep 0.2)
                     (setf (car box) t))
                   :name "automa-gp-halt-setter")))
      (unwind-protect
           (let ((automa-gp::*notice-halt* (lambda () (car box))))
             (is (null (automa-gp::%cancellable-program
                        '("perl" "-e" "sleep 5"))))
             (is (< (/ (- (get-internal-real-time) started)
                       internal-time-units-per-second)
                    1.5)))
        (setf (car box) t)
        (ignore-errors (sb-thread:join-thread setter :timeout 1)))))
  (let ((path (namestring
               (merge-pathnames "span.txt"
                                (ensure-directories-exist
                                 (pathname (format nil "/tmp/automa-gp-span-~D/"
                                                   (random 1000000))))))))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "xxabcdyy" out))
           (is (automa-gp::%file-contains-p path "abcd" :chunk 3))
           (let ((automa-gp::*notice-halt* (lambda () t)))
             (is (null (automa-gp::%file-contains-p path "abcd" :chunk 3)))))
      (ignore-errors (delete-file path))
      (ignore-errors (uiop:delete-directory-tree
                      (uiop:pathname-directory-pathname path)
                      :validate t :if-does-not-exist :ignore))))
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (ensure-directories-exist
               (pathname (format nil "/tmp/automa-gp-halt-text-~D/" (random 1000000)))))
         (path (namestring (merge-pathnames "transcript.txt" dir))))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "token-is-here" out))
           (gp-add-reaction
            (make-event-reaction :name 'on-text
                                 :when (list 'automa-gp::terminal-text path "token-is-here")
                                 :assert '((transcript heard))
                                 :goals '((noted-text up))))
           (gp-add-reaction
            (make-event-reaction :name 'on-proc
                                 :when (list 'automa-gp::process-running (current-process-id))
                                 :assert '((proc heard))
                                 :goals '((noted-proc up))))
           (let ((automa-gp::*notice-halt* (lambda () t)))
             (is (null (gp-notice-terminal-text)))
             (is (null (gp-notice-processes)))
             (is (null (gp-facts)))
             (is (null (gp-goals)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(defun %test-screen-reaction ()
  "A TERMINAL-SCREEN reaction on a tab no host has."
  (make-event-reaction :name 'on-screen
                       :when '(automa-gp::terminal-screen
                               "ttys99999"
                               "automa-gp-screen-missing")
                       :assert '((screen heard))
                       :goals '((noted-screen up))))

(test terminal-screen-is-refused-where-there-is-no-terminal-app
  ;; MACOS-P reads *FEATURES*, so the refusal is checked on every host.
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction (%test-screen-reaction))
  (let ((*features* (remove :darwin *features*)))
    (is (not (macos-p)))
    (signals notice-refused (gp-notice-terminal-screen))
    (signals notice-refused (gp-watch-terminal-screen :interval 0.2))
    (is (not (gp-terminal-screen-watch)))
    (multiple-value-bind (code body)
        (web-api-handle :post "/api/notice-terminal-screen")
      (is (= 400 code))
      (is (search "only on macOS" (getf body :error)))))
  (is (null (gp-facts)))
  (is (null (gp-events))))

(test notice-terminal-screen-skips-a-tab-that-does-not-answer
  (gp-clear-memory)
  (gp-reset)
  (signals notice-refused (gp-notice-terminal-screen))
  (is (null (gp-facts)))
  (when (macos-p)
    (let ((started (get-internal-real-time)))
      (is (null (automa-gp::%osascript "delay 5" :timeout 1)))
      (is (< (/ (- (get-internal-real-time) started)
                internal-time-units-per-second)
             3)))
    (gp-add-reaction (%test-screen-reaction))
    (gp-add-reaction
     (make-event-reaction :name 'on-bad
                          :when '(automa-gp::terminal-screen
                                  "ttys000; say hi"
                                  "x")))
    (gp-add-fact '(bench clear))
    (gp-listen :reason :manual)
    (let ((before (copy-tree *observed-before*)))
      (let ((noticed (gp-notice-terminal-screen)))
        (is (null noticed))
        (is (not (fact-p '(screen heard) (gp-facts))))
        (is (not (fact-p '(noted-screen up) (gp-goals))))
        (is (equal before *observed-before*))))
    (multiple-value-bind (code ctype json)
        (web-api-handle-json :post "/api/notice-terminal-screen" "{}")
      (declare (ignore ctype))
      (is (= 200 code))
      (is (not (search "automa-gp-screen-missing" json)))
      (is (not (search "say hi" json))))
    (gp-reset)
    (gp-add-reaction
     (make-event-reaction :name 'only-var
                          :when '(automa-gp::terminal-screen ?tty ?text)))
    (signals notice-refused (gp-notice-terminal-screen))
    (gp-reset)
    (gp-add-reaction
     (make-event-reaction :name 'only-bad
                          :when '(automa-gp::terminal-screen "not-a-tty" "x")))
    (signals notice-refused (gp-notice-terminal-screen))
    (is (null (gp-facts)))))

(test watch-terminal-screen-stays-until-stopped
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction (%test-screen-reaction))
  (unwind-protect
       (when (macos-p)
         (let ((noticed (gp-watch-terminal-screen :interval 0.2)))
           (is (null noticed))
           (is (gp-terminal-screen-watch)))
         (signals notice-refused (gp-watch-terminal-screen :interval 0.2))
         (is (not (fact-p '(screen heard) (gp-facts))))
         (gp-stop-terminal-screen-watch)
         (is (not (gp-terminal-screen-watch)))
         (is (not (fact-p '(screen heard) (gp-facts))))
         (multiple-value-bind (code ctype json)
             (web-api-handle-json :post "/api/watch-terminal-screen" "{\"interval\":0.2}")
           (declare (ignore ctype))
           (is (= 200 code))
           (is (search "\"watching\":true" json))
           (is (not (search "automa-gp-screen-missing" json))))
         (multiple-value-bind (code ctype json)
             (web-api-handle-json :get "/api/status" "")
           (declare (ignore ctype))
           (is (= 200 code))
           (is (search "\"terminal-screen-watch\":true" json)))
         (web-api-handle-json :post "/api/watch-terminal-screen/stop" "{}")
         (gp-watch-terminal-screen :interval 0.2)
         (gp-reset)
         (is (not (gp-terminal-screen-watch)))
         (is (not (find "automa-gp-terminal-screen-watch"
                        (sb-thread:list-all-threads)
                        :key #'sb-thread:thread-name
                        :test #'string=))))
    (when (gp-terminal-screen-watch)
      (ignore-errors (gp-stop-terminal-screen-watch)))))

(test notice-watches-of-different-kinds-stay-separate
  (gp-clear-memory)
  (gp-reset)
  (signals error (gp-watch-processes :interval 0))
  (is (not (gp-process-watch)))
  (signals error (gp-watch-processes :interval 0.2))
  (is (not (gp-process-watch)))
  (let* ((dir (ensure-directories-exist
               (pathname (format nil "/tmp/automa-gp-watches-~D/" (random 1000000)))))
         (path (namestring (merge-pathnames "transcript.txt" dir))))
    (unwind-protect
         (progn
           (with-open-file (out path :direction :output :if-exists :supersede)
             (write-string "" out))
           (gp-add-reaction
            (make-event-reaction :name 'on-proc
                                 :when '(automa-gp::process-running
                                         "automa-gp-no-such-process")))
           (gp-add-reaction
            (make-event-reaction :name 'on-text
                                 :when (list 'automa-gp::terminal-text path
                                             "automa-gp-absent-line")))
           (is (null (gp-watch-processes :interval 0.2)))
           (is (null (gp-watch-terminal-text :interval 0.2)))
           (is (gp-process-watch))
           (is (gp-terminal-text-watch))
           (signals error (gp-watch-processes :interval 0.2))
           (is (gp-terminal-text-watch))
           (gp-stop-process-watch)
           (is (not (gp-process-watch)))
           (is (gp-terminal-text-watch))
           (is (not (fact-p '(automa-gp::process-running "automa-gp-no-such-process")
                            (gp-facts))))
           (gp-reset)
           (is (not (gp-terminal-text-watch)))
           (is (not (find "automa-gp-process-watch"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=)))
           (is (not (find "automa-gp-terminal-text-watch"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=))))
      (when (gp-process-watch)
        (ignore-errors (gp-stop-process-watch)))
      (when (gp-terminal-text-watch)
        (ignore-errors (gp-stop-terminal-text-watch)))
      (ignore-errors (delete-file path))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(defvar *notice-watch-probe* nil)

(defvar *notice-watch-probe-lock* (sb-thread:make-mutex :name "automa-gp-notice-watch-probe"))

(test notice-watch-is-reserved-before-the-first-look
  (let ((lock *notice-watch-probe-lock*))
    (unwind-protect
         (progn
           (setf *notice-watch-probe* nil)
           (let ((saw-busy nil))
             (is (equal '(:seen)
                        (automa-gp::%begin-notice-watch
                         '*notice-watch-probe* lock 0.05
                         "automa-gp-notice-watch-probe" "busy"
                         (lambda ()
                           (handler-case
                               (automa-gp::%begin-notice-watch
                                '*notice-watch-probe* lock 0.05
                                "automa-gp-notice-watch-probe" "busy"
                                (lambda () (values nil (lambda () nil) nil)))
                             (error (condition)
                               (setf saw-busy
                                     (search "busy" (princ-to-string condition)))))
                           (values '(:seen) (lambda () '(:seen)) nil)))))
             (is (not (null saw-busy))))
           (is (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock))
           (automa-gp::%end-notice-watch '*notice-watch-probe* lock "absent")
           (is (not (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)))
           (is (equal '(:seen)
                      (automa-gp::%begin-notice-watch
                       '*notice-watch-probe* lock 0.05
                       "automa-gp-notice-watch-probe" "busy"
                       (lambda ()
                         (automa-gp::%end-notice-watch
                          '*notice-watch-probe* lock "absent")
                         (values '(:seen) (lambda () '(:seen)) "label")))))
           (is (not (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)))
           (is (not (find "automa-gp-notice-watch-probe"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=)))
           (signals error
             (automa-gp::%begin-notice-watch
              '*notice-watch-probe* lock 0.05
              "automa-gp-notice-watch-probe" "busy"
              (lambda () (error "look failed"))))
           (is (not (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock))))
      (when (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)
        (ignore-errors
         (automa-gp::%end-notice-watch '*notice-watch-probe* lock "absent"))))))

(test notice-stops-before-the-next-file
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (ensure-directories-exist
               (pathname (format nil "/tmp/automa-gp-halt-~D/" (random 1000000)))))
         (first (namestring (merge-pathnames "a-first.txt" dir)))
         (second (namestring (merge-pathnames "b-second.txt" dir))))
    (unwind-protect
         (progn
           (with-open-file (out first :direction :output :if-exists :supersede)
             (write-string "a" out))
           (with-open-file (out second :direction :output :if-exists :supersede)
             (write-string "b" out))
           (gp-add-reaction
            (make-event-reaction :name 'on-file
                                 :when '(automa-gp::file-created ?path)
                                 :assert '((seen ?path))
                                 :goals '((noted ?path))))
           (let ((automa-gp::*notice-halt*
                  (lambda ()
                    (find 'automa-gp::file-created (gp-facts) :key #'car))))
             (let ((noticed (gp-notice-directory (namestring dir))))
               (is (= 1 (length noticed)))
               (is (search "a-first.txt" (second (first noticed))))
               (is (= 1 (count 'automa-gp::file-created (gp-facts) :key #'car)))
               (is (= 1 (count 'seen (gp-facts) :key #'car)))
               (is (= 1 (length (gp-goals))))
               (is (not (find "b-second.txt" (gp-facts)
                              :test (lambda (text fact)
                                      (and (consp fact)
                                           (some (lambda (term)
                                                   (and (stringp term)
                                                        (search text term)))
                                                 fact))))))))
           (let ((noticed (gp-notice-directory (namestring dir))))
             (is (= 2 (length noticed)))
             (is (find "b-second.txt" noticed
                       :test (lambda (text fact)
                               (and (consp fact)
                                    (some (lambda (term)
                                            (and (stringp term)
                                                 (search text term)))
                                          fact)))))
             (is (= 2 (length (gp-goals))))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test notice-watch-stop-is-visible-during-the-look
  (let ((lock *notice-watch-probe-lock*))
    (unwind-protect
         (progn
           (setf *notice-watch-probe* nil)
           (is (equal '(nil t)
                      (automa-gp::%begin-notice-watch
                       '*notice-watch-probe* lock 0.05
                       "automa-gp-notice-watch-probe" "busy"
                       (lambda ()
                         (let ((before (automa-gp::%notice-halted-p)))
                           (automa-gp::%end-notice-watch
                            '*notice-watch-probe* lock "absent")
                           (values (list before (automa-gp::%notice-halted-p))
                                   (lambda () nil)
                                   nil))))))
           (is (not (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)))
           (is (not (find "automa-gp-notice-watch-probe"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=))))
      (when (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)
        (ignore-errors
         (automa-gp::%end-notice-watch '*notice-watch-probe* lock "absent"))))))

;;; Regressions from the engineering pass.

(defmacro with-notice-directory ((dir) &body body)
  "Run BODY with DIR bound to a fresh, empty temporary directory."
  `(let ((,dir (ensure-directories-exist
                (uiop:ensure-directory-pathname
                 (merge-pathnames
                  (format nil "automa-gp-notice-~D-~D/"
                          (get-universal-time) (random 1000000))
                  (uiop:temporary-directory))))))
     (unwind-protect
          (progn ,@body)
       (uiop:delete-directory-tree ,dir :validate t
                                        :if-does-not-exist :ignore))))

(defun %test-file-reaction ()
  "A FILE-CREATED reaction that asserts (SEEN path) and wants (FILED path)."
  (make-event-reaction :name 'on-file
                       :when '(automa-gp::file-created ?path)
                       :assert '((seen ?path))
                       :goals '((filed ?path))))

(defun %test-lowest-free-descriptor ()
  "The file descriptor the next open in this image would get."
  (let ((descriptor (sb-posix:open "/dev/null" sb-posix:o-rdonly)))
    (sb-posix:close descriptor)
    descriptor))

(test notice-command-closes-its-pipe-on-every-way-out
  (let ((before (%test-lowest-free-descriptor)))
    (is (every (lambda (text) (equal "hi" (string-right-trim '(#\Newline) text)))
               (loop repeat 12
                     collect (automa-gp::%cancellable-program '("echo" "hi")
                                                              :output t))))
    (is (<= (%test-lowest-free-descriptor) before))
    ;; A read cut short by its timeout, and one cut short by a stop.
    (is (every #'null
               (loop repeat 3
                     collect (automa-gp::%cancellable-program
                              '("perl" "-e" "$| = 1; print 'x'; sleep 5")
                              :timeout 0.2 :output t))))
    (let ((looks 0))
      (let ((automa-gp::*notice-halt* (lambda () (> (incf looks) 2))))
        (is (null (automa-gp::%cancellable-program '("perl" "-e" "sleep 5")
                                                   :output t)))))
    (is (<= (%test-lowest-free-descriptor) before))
    (is (not (find "automa-gp-command-read" (sb-thread:list-all-threads)
                   :key #'sb-thread:thread-name :test #'string=))))
  ;; A program that cannot be started is an error, not an empty answer.
  (signals error
    (automa-gp::%cancellable-program '("automa-gp-no-such-program-xyzzy")))
  (signals error
    (automa-gp::%cancellable-program '("automa-gp-no-such-program-xyzzy")
                                     :output t)))

(test notice-processes-pid-names-one-process
  (dolist (pid '(0 -1 -4242))
    (is (null (automa-gp::%process-target pid)))
    (is (null (automa-gp::%notice-process-running-p pid))))
  (is-true (automa-gp::%notice-process-running-p (current-process-id)))
  (is-true (automa-gp::%notice-process-running-p (sb-posix:getppid)))
  (is (null (automa-gp::%notice-process-running-p (expt 10 12))))
  ;; Pid 1 belongs to another user: it runs although it cannot be signalled.
  (when (eql 0 (nth-value 2 (uiop:run-program '("ps" "-p" "1" "-o" "pid=")
                                              :ignore-error-status t)))
    (is-true (automa-gp::%notice-process-running-p 1)))
  (gp-clear-memory)
  (gp-reset)
  (dolist (pid '(0 -1))
    (gp-add-reaction
     (make-event-reaction :name (list 'on-group pid)
                          :when (list 'automa-gp::process-running pid)
                          :assert '((group heard)))))
  (signals notice-refused (gp-notice-processes))
  (is (null (gp-facts)))
  (is (null (gp-events))))

(test notice-processes-name-is-literal-text
  (let ((self (current-process-id))
        (other (1+ (current-process-id)))
        (listing automa-gp::*process-listing*))
    (loop for (name pid command expected)
            in `(("nginx" ,other "nginx: worker process" t)
                 ("nginx" ,other "/usr/sbin/nginx -g daemon off;" t)
                 ("ngin.x" ,other "/usr/sbin/nginx -g daemon off;" nil)
                 ("." ,other "nginx" nil)
                 ("ps" ,other ,listing nil)
                 ("pid= -o command=" ,other ,listing nil)
                 ("nginx" ,self "sbcl --eval (watch \"nginx\")" nil)
                 ("sbcl" ,self "sbcl --eval (watch \"nginx\")" t)
                 ("sbcl" ,self "/usr/local/bin/sbcl --eval x" t)
                 ("/usr/local/bin/sbcl" ,self "/usr/local/bin/sbcl" t)
                 ("bin/sbcl" ,self "/usr/local/bin/sbcl --eval x" nil))
          do (is (eq expected
                     (and (automa-gp::%command-names-p name pid command) t))
                 "~S on ~S should be ~S" name command expected))
    (is (equal (list 42 "perl -e sleep 60")
               (multiple-value-list
                (automa-gp::%process-line "   42 perl -e sleep 60"))))
    (is (null (automa-gp::%process-line "")))
    (is (null (automa-gp::%process-line "COMMAND"))))
  (let* ((token (format nil "automa-gp-lit-~D-~D"
                        (get-universal-time) (random 100000)))
         (process (uiop:launch-program
                   (list "perl" "-e" (format nil "sleep 60; # ~A" token))
                   :output #P"/dev/null" :error-output #P"/dev/null")))
    (unwind-protect
         (progn
           (loop repeat 80
                 until (automa-gp::%notice-process-running-p token)
                 do (sleep 0.05))
           (is-true (automa-gp::%notice-process-running-p token))
           ;; Each dot would match the hyphen it replaces in a pattern.
           (is (null (automa-gp::%notice-process-running-p
                      (substitute #\. #\- token))))
           ;; Only the ps that lists the processes carries these.
           (is (null (automa-gp::%notice-process-running-p "pid= -o command=")))
           (is (null (automa-gp::%notice-process-running-p "-o command=")))
           (is-true (automa-gp::%notice-process-running-p
                     (file-namestring sb-ext:*runtime-pathname*))))
      (ignore-errors (uiop:terminate-process process :urgent t))
      (ignore-errors (uiop:wait-process process)))))

(test notice-terminal-text-reads-past-bytes-that-are-not-utf-8
  (gp-clear-memory)
  (gp-reset)
  (with-notice-directory (dir)
    (let ((path (namestring (merge-pathnames "transcript.bin" dir))))
      (with-open-file (out path :direction :output
                                :element-type '(unsigned-byte 8))
        (write-sequence #(255 254 27 91) out)
        (write-sequence (map 'vector #'char-code "MARKER here") out)
        (write-sequence #(10 255) out))
      (gp-add-reaction
       (make-event-reaction :name 'on-marker
                            :when (list 'automa-gp::terminal-text path "MARKER here")
                            :assert '((marker heard))))
      (is (equal (list (list 'automa-gp::terminal-text path "MARKER here"))
                 (gp-notice-terminal-text)))
      (is (fact-p '(marker heard) (gp-facts)))
      ;; A transcript that is not there yet is absent, not an error.
      (gp-add-reaction
       (make-event-reaction :name 'on-later
                            :when (list 'automa-gp::terminal-text
                                        (namestring (merge-pathnames "later" dir))
                                        "x")))
      (is (= 1 (length (gp-notice-terminal-text)))))))

(test notice-directory-reacts-a-file-notice-path-recorded
  (gp-clear-memory)
  (gp-reset)
  (with-notice-directory (dir)
    (let ((path (namestring (merge-pathnames "report.txt" dir))))
      (adapter-write-file-string path "x")
      (gp-add-reaction (%test-file-reaction))
      (let ((fact (gp-notice-path path)))
        (is (equal (list fact) (gp-facts)))
        (is (= 1 (length (gp-events :status :pending))))
        (is (null (gp-goals)))
        (is (equal (list fact) (gp-notice-directory (namestring dir))))
        (is (fact-p (list 'seen path) (gp-facts)))
        (is (equal (list (list 'filed path)) (gp-goals)))
        (is (= 1 (length (gp-events))))
        (is (null (gp-events :status :pending)))
        ;; Neither entry point records or reacts the file a second time.
        (gp-notice-path path)
        (gp-notice-directory (namestring dir))
        (is (= 1 (length (gp-events))))
        (is (= 2 (length (gp-facts))))
        (is (= 1 (length (gp-goals))))))))

(test notice-leaves-working-memory-and-last-reaction-current
  (gp-clear-memory)
  (gp-reset)
  (with-notice-directory (dir)
    (let ((path (namestring (merge-pathnames "report.txt" dir))))
      (adapter-write-file-string path "x")
      (gp-add-reaction (%test-file-reaction))
      (gp-notice-path path)
      (is (equal (gp-facts) (working-memory-facts *working-memory*)))
      (is (null (gp-last-reaction)))
      (gp-notice-directory (namestring dir))
      (is (equal (gp-facts) (working-memory-facts *working-memory*)))
      (is (equal (gp-goals) (working-memory-goals *working-memory*)))
      (let ((reaction (gp-last-reaction)))
        (is (= 1 (getf reaction :processed)))
        (is (equal '(on-file) (getf reaction :matched)))
        (is (equal (list (list 'seen path)) (getf reaction :facts-added)))
        (is (equal (list (list 'filed path)) (getf reaction :goals-added))))
      (multiple-value-bind (code body) (web-api-handle :get "/api/reaction")
        (is (= 200 code))
        (is (getf body :reaction))))))

(test notice-takes-a-name-as-the-system-knows-it
  ;; A pathname reads [ ] * and ? as a pattern. In these names they are
  ;; plain characters.
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction (%test-file-reaction))
  (flet ((native (directory name)
           (concatenate 'string (sb-ext:native-namestring directory) name)))
    (with-notice-directory (outside)
      (adapter-write-file-string (native outside "secret.txt") "outside")
      (dolist (name '("linked" "link[1]" "li*nk" "link?"))
        (with-notice-directory (dir)
          (sb-posix:symlink (sb-ext:native-namestring outside :as-file t)
                            (native dir name))
          (is (null (gp-notice-directory dir))
              "The walk entered the linked directory ~S." name)))
      (is (null (gp-facts)))
      ;; A directory of that kind that is no link is entered.
      (with-notice-directory (dir)
        (sb-posix:mkdir (native dir "real[1]") #o700)
        (with-open-file (out (sb-ext:parse-native-namestring
                              (native dir "real[1]/inside.txt"))
                             :direction :output)
          (write-string "inside" out))
        (let ((noticed (gp-notice-directory dir)))
          (is (= 1 (length noticed)))
          (is (search "inside.txt" (second (first noticed)))))))
    (gp-reset)
    (with-notice-directory (dir)
      (let ((path (native dir "typescript[1].log")))
        (with-open-file (out (sb-ext:parse-native-namestring path)
                             :direction :output)
          (write-string "MARKER here" out))
        (gp-add-reaction
         (make-event-reaction :name 'on-marker
                              :when (list 'automa-gp::terminal-text path
                                          "MARKER"))))
      (is (= 1 (length (gp-notice-terminal-text)))))))
