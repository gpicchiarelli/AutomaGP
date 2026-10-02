;;;; tests/test-notice-watch.lisp — what a running watch owes its session
;;;;
;;;; A stop that does not wait, a failing look that can be seen, the
;;;; context a watch keeps, and writes that never interleave. The fixtures
;;;; WITH-NOTICE-DIRECTORY and %TEST-FILE-REACTION are in test-notice.lisp.

(in-package #:automa-gp/tests)

(def-suite notice-watch-suite :in automa-gp-suite)
(in-suite notice-watch-suite)

(defmacro %await (form)
  "Evaluate FORM every 50 ms, for five seconds at most, until it is true."
  `(loop repeat 100
         until ,form
         do (sleep 0.05)))

(defmacro %seconds (&body body)
  "Run BODY and return the seconds it took."
  `(let ((start (get-internal-real-time)))
     ,@body
     (/ (- (get-internal-real-time) start) internal-time-units-per-second)))

(defun %watch-thread-names ()
  "Names of the watch threads still alive."
  (loop for thread in (sb-thread:list-all-threads)
        for name = (sb-thread:thread-name thread)
        when (and (stringp name)
                  (search "automa-gp-" name)
                  (search "-watch" name))
          collect name))

(test watch-stop-does-not-wait-for-the-interval
  (gp-clear-memory)
  (gp-reset)
  (with-notice-directory (dir)
    (gp-add-reaction (%test-file-reaction))
    (gp-add-reaction
     (make-event-reaction :name 'on-process
                          :when '(automa-gp::process-running
                                  "automa-gp-no-such-process")))
    (unwind-protect
         (progn
           (gp-watch-directory (namestring dir) :interval 30)
           (gp-watch-processes :interval 30)
           ;; Both threads are waiting for their second look.
           (sleep 0.3)
           (is (< (%seconds (gp-stop-directory-watch)) 2))
           (is (null (gp-directory-watch)))
           (is (gp-process-watch))
           (gp-watch-directory (namestring dir) :interval 30)
           (is (< (%seconds (gp-reset)) 2))
           (is (null (gp-directory-watch)))
           (is (not (gp-process-watch)))
           (is (null (%watch-thread-names))))
      (automa-gp::%stop-notice-watches))))

(test watch-reports-a-look-that-fails-until-one-succeeds
  (gp-clear-memory)
  (gp-reset)
  (is (null (gp-watch-failures)))
  (with-notice-directory (root)
    (let* ((dir (merge-pathnames "inbox/" root))
           (path (namestring (merge-pathnames "a.txt" dir)))
           (fact (list 'automa-gp::file-created path)))
      (flet ((failed-looks ()
               (getf (first (gp-watch-failures)) :failed-looks 0)))
        (gp-add-reaction (%test-file-reaction))
        (adapter-write-file-string path "a")
        (unwind-protect
             (progn
               (is (equal (list fact)
                          (gp-watch-directory (namestring dir) :interval 0.05)))
               (sleep 0.2)
               (is (null (gp-watch-failures)))
               (uiop:delete-directory-tree dir :validate t)
               (%await (gp-watch-failures))
               (let ((failures (gp-watch-failures)))
                 (is (= 1 (length failures)))
                 (is (eq :directory-watch (getf (first failures) :watch)))
                 (is (plusp (getf (first failures) :failed-looks)))
                 (is (search "not on disk" (getf (first failures) :error))))
               ;; Every further look that fails is counted.
               (let ((count (failed-looks)))
                 (%await (> (failed-looks) count))
                 (is (> (failed-looks) count)))
               ;; The watch is still there, and a look that works clears it.
               (is (search "inbox" (gp-directory-watch)))
               (adapter-write-file-string path "a")
               (%await (null (gp-watch-failures)))
               (is (null (gp-watch-failures)))
               ;; A stop while it fails returns the facts of the last good look.
               (uiop:delete-directory-tree dir :validate t)
               (%await (gp-watch-failures))
               (is (plusp (failed-looks)))
               (is (equal (list fact) (gp-stop-directory-watch)))
               (is (null (gp-watch-failures))))
          (automa-gp::%stop-notice-watches))))))

(test watch-keeps-the-context-it-was-started-on
  (gp-clear-memory)
  (gp-reset)
  (with-notice-directory (dir)
    (let ((home (gp-context))
          (path (namestring (merge-pathnames "later.txt" dir))))
      (gp-add-reaction (%test-file-reaction))
      (unwind-protect
           (progn
             (is (null (gp-watch-directory (namestring dir) :interval 0.05)))
             (let ((elsewhere (gp-context :name 'elsewhere)))
               (adapter-write-file-string path "later")
               (%await (fact-p (list 'seen path) (context-facts home)))
               (is (fact-p (list 'automa-gp::file-created path)
                           (context-facts home)))
               (is (fact-p (list 'seen path) (context-facts home)))
               (is (equal (list (list 'filed path)) (context-goals home)))
               (is (null (gp-watch-failures)))
               ;; The current context, and what describes it, are left alone.
               (is (eq elsewhere (gp-context)))
               (is (null (gp-facts)))
               (is (null (gp-events)))
               (is (null (gp-goals)))
               (is (eq 'elsewhere
                       (working-memory-context-name *working-memory*)))
               (is (null (working-memory-facts *working-memory*)))
               (is (null (gp-last-reaction)))))
        (automa-gp::%stop-notice-watches)))))

(test notices-entering-one-context-do-not-interleave
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction (%test-file-reaction))
  (let* ((writers 6)
         (each 100)
         (total (* writers each))
         (threads (loop for writer below writers
                        collect (let ((writer writer))
                                  (sb-thread:make-thread
                                   (lambda ()
                                     (dotimes (i each)
                                       (automa-gp::%accept-notice
                                        (list 'automa-gp::file-created
                                              (format nil "f-~D-~D" writer i)))))
                                   :name "automa-gp-notice-writer")))))
    (mapc #'sb-thread:join-thread threads)
    (is (= total (count 'automa-gp::file-created (gp-facts) :key #'car)))
    (is (= total (count 'seen (gp-facts) :key #'car)))
    (is (= total (length (gp-events))))
    (is (null (gp-events :status :pending)))
    (is (= total (length (gp-goals))))
    (is (equal (gp-facts) (working-memory-facts *working-memory*)))))

(test watch-refusals-are-notice-refused
  (gp-clear-memory)
  (gp-reset)
  (dolist (stop (list #'gp-stop-directory-watch #'gp-stop-process-watch
                      #'gp-stop-terminal-watch #'gp-stop-terminal-text-watch
                      #'gp-stop-terminal-screen-watch))
    (signals notice-refused (funcall stop)))
  (is (null (automa-gp::%stop-notice-watches)))
  (dolist (interval '(0 -1 nil "1"))
    (signals notice-refused (gp-watch-directory "/tmp/" :interval interval))
    (signals notice-refused (gp-watch-processes :interval interval))
    (signals notice-refused (gp-watch-terminals :interval interval))
    (signals notice-refused (gp-watch-terminal-text :interval interval))
    (signals notice-refused (gp-watch-terminal-screen :interval interval)))
  (dolist (path '(42 nil "" "   "))
    (signals notice-refused (gp-notice-path path))
    (signals notice-refused (gp-notice-directory path))
    (signals notice-refused (gp-watch-directory path :interval 0.05)))
  (is (null (gp-directory-watch)))
  (is (null (gp-watch-failures)))
  (is (null (%watch-thread-names)))
  (let ((condition (nth-value 1 (ignore-errors
                                 (gp-notice-path
                                  "/tmp/automa-gp-notice-missing-file")))))
    (is (typep condition 'notice-refused))
    (is (typep condition 'gp-error))
    (is (search "not on disk" (notice-refused-reason condition)))
    (is (string= (notice-refused-reason condition)
                 (princ-to-string condition))))
  (is (null (gp-facts)))
  (is (null (gp-events))))

(test watch-stop-ends-a-look-that-does-not-see-the-stop
  (let ((lock *notice-watch-probe-lock*)
        (looks 0))
    (setf *notice-watch-probe* nil)
    (unwind-protect
         (progn
           (automa-gp::%begin-notice-watch
            '*notice-watch-probe* lock 0.05
            "automa-gp-notice-watch-probe" "busy"
            (lambda ()
              (values '(:first)
                      (lambda () (incf looks) (sleep 30) '(:late))
                      nil))
            :join-slack 0.2)
           (%await (plusp looks))
           (is (= 1 looks))
           (let (noticed)
             (is (< (%seconds
                      (setf noticed (automa-gp::%end-notice-watch
                                     '*notice-watch-probe* lock "absent")))
                    3))
             (is (equal '(:first) noticed)))
           (is (not (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)))
           (is (not (find "automa-gp-notice-watch-probe"
                          (sb-thread:list-all-threads)
                          :key #'sb-thread:thread-name
                          :test #'string=))))
      (when (automa-gp::%notice-watch-active-p '*notice-watch-probe* lock)
        (ignore-errors
         (automa-gp::%end-notice-watch '*notice-watch-probe* lock "absent"))))))
