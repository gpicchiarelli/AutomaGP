;;;; tests/test-autonomy.lisp — Phase 12 controlled autonomous operation

(in-package #:automa-gp/tests)

(def-suite autonomy-suite :in automa-gp-suite)
(in-suite autonomy-suite)

(defun %auto-studio ()
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
  (gp-add-goal '(connection interface-01 computer))
  (gp-context))

(test autonomy-read-observes-without-planning
  (%auto-studio)
  (let ((before (copy-tree (gp-facts)))
        (summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :read))))
    (is (eq :halted (getf summary :status)))
    (is (eq :authority-read (getf summary :halt)))
    (is (equal before (gp-facts)))
    (is (null (getf summary :plan)))
    (is (eq summary (gp-last-autonomy)))))

(test autonomy-simulate-achieves-without-mutating
  (%auto-studio)
  (let ((before (copy-tree (gp-facts)))
        (summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :simulate
                                                :learn t))))
    (is (eq :done (getf summary :status)))
    (is (eq :completed (getf summary :halt)))
    (is (eq :simulate (getf summary :authority)))
    (is (equal before (gp-facts)))
    (is-false (fact-p '(connection interface-01 computer) (gp-facts)))
    (is (getf (getf summary :plan) :success))
    (is (= 2 (getf (getf summary :plan) :length)))
    (is (getf (getf summary :execution) :success))
    (is (eq :simulate (getf (getf summary :execution) :mode)))
    (is-false (fact-p '(connection interface-01 computer)
                      (knowledge-memory-facts (ensure-knowledge-memory))))))

(test autonomy-execute-mutates-and-learns
  (%auto-studio)
  (let ((summary (gp-autonomous-loop
                  :policy (make-autonomy-policy :authority :execute
                                                :learn t
                                                :auto-confirm t))))
    (is (eq :done (getf summary :status)))
    (is (= 1 (getf summary :iterations)))
    (is-true (fact-p '(connection interface-01 computer) (gp-facts)))
    (is-true (fact-p '(power-state interface-01 on) (gp-facts)))
    (is-true (fact-p '(connection interface-01 computer)
                     (knowledge-memory-facts (ensure-knowledge-memory))))))

(test autonomy-execute-halts-without-confirmation
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(ready x))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((ready x))
                  :add-list '((sealed x))
                  :reversible nil
                  :risk :high))
  (gp-add-goal '(sealed x))
  (let ((summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :execute
                                                :auto-confirm nil))))
    (is (eq :halted (getf summary :status)))
    (is (eq :confirmation-required (getf summary :halt)))
    (is-false (fact-p '(sealed x) (gp-facts))))
  (let ((summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :execute
                                                :auto-confirm t
                                                :learn t))))
    (is (eq :done (getf summary :status)))
    (is-true (fact-p '(sealed x) (gp-facts)))))

(test autonomy-no-goals-and-impossible-plan-halt
  (gp-clear-memory)
  (gp-reset)
  (let ((summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :simulate))))
    (is (eq :halted (getf summary :status)))
    (is (eq :no-goals (getf summary :halt))))
  (gp-add-goal '(missing thing))
  (let ((summary (gp-autonomous-loop
                  :policy (make-autonomy-policy :authority :simulate
                                                :max-steps 4)
                  :max-steps 4)))
    (is (eq :halted (getf summary :status)))
    (is (eq :plan-failed (getf summary :halt)))
    (is (= 1 (getf summary :iterations)))))

(test autonomy-reacts-to-pending-document-event
  (gp-clear-memory)
  (gp-reset)
  (gp-load-domain :documents :seed-demo t)
  (gp-emit '(automa-gp::file-created "brief.pdf"))
  (is (= 1 (length (pending-events (gp-context)))))
  (let ((summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :simulate
                                                :react-events t))))
    (is (eq :done (getf summary :status)))
    (is (null (pending-events (gp-context))))
    (is-true (fact-p '(automa-gp::document-source "brief.pdf") (gp-facts)))
    (is-false (fact-p '(automa-gp::document-classified "brief.pdf"
                                                       automa-gp::report)
                      (gp-facts)))
    (is (getf (getf summary :plan) :success))))

(test web-api-autonomy-step
  (%auto-studio)
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/autonomy")
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (is (eq :simulate (getf (getf body :policy) :authority))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/autonomy/step"
                      '(:authority "simulate"))
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (is (eq :done (getf (getf body :autonomy) :status)))
    (is-false (fact-p '(connection interface-01 computer) (gp-facts))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/autonomy/step"
                      '(:authority "execute"
                        :adapters t
                        :auto-confirm t))
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (let ((autonomy (getf body :autonomy)))
      (is (member (getf autonomy :status) '(:done :halted :continue) :test #'eq))
      (is (eq :execute (getf autonomy :authority)))))
  (%auto-studio)
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/autonomy/loop"
                      '(:authority "simulate" :max-steps 3))
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (let ((autonomy (getf body :autonomy)))
      (is (eq :done (getf autonomy :status)))
      (is (eq :completed (getf autonomy :halt)))
      (is (= 1 (getf autonomy :iterations)))
      (is (eq :simulate (getf autonomy :authority))))
    (is-false (fact-p '(connection interface-01 computer) (gp-facts))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/autonomy")
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (let ((last (getf body :last)))
      (is (listp last))
      (is (eq :done (getf last :status)))
      (is (eq :completed (getf last :halt)))
      (is (= 1 (getf last :iterations)))
      (is (eq :simulate (getf last :authority)))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/autonomy/policy" '(:max-steps 3))
    (is (= 200 code))
    (is (= 3 (getf (getf body :policy) :max-steps))))
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/autonomy")
    (is (= 200 code))
    (is (= 3 (getf (getf body :policy) :max-steps))))
  (%auto-studio)
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/autonomy/loop" '(:authority "simulate"))
    (is (= 200 code))
    (is (eq t (getf body :ok)))
    (is (eq :done (getf (getf body :autonomy) :status)))
    (is (= 1 (getf (getf body :autonomy) :iterations))))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/autonomy/policy" '(:max-steps 8))
    (is (= 200 code))
    (is (= 8 (getf (getf body :policy) :max-steps)))))

(test autonomy-halts-when-the-external-action-is-refused
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-auto-halt-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker))
         (policy (make-autonomy-policy :authority :execute
                                       :adapters t
                                       :auto-confirm t
                                       :learn nil
                                       :prefer-archive nil)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-fact (list 'seen path))
           (gp-add-goal (list 'noted path))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((seen ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (unwind-protect
                (progn
                  (sb-impl::encapsulate
                   'record-plan-episode! 'drop-support
                   (lambda (next &rest args)
                     (prog1 (apply next args)
                       (gp-remove-fact (list 'seen path)))))
                  (let ((summary (gp-autonomous-loop :policy policy :max-steps 3)))
                    (is (eq :halted (getf summary :status)))
                    (is (eq :external-unsupported (getf summary :halt)))
                    (is (= 1 (getf summary :iterations)))
                    (is (eq :plan (context-mode (gp-context))))
                    (is (null (gp-last-execution)))
                    (is-false (file-exists-p marker))
                    (is (not (fact-p (list 'noted path) (gp-facts))))))
             (sb-impl::unencapsulate 'record-plan-episode! 'drop-support))
           (gp-add-fact (list 'seen path))
           (let ((sim (make-autonomy-policy :authority :simulate
                                            :learn nil
                                            :prefer-archive nil)))
             (unwind-protect
                  (progn
                    (sb-impl::encapsulate
                     'record-plan-episode! 'drop-support-sim
                     (lambda (next &rest args)
                       (prog1 (apply next args)
                         (gp-remove-fact (list 'seen path)))))
                    (let ((summary (gp-autonomous-step :policy sim)))
                      (is (eq :halted (getf summary :status)))
                      (is (eq :external-unsupported (getf summary :halt)))
                      (is (eq :plan (context-mode (gp-context))))
                      (is (null (getf summary :execution)))
                      (is (not (fact-p (list 'noted path) (gp-facts))))
                      (is-false (file-exists-p marker))))
               (sb-impl::unencapsulate 'record-plan-episode! 'drop-support-sim)))
           (gp-add-fact (list 'seen path))
           (unwind-protect
                (progn
                  (sb-impl::encapsulate
                   'record-plan-episode! 'change-spec
                   (lambda (next &rest args)
                     (prog1 (apply next args)
                       (setf (operator-meta
                              (find-operator (gp-context) 'note-file))
                             (list :external
                                   (list :adapter :filesystem
                                         :op :write-string
                                         :args (list :path '?path
                                                     :content "changed")))))))
                  (let ((summary (gp-autonomous-step :policy policy)))
                    (is (eq :halted (getf summary :status)))
                    (is (eq :external-mismatch (getf summary :halt)))
                    (is (eq :plan (context-mode (gp-context))))
                    (is (null (getf summary :execution)))
                    (is-false (file-exists-p marker))))
             (sb-impl::unencapsulate 'record-plan-episode! 'change-spec))
           (let ((quiet (make-autonomy-policy :authority :execute
                                              :adapters nil
                                              :auto-confirm t
                                              :learn nil
                                              :prefer-archive nil)))
             (unwind-protect
                  (progn
                    (sb-impl::encapsulate
                     'record-plan-episode! 'change-again
                     (lambda (next &rest args)
                       (prog1 (apply next args)
                         (setf (operator-meta
                                (find-operator (gp-context) 'note-file))
                               (list :external
                                     (list :adapter :filesystem
                                           :op :write-string
                                           :args (list :path '?path
                                                       :content "other")))))))
                    (let ((summary (gp-autonomous-step :policy quiet)))
                      (is (eq :halted (getf summary :status)))
                      (is (eq :external-mismatch (getf summary :halt)))
                      (is (eq :plan (context-mode (gp-context))))
                      (is (null (getf summary :execution)))
                      (is (not (fact-p (list 'noted path) (gp-facts))))
                      (is-false (file-exists-p marker))))
               (sb-impl::unencapsulate 'record-plan-episode! 'change-again)))
           (let ((sim (make-autonomy-policy :authority :simulate
                                            :learn nil
                                            :prefer-archive nil)))
             (unwind-protect
                  (progn
                    (sb-impl::encapsulate
                     'record-plan-episode! 'change-for-sim
                     (lambda (next &rest args)
                       (prog1 (apply next args)
                         (setf (operator-meta
                                (find-operator (gp-context) 'note-file))
                               (list :external
                                     (list :adapter :filesystem
                                           :op :write-string
                                           :args (list :path '?path
                                                       :content "simulated")))))))
                    (let ((summary (gp-autonomous-step :policy sim)))
                      (is (eq :halted (getf summary :status)))
                      (is (eq :external-mismatch (getf summary :halt)))
                      (is (eq :plan (context-mode (gp-context))))
                      (is (null (getf summary :execution)))
                      (is (not (fact-p (list 'noted path) (gp-facts))))
                      (is-false (file-exists-p marker))))
               (sb-impl::unencapsulate 'record-plan-episode! 'change-for-sim)))
           (setf (operator-meta (find-operator (gp-context) 'note-file))
                 (list :external
                       (list :adapter :filesystem
                             :op :write-string
                             :args (list :path '?path
                                         :content "changed"))))
           (let ((summary (gp-autonomous-step :policy policy)))
             (is (eq :done (getf summary :status)))
             (is (eq :execute (context-mode (gp-context))))
             (is (equal "changed" (adapter-read-file-string marker)))))
      (gp-clear-memory)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))
