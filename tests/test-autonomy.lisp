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
  (signals error (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :simulate)))
  (signals error (gp-autonomous-loop
                  :policy (make-autonomy-policy :authority :simulate
                                                :max-steps 2)
                  :max-steps 2))
  (let ((summary (autonomous-step
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

(test autonomy-refuses-when-goals-already-hold
  (gp-clear-memory)
  (gp-reset)
  (gp-add-goal '(power-state interface-01 on))
  (gp-add-fact '(power-state interface-01 on))
  (is-false (autonomy-has-work-p))
  (is (null (autonomy-open-goals)))
  (setf *last-autonomy* '(:status :done :halt :completed :marker t))
  (signals error (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :simulate)))
  (is (eq :completed (getf *last-autonomy* :halt)))
  (is (eq t (getf *last-autonomy* :marker)))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/autonomy/step"
                      '(:authority "simulate"))
    (is (= 400 code))
    (is (search "no open goal" (getf body :error))))
  (is (eq :completed (getf *last-autonomy* :halt)))
  (is (eq t (getf *last-autonomy* :marker))))

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

;;; ---------------------------------------------------------------------------
;;; Fixtures for the gate tests
;;; ---------------------------------------------------------------------------

(defun %auto-phase (summary phase)
  "The first entry of SUMMARY's :PHASES recorded for PHASE, or NIL."
  (find phase (getf summary :phases)
        :key (lambda (entry) (getf entry :phase))))

(defun %auto-seal (&key archived)
  "Fresh session whose open goal (SEALED X) needs SEAL, an irreversible
:HIGH operator. With ARCHIVED the plan is stored as SEAL-PROC and SEAL is
then unregistered, so only the archived step still carries the risk.
Returns the context."
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(ready x))
  (gp-add-operator
   (make-operator :name 'seal
                  :preconditions '((ready x))
                  :add-list '((sealed x))
                  :reversible nil
                  :risk :high))
  (when archived
    (gp-plan :goals '((sealed x)) :archive nil)
    (gp-remember-procedure :name 'seal-proc)
    (gp-remove-operator 'seal))
  (gp-add-goal '(sealed x))
  (gp-context))

(defun %auto-note-file (path)
  "Fresh session whose open goal (NOTED PATH) needs NOTE-FILE, which
writes PATH through the filesystem adapter."
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact (list 'seen path))
  (gp-add-operator
   (make-operator
    :name 'note-file
    :preconditions '((seen ?path))
    :add-list '((noted ?path))
    :meta (list :external
                (list :adapter :filesystem
                      :op :write-string
                      :args (list :path '?path :content "noticed")))))
  (gp-add-goal (list 'noted path))
  (gp-context))

(defun %auto-fetch (path)
  "Fresh session whose open goal (FETCHED PATH) takes two steps: PREPARE,
purely symbolic, then FETCH, which reads PATH through the filesystem
adapter and therefore fails for as long as PATH does not exist."
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact (list 'source path))
  (gp-add-operator
   (make-operator :name 'prepare
                  :preconditions '((source ?path))
                  :add-list '((prepared ?path))))
  (gp-add-operator
   (make-operator
    :name 'fetch
    :preconditions '((prepared ?path))
    :add-list '((fetched ?path))
    :meta (list :external
                (list :adapter :filesystem
                      :op :read-string
                      :args (list :path '?path)))))
  (gp-add-goal (list 'fetched path))
  (gp-context))

(defun %call-with-auto-directory (function)
  "Call FUNCTION with a fresh directory under the temporary directory,
then delete that directory tree."
  (let ((dir (uiop:ensure-directory-pathname
              (merge-pathnames
               (format nil "automa-gp-autonomy-~36R-~36R/"
                       (get-universal-time) (random (expt 36 6)))
               (uiop:temporary-directory)))))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (funcall function dir))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

;;; ---------------------------------------------------------------------------
;;; Policy construction
;;; ---------------------------------------------------------------------------

(test autonomy-authority-designators-and-order
  (dolist (authority *valid-authorities*)
    (is (eq authority (ensure-authority authority)))
    (is (eq authority (ensure-authority (intern (symbol-name authority)
                                                :automa-gp/tests))))
    (is (eq authority (ensure-authority (string-downcase authority)))))
  (dolist (bad '(nil :root "" "sudo" 3 (:execute)))
    (signals error (ensure-authority bad))
    (signals error (make-autonomy-policy :authority bad)))
  (is-false (find-symbol "SUDO" :keyword)
            "a rejected authority name must not be interned")
  (loop for (have . stronger) on *valid-authorities*
        do (is-true (authority>= have have))
           (dolist (need stronger)
             (is-false (authority>= have need))
             (is-true (authority>= need have)))))

(test autonomy-policy-arguments-are-validated
  (loop for (given expected) in '((nil 8) (-3 1) (0 1) (1 1) (5 5))
        do (is (= expected
                  (policy-max-steps (make-autonomy-policy :max-steps given)))))
  (dolist (bad '(2.5 "3" :many))
    (signals type-error (make-autonomy-policy :max-steps bad)))
  (signals type-error (make-autonomy-policy :confirm-fn "yes"))
  (is (eq :simulate (policy-authority (ensure-autonomy-policy))))
  (let ((policy (make-autonomy-policy :authority :read)))
    (is (eq policy (ensure-autonomy-policy policy))))
  ;; A malformed policy must not silently become the session policy.
  (%auto-studio)
  (let ((*autonomy-policy* (make-autonomy-policy :authority :execute
                                                 :auto-confirm t))
        (before (copy-tree (gp-facts))))
    (dolist (bad '((:authority :read) :read "read"))
      (signals type-error (ensure-autonomy-policy bad))
      (signals type-error (autonomous-step :policy bad))
      (signals type-error (autonomous-loop :policy bad)))
    (signals type-error (autonomous-step :context 'studio-audio))
    (signals type-error (autonomous-loop :context 'studio-audio))
    (is (equal before (gp-facts)))))

;;; ---------------------------------------------------------------------------
;;; The authorization gate
;;; ---------------------------------------------------------------------------

(test autonomy-gate-decides-by-authority-risk-and-confirmation
  ;; Each row: authority, risky plan?, auto-confirm, confirm-fn answer
  ;; (NIL = no fn) → allowed, reason, confirmation carried, fn calls.
  (loop for (authority risky auto answer ok reason confirmed calls) in
        '((:read     nil nil nil    nil :authority-read        nil 0)
          (:read     t   t   :allow nil :authority-read        nil 0)
          (:simulate nil nil nil    t   :simulate-authorized   nil 0)
          (:simulate t   nil nil    t   :simulate-authorized   nil 0)
          (:simulate t   nil :deny  t   :simulate-authorized   nil 0)
          (:execute  nil nil nil    t   :execute-authorized    nil 0)
          (:execute  nil nil :deny  t   :execute-authorized    nil 0)
          (:execute  nil t   nil    t   :execute-authorized    t   0)
          (:execute  t   nil nil    nil :confirmation-required nil 0)
          (:execute  t   t   nil    t   :execute-authorized    t   0)
          (:execute  t   nil :allow t   :execute-authorized    t   1)
          (:execute  t   nil :deny  nil :confirmation-denied   nil 1)
          (:execute  t   t   :deny  nil :confirmation-denied   nil 1))
        do (let* ((context (if risky (%auto-seal) (%auto-studio)))
                  (plan (gp-plan))
                  (seen nil)
                  (policy (make-autonomy-policy
                           :authority authority
                           :auto-confirm auto
                           :confirm-fn (and answer
                                            (lambda (&rest arguments)
                                              (push arguments seen)
                                              (eq answer :allow)))))
                  (row (list authority risky auto answer)))
             (is (equal (list ok reason confirmed)
                        (multiple-value-list
                         (automa-gp::%authorize-execution policy plan context)))
                 "gate for ~S" row)
             (is (= calls (length seen)) "confirm-fn calls for ~S" row)
             (dolist (arguments seen)
               (is (equal (list plan context) arguments)
                   "confirm-fn receives (PLAN CONTEXT)"))))
  ;; No authority runs something that is not a successful plan.
  (gp-clear-memory)
  (gp-reset)
  (gp-add-goal '(missing thing))
  (let ((failed (gp-plan)))
    (is-false (plan-success failed))
    (dolist (authority '(:simulate :execute))
      (let ((policy (make-autonomy-policy :authority authority :auto-confirm t)))
        (is (equal '(nil :plan-unsuccessful nil)
                   (multiple-value-list
                    (automa-gp::%authorize-execution policy failed (gp-context)))))
        (is (equal '(nil :no-plan nil)
                   (multiple-value-list
                    (automa-gp::%authorize-execution policy nil (gp-context)))))))))

(test autonomy-confirmation-gate-covers-registered-and-archived-steps
  ;; A risky step is confirmed the same way whether its operator is still
  ;; registered or only the archived step remembers the risk.
  (dolist (archived '(nil t))
    (loop for (confirm halt runs calls) in
          '((:none  :confirmation-required nil 0)
            (:deny  :confirmation-denied   nil 1)
            (:allow :completed             t   1)
            (:auto  :completed             t   0))
          do (let* ((context (%auto-seal :archived archived))
                    (seen nil)
                    (summary
                      (gp-autonomous-step
                       :policy (make-autonomy-policy
                                :authority :execute
                                :auto-confirm (eq confirm :auto)
                                :confirm-fn
                                (and (member confirm '(:deny :allow))
                                     (lambda (plan ctx)
                                       (push (list plan ctx) seen)
                                       (eq confirm :allow))))))
                    (row (list :archived archived :confirm confirm)))
               (is (eq halt (getf summary :halt)) "halt for ~S" row)
               (is (eq (if runs :done :halted) (getf summary :status))
                   "status for ~S" row)
               (is (eq runs (and (fact-p '(sealed x) (gp-facts)) t))
                   "live fact for ~S" row)
               (is (eq runs (and (getf summary :execution) t))
                   "execution for ~S" row)
               (is (= calls (length seen)) "confirm-fn calls for ~S" row)
               (dolist (arguments seen)
                 (is (plan-p (first arguments)))
                 (is (eq context (second arguments))))
               (is (equal '((:name seal :risk :high :reversible nil))
                          (getf (%auto-phase summary :evaluate) :risky-operators))
                   "risky operators for ~S" row)
               (when archived
                 (is (eq 'seal-proc
                         (getf (getf summary :plan) :from-procedure))))))))

(test autonomy-execute-carries-only-the-confirmation-the-gate-granted
  ;; A confirm-fn that was never asked must not confirm anything inside
  ;; the run: EXECUTE-PLAN! receives :CONFIRM T only from auto-confirm or
  ;; from a confirm-fn that approved this plan.
  (let ((carried nil))
    (unwind-protect
         (progn
           (sb-impl::encapsulate
            'execute-plan! 'watch-confirm
            (lambda (next context plan &rest keys &key confirm &allow-other-keys)
              (push confirm carried)
              (apply next context plan keys)))
           (loop for (risky auto answer expected) in
                 '((nil nil nil    nil)
                   (nil nil :deny  nil)
                   (nil nil :allow nil)
                   (nil t   nil    t)
                   (t   t   nil    t)
                   (t   nil :allow t))
                 do (if risky (%auto-seal) (%auto-studio))
                    (setf carried nil)
                    (let ((summary
                            (gp-autonomous-step
                             :policy (make-autonomy-policy
                                      :authority :execute
                                      :auto-confirm auto
                                      :confirm-fn
                                      (and answer
                                           (lambda (plan context)
                                             (declare (ignore plan context))
                                             (eq answer :allow)))))))
                      (is (eq :done (getf summary :status)))
                      (is (equal (list expected) carried)
                          "confirmation carried for ~S"
                          (list risky auto answer)))))
      (sb-impl::unencapsulate 'execute-plan! 'watch-confirm))))

(test autonomy-adapters-run-only-under-execute-with-the-adapters-flag
  (%call-with-auto-directory
   (lambda (dir)
     (let* ((marker (merge-pathnames "marker.txt" dir))
            (path (namestring marker)))
       ;; Each row: authority, policy :adapters, ambient *INVOKE-ADAPTERS*
       ;; → file written, goal fact live.
       (loop for (authority adapters ambient written live) in
             '((:read     t   t   nil nil)
               (:simulate t   t   nil nil)
               (:execute  nil t   nil t)
               (:execute  t   nil t   t))
             do (%auto-note-file path)
                (let* ((*invoke-adapters* ambient)
                       (summary (gp-autonomous-step
                                 :policy (make-autonomy-policy
                                          :authority authority
                                          :adapters adapters)))
                       (row (list authority :adapters adapters
                                  :ambient ambient)))
                  (is (eq (if (eq authority :read) :halted :done)
                          (getf summary :status))
                      "status for ~S" row)
                  (is (eq written (and (file-exists-p marker) t))
                      "file for ~S" row)
                  (is (eq live (and (fact-p (list 'noted path) (gp-facts)) t))
                      "live fact for ~S" row))
                (adapter-delete-file marker))))))

(test autonomy-read-reacts-then-halts-without-planning
  (gp-clear-memory)
  (gp-reset)
  (gp-add-reaction
   (make-event-reaction :name 'on-ping
                        :when '(ping ?who)
                        :assert '((pinged ?who))
                        :goals '((answered ?who))))
  (gp-add-operator
   (make-operator :name 'answer
                  :preconditions '((pinged ?who))
                  :add-list '((answered ?who))))
  (gp-emit '(ping a))
  (let ((summary (gp-autonomous-step
                  :policy (make-autonomy-policy :authority :read))))
    (is (eq :halted (getf summary :status)))
    (is (eq :authority-read (getf summary :halt)))
    (is (null (getf summary :plan)))
    (is (null (getf summary :execution)))
    (is (zerop (getf summary :pending-events)))
    (is (equal '((answered a)) (getf summary :goals)))
    (is (equal '((answered a))
               (getf (%auto-phase summary :evaluate) :differences)))
    (is-true (fact-p '(pinged a) (gp-facts)))
    (is-false (fact-p '(answered a) (gp-facts)))))

(test autonomy-has-work-follows-the-policy-it-is-given
  (gp-clear-memory)
  (gp-reset)
  (let ((deaf (make-autonomy-policy :react-events nil))
        (listening (make-autonomy-policy :react-events t)))
    (is-false (autonomy-has-work-p))
    (gp-emit '(ping a))
    (is-true (autonomy-has-work-p))
    (is-true (autonomy-has-work-p nil listening))
    (is-false (autonomy-has-work-p nil deaf)
              "an event the policy does not react to is not work")
    (let ((summary (autonomous-step :policy deaf)))
      (is (eq :no-goals (getf summary :halt)))
      (is (= 1 (getf summary :pending-events))))
    (gp-add-goal '(answered a))
    (is-true (autonomy-has-work-p nil deaf))
    (is-true (autonomy-has-work-p (gp-context) deaf))))

;;; ---------------------------------------------------------------------------
;;; The loop: replanning, the step limit, the summary
;;; ---------------------------------------------------------------------------

(test autonomy-loop-replans-after-a-live-run-that-failed-part-way
  (%call-with-auto-directory
   (lambda (dir)
     (let* ((source (merge-pathnames "source.txt" dir))
            (path (namestring source)))
       (flet ((policy (&rest keys)
                (apply #'make-autonomy-policy
                       (append keys
                               (list :authority :execute :adapters t
                                     :learn nil :prefer-archive nil))))
              (live-p (name)
                (and (fact-p (list name path) (gp-facts)) t)))
         ;; PREPARE runs, FETCH fails: the second cycle replans from the
         ;; observed facts, fails without changing anything, and halts.
         (%auto-fetch path)
         (let ((summary (gp-autonomous-loop :policy (policy) :max-steps 5)))
           (is (eq :halted (getf summary :status)))
           (is (eq :execution-failed (getf summary :halt)))
           (is (= 2 (getf summary :iterations)))
           (is (equal '(:continue :halted)
                      (mapcar (lambda (step) (getf step :status))
                              (getf summary :results))))
           (is (equal '(2 1)
                      (mapcar (lambda (step) (getf (getf step :plan) :length))
                              (getf summary :results))))
           (is (eq :replan-next
                   (getf (%auto-phase (first (getf summary :results)) :correct)
                         :action)))
           (is-true (live-p 'prepared))
           (is-false (live-p 'fetched)))
         ;; The step limit ends a run that would continue.
         (%auto-fetch path)
         (let ((summary (gp-autonomous-loop :policy (policy) :max-steps 1)))
           (is (eq :halted (getf summary :status)))
           (is (eq :max-steps (getf summary :halt)))
           (is (= 1 (getf summary :iterations)))
           (is (eq :continue (getf (getf summary :final) :status)))
           (is-true (live-p 'prepared))
           (is-false (live-p 'fetched)))
         ;; The policy limit applies when the call names none.
         (%auto-fetch path)
         (let ((summary (gp-autonomous-loop :policy (policy :max-steps 1))))
           (is (eq :max-steps (getf summary :halt)))
           (is (= 1 (getf summary :iterations))))
         ;; Without replanning the failed run halts the first cycle.
         (%auto-fetch path)
         (let ((summary (gp-autonomous-loop
                         :policy (policy :replan-on-discrepancy nil)
                         :max-steps 5)))
           (is (eq :halted (getf summary :status)))
           (is (eq :execution-failed (getf summary :halt)))
           (is (= 1 (getf summary :iterations))))
         ;; A simulation changes no live fact, so there is nothing to
         ;; replan from: it never asks for another cycle.
         (%auto-fetch path)
         (let ((summary (gp-autonomous-loop
                         :policy (policy :authority :simulate) :max-steps 5)))
           (is (eq :done (getf summary :status)))
           (is (= 1 (getf summary :iterations)))
           (is-false (live-p 'prepared)))
         ;; One step reports :CONTINUE; once the world is repaired the
         ;; next step replans from the observed facts and completes.
         (%auto-fetch path)
         (let ((first-step (gp-autonomous-step :policy (policy))))
           (is (eq :continue (getf first-step :status)))
           (is (null (getf first-step :halt)))
           (is-false (getf (getf first-step :execution) :success))
           (adapter-write-file-string path "payload")
           (let ((second-step (gp-autonomous-step :policy (policy))))
             (is (eq :done (getf second-step :status)))
             (is (equal '(fetch) (getf (getf second-step :plan) :operators)))
             (is-true (live-p 'fetched)))))))))

(test autonomy-leaves-step-restarts-to-the-caller
  ;; With the runner's default abort off, a failing step reaches the
  ;; caller's handler with its restarts still in place: the cycle neither
  ;; swallows the condition nor signals it again after unwinding.
  (%call-with-auto-directory
   (lambda (dir)
     (let ((path (namestring (merge-pathnames "source.txt" dir)))
           (policy (make-autonomy-policy :authority :execute :adapters t
                                         :learn nil :prefer-archive nil
                                         :replan-on-discrepancy nil))
           (*plan-runner-default-abort* nil))
       ;; A handler that picks a restart lets the cycle finish normally.
       (%auto-fetch path)
       (let* ((offered nil)
              (summary
                (handler-bind
                    ((action-failed
                       (lambda (condition)
                         (setf offered (mapcar #'restart-name
                                               (compute-restarts condition)))
                         (invoke-restart :abort-execution))))
                  (gp-autonomous-step :policy policy))))
         (is (subsetp '(:retry :skip :abort-execution :use-value
                        :use-alternative :ask-user)
                      offered))
         (is (eq :halted (getf summary :status)))
         (is (eq :execution-failed (getf summary :halt)))
         (is-false (getf (getf summary :execution) :success))
         (is (eq :execute (context-mode (gp-context)))))
       ;; With no handler the condition leaves the cycle: the mode goes
       ;; back to what it was and the last summary is not replaced.
       (%auto-fetch path)
       (let ((marker (list :marker t)))
         (setf *last-autonomy* marker)
         (signals action-failed (gp-autonomous-step :policy policy))
         (is (eq marker *last-autonomy*))
         (is (eq :plan (context-mode (gp-context))))
         (is-true (fact-p (list 'prepared path) (gp-facts)))
         (is-false (fact-p (list 'fetched path) (gp-facts))))))))

(test autonomy-does-not-run-a-plan-the-runner-refuses-after-the-gate
  ;; The gate and the runner ask the same question about external
  ;; actions. Should the answer change between the two, the runner's
  ;; refusal reaches the caller: no step ran and the mode is restored.
  (%call-with-auto-directory
   (lambda (dir)
     (let* ((marker (merge-pathnames "marker.txt" dir))
            (path (namestring marker))
            (in-runner nil))
       (flet ((runner (next &rest arguments)
                (setf in-runner t)
                (unwind-protect (apply next arguments)
                  (setf in-runner nil)))
              (supported (next &rest arguments)
                (and (not in-runner) (apply next arguments))))
         (unwind-protect
              (progn
                (sb-impl::encapsulate 'simulate-plan 'in-runner #'runner)
                (sb-impl::encapsulate 'execute-plan! 'in-runner #'runner)
                (sb-impl::encapsulate 'plan-external-actions-supported-p
                                      'changed-since-the-gate #'supported)
                (dolist (authority '(:simulate :execute))
                  (%auto-note-file path)
                  (let ((marker-summary (list :marker t)))
                    (setf *last-autonomy* marker-summary)
                    (signals error
                      (gp-autonomous-step
                       :policy (make-autonomy-policy :authority authority
                                                     :adapters t)))
                    (is (eq marker-summary *last-autonomy*)))
                  (is (eq :plan (context-mode (gp-context))))
                  (is (null (gp-last-execution)))
                  (is-false (file-exists-p marker))
                  (is-false (fact-p (list 'noted path) (gp-facts)))))
           (sb-impl::unencapsulate 'simulate-plan 'in-runner)
           (sb-impl::unencapsulate 'execute-plan! 'in-runner)
           (sb-impl::unencapsulate 'plan-external-actions-supported-p
                                   'changed-since-the-gate)))))))

(test autonomy-loop-requires-a-positive-step-limit
  (%auto-studio)
  (let ((marker (list :marker t))
        (before (copy-tree (gp-facts))))
    (setf *last-autonomy* marker)
    (dolist (bad '(0 -3 2.5 "3"))
      (signals type-error (gp-autonomous-loop :max-steps bad))
      (signals type-error (autonomous-loop :max-steps bad)))
    ;; A policy limit lowered after construction is refused the same way.
    (let ((policy (make-autonomy-policy :authority :execute :auto-confirm t)))
      (setf (policy-max-steps policy) 0)
      (signals type-error (autonomous-loop :policy policy)))
    (is (eq marker *last-autonomy*))
    (is (equal before (gp-facts)))))

(test autonomy-loop-summary-extends-the-last-step-summary
  (%auto-studio)
  (let* ((summary (gp-autonomous-loop
                   :policy (make-autonomy-policy :authority :simulate)
                   :max-steps 3))
         (final (getf summary :final)))
    (is (eq summary (gp-last-autonomy)))
    (is (= 1 (getf summary :iterations)))
    (is (equal (list final) (getf summary :results)))
    (loop for (key value) on final by #'cddr
          do (is (equal value (getf summary key))
                 "the loop summary keeps ~S of its last step" key))
    (dolist (key '(:status :halt :authority :authorized :authorize-reason
                   :phases :plan :execution :goals :pending-events))
      (is (not (eq :absent (getf summary key :absent)))
          "the loop summary has ~S" key))
    (is-true (getf (getf summary :plan) :success))
    (is-true (getf (getf summary :execution) :success)))
  ;; The JSON façade therefore still shows the plan and the run.
  (multiple-value-bind (code body)
      (web-api-handle :get "/api/autonomy")
    (is (= 200 code))
    (let ((last (getf body :last)))
      (is (= 1 (getf last :iterations)))
      (is (eq t (getf last :authorized)))
      (is (eq :simulate-authorized (getf last :authorize-reason)))
      (is (listp (getf last :plan)))
      (is (= 2 (getf (getf last :plan) :length)))
      (is (listp (getf last :execution)))
      (is (eq :simulate (getf (getf last :execution) :mode)))
      (is (plusp (length (getf last :phases))))
      (is (= 1 (length (getf last :goals)))))))

;;; ---------------------------------------------------------------------------
;;; Remembering procedures
;;; ---------------------------------------------------------------------------

(test autonomy-remembers-each-goal-set-as-its-own-procedure
  (flet ((chain ()
           (gp-clear-memory)
           (gp-reset)
           (gp-add-fact '(a 1))
           (gp-add-operator (make-operator :name 'op-b
                                           :preconditions '((a 1))
                                           :add-list '((b 1))))
           (gp-add-operator (make-operator :name 'op-d
                                           :preconditions '((a 1))
                                           :add-list '((d 1))))))
    (dolist (authority '(:simulate :execute))
      (chain)
      (let ((policy (make-autonomy-policy :authority authority
                                          :remember-procedure t
                                          :learn nil)))
        ;; Two cycles with different goal sets leave two procedures.
        (gp-add-goal '(b 1))
        (is (eq :done (getf (gp-autonomous-step :policy policy) :status)))
        (gp-remove-goal '(b 1))
        (gp-add-goal '(d 1))
        (is (eq :done (getf (gp-autonomous-step :policy policy) :status)))
        (is (= 2 (length (gp-procedures))) "under ~S" authority)
        (loop for (goal operator) in '(((b 1) op-b) ((d 1) op-d))
              for found = (procedures-for-goals (list goal))
              do (is (= 1 (length found)) "one procedure for ~S" goal)
                 (is (equal (list operator)
                            (procedure-operators-used (first found))))
                 (is (= 1 (procedure-success-count (first found)))
                     "~S under ~S" goal authority))))
    ;; The same fresh plan seen again is the same procedure: one more
    ;; success, no second copy.
    (chain)
    (let ((policy (make-autonomy-policy :authority :execute
                                        :remember-procedure t
                                        :prefer-archive nil
                                        :learn nil)))
      (gp-add-goal '(b 1))
      (gp-autonomous-step :policy policy)
      (gp-remove-fact '(b 1))
      (gp-autonomous-step :policy policy)
      (is (= 1 (length (gp-procedures))))
      (is (= 2 (procedure-success-count (first (gp-procedures))))))
    ;; A plan assembled from archived procedures is not stored again;
    ;; the live run scores each procedure it replayed.
    (chain)
    (gp-remember-procedure :plan (gp-plan :goals '((b 1)) :archive nil)
                           :name 'make-b)
    (gp-remember-procedure :plan (gp-plan :goals '((d 1)) :archive nil)
                           :name 'make-d)
    (gp-add-goal '(b 1))
    (gp-add-goal '(d 1))
    (let ((summary (gp-autonomous-step
                    :policy (make-autonomy-policy :authority :execute
                                                  :remember-procedure t
                                                  :learn nil))))
      (is (eq :done (getf summary :status)))
      (is (equal '(make-b make-d)
                 (sort (copy-list (getf (plan-meta (gp-last-plan))
                                        :from-procedures))
                       #'string<)))
      (is (= 2 (length (gp-procedures))))
      (dolist (name '(make-b make-d))
        (is (= 2 (procedure-success-count (gp-find-procedure name))))))))
