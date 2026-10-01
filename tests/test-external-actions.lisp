;;;; tests/test-external-actions.lisp — external actions are named, matched and gated before anything runs

(in-package #:automa-gp/tests)

(def-suite external-actions-suite :in automa-gp-suite)
(in-suite external-actions-suite)

(test plan-names-an-external-action-without-running
  (gp-clear-memory)
  (gp-reset)
  (is (null (plan-external-actions nil)))
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-plan-external-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-fact (list 'seen path))
           (gp-add-operator
            (make-operator :name 'note-file
                           :preconditions '((seen ?path))
                           :add-list '((noted ?path))))
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-success plan))
             (is (null (plan-external-actions plan))))
           (gp-remove-operator 'note-file)
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
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-success plan))
             (let ((actions (plan-external-actions plan)))
               (is (= 1 (length actions)))
               (is (null (plan-external-actions-withheld plan)))
               (is (eq 'note-file (getf (first actions) :operator)))
               (is (eq :filesystem (getf (first actions) :adapter)))
               (is (eq :write-string (getf (first actions) :op)))
               (is (equal path (getf (getf (first actions) :args) :path)))
               (is (equal "noticed" (getf (getf (first actions) :args) :content))))
             (is-false (file-exists-p marker))
             (gp-simulate)
             (is (fact-p (list 'seen path) (gp-facts)))
             (is (not (fact-p (list 'noted path) (gp-facts))))
             (is-false (file-exists-p marker)))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (let ((ext (getf (getf body :plan) :external)))
               (is (= 1 (length ext)))
               (is (eq :filesystem (getf (aref ext 0) :adapter)))
               (is (equal path (getf (getf (aref ext 0) :args) :path)))))
           (gp-run :adapters nil :confirm t)
           (is (fact-p (list 'noted path) (gp-facts)))
           (is-false (file-exists-p marker))
           (gp-remove-fact (list 'noted path))
           (gp-run :adapters t :confirm t)
           (is (equal "noticed" (adapter-read-file-string marker)))
           (gp-remove-operator 'note-file)
           (is (null (plan-external-actions (gp-last-plan))))
           (is (not (plan-external-actions-match-p (gp-last-plan))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (declare (ignore code))
             (is (= 1 (length (getf (getf body :plan) :external))))
             (is (null (getf (getf body :plan) :external-matches)))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test execute-refuses-an-external-action-that-changed
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-plan-changed-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-fact (list 'seen path))
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
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-success plan))
             (is (plan-external-actions-match-p plan)))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (eq t (getf (getf body :plan) :external-matches)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external) 0)
                                    :args)
                              :content))))
           (setf (operator-meta (find-operator (gp-context) 'note-file))
                 (list :external
                       (list :adapter :filesystem
                             :op :write-string
                             :args (list :path '?path
                                         :content "changed"))))
           (is (not (plan-external-actions-match-p (gp-last-plan))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (null (getf (getf body :plan) :external-matches)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external) 0)
                                    :args)
                              :content))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters t))
             (is (= 400 code))
             (is (search "no longer matches" (getf body :error))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters nil))
             (is (= 400 code))
             (is (search "no longer matches" (getf body :error))))
           (is (eq :plan (context-mode (gp-context))))
           (is-false (file-exists-p marker))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (handler-case (gp-run :adapters nil :confirm t)
             (error (condition)
               (is (search "no longer matches" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is-false (file-exists-p marker))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (handler-case (gp-simulate)
             (error (condition)
               (is (search "no longer matches" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/simulate")
             (is (= 400 code))
             (is (search "no longer matches" (getf body :error))))
           (is (eq :plan (context-mode (gp-context))))
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-external-actions-match-p plan))
             (is (equal "changed"
                        (getf (getf (first (plan-external-actions plan)) :args)
                              :content))))
           (gp-run :adapters t :confirm t)
           (is (equal "changed" (adapter-read-file-string marker))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test replay-runs-the-recorded-external-action
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-replay-external-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-fact (list 'seen path))
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
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-success plan)))
           (gp-remember-procedure :name 'note-once)
           (gp-run :adapters t :confirm t)
           (is (equal "noticed" (adapter-read-file-string marker)))
           (adapter-delete-file marker)
           (gp-remove-fact (list 'noted path))
           (let ((plan (gp-use-procedure :name 'note-once)))
             (is (eq 'note-once (getf (plan-meta plan) :from-procedure)))
             (is (plan-external-actions-match-p plan))
             (is (equal path
                        (getf (getf (first (plan-external-actions plan)) :args)
                              :path))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (eq t (getf (getf body :plan) :external-matches)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external) 0)
                                    :args)
                              :content))))
           (gp-simulate)
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (is-false (file-exists-p marker))
           (gp-run :adapters nil :confirm t)
           (is (fact-p (list 'noted path) (gp-facts)))
           (is-false (file-exists-p marker))
           (gp-remove-fact (list 'noted path))
           (gp-run :adapters t :confirm t)
           (is (equal "noticed" (adapter-read-file-string marker)))
           (adapter-delete-file marker)
           (gp-remove-fact (list 'noted path))
           (gp-remove-operator 'note-file)
           (let ((plan (gp-use-procedure :name 'note-once)))
             (is (plan-external-actions-match-p plan))
             (is (null (plan-external-actions plan))))
           (gp-run :adapters t :confirm t)
           (is (fact-p (list 'noted path) (gp-facts)))
           (is-false (file-exists-p marker)))
      (gp-clear-memory)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test effects-only-replay-withholds-the-external-action
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-withhold-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((seen ?path) (open ?path))
             :add-list '((noted ?path) (closed ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (install-procedure!
            (make-procedure
             :name 'note-once
             :goals (list (list 'noted path))
             :operators-used '(note-file)
             :steps (list
                     (list :operator 'note-file
                           :bindings (list (cons '?path path))
                           :goal (list 'noted path)))))
           (gp-add-fact (list 'seen path))
           (gp-add-fact (list 'noted path))
           (let ((plan (gp-use-procedure :name 'note-once)))
             (is (eq t (getf (first (plan-steps plan)) :effects-only)))
             (is (null (plan-external-actions plan)))
             (is (plan-external-actions-match-p plan))
             (let ((held (plan-external-actions-withheld plan)))
               (is (= 1 (length held)))
               (is (equal path (getf (getf (first held) :args) :path)))
               (is (equal "noticed" (getf (getf (first held) :args) :content)))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (zerop (length (getf (getf body :plan) :external))))
             (is (eq t (getf (getf body :plan) :external-matches)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external-withheld) 0)
                                    :args)
                              :content))))
           (gp-simulate)
           (is (not (fact-p (list 'closed path) (gp-facts))))
           (is-false (file-exists-p marker))
           (is (not (eq :withheld
                        (getf (first (execution-steps (gp-last-execution)))
                              :external))))
           (gp-run :adapters nil :confirm t)
           (is (fact-p (list 'closed path) (gp-facts)))
           (is-false (file-exists-p marker))
           (is (not (eq :withheld
                        (getf (first (execution-steps (gp-last-execution)))
                              :external))))
           (gp-remove-fact (list 'closed path))
           (setf (operator-meta (find-operator (gp-context) 'note-file))
                 (list :external
                       (list :adapter :filesystem
                             :op :write-string
                             :args (list :path '?path
                                         :content "changed"))))
           (is (plan-external-actions-match-p (gp-last-plan)))
           (is (null (plan-external-actions (gp-last-plan))))
           (is (equal "changed"
                      (getf (getf (first (plan-external-actions-withheld
                                          (gp-last-plan)))
                                  :args)
                            :content)))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (eq t (getf (getf body :plan) :external-matches)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external-withheld) 0)
                                    :args)
                              :content))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters t))
             (is (= 200 code))
             (is (eq :withheld
                     (getf (aref (getf (getf body :execution) :steps) 0)
                           :external))))
           (is (fact-p (list 'closed path) (gp-facts)))
           (is-false (file-exists-p marker)))
      (gp-clear-memory)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test external-action-refuses-when-the-facts-no-longer-support-it
  (gp-clear-memory)
  (gp-reset)
  (is (null (plan-external-actions-supported-p nil)))
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-support-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-fact (list 'seen path))
           (gp-add-operator
            (make-operator :name 'open-file
                           :preconditions '((seen ?path))
                           :add-list '((open ?path))))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((open ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-success plan))
             (is (eq 'open-file (getf (first (plan-steps plan)) :operator)))
             (is (eq 'note-file (getf (second (plan-steps plan)) :operator)))
             (is (= 1 (length (plan-external-actions plan))))
             (is (null (plan-external-actions-withheld plan)))
             (is (plan-external-actions-match-p plan))
             (is (plan-external-actions-supported-p plan))
             (is (not (fact-p (list 'open path) (gp-facts)))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (eq t (getf (getf body :plan) :external-supported)))
             (is (equal "noticed"
                        (getf (getf (aref (getf (getf body :plan) :external) 0)
                                    :args)
                              :content))))
           (gp-remove-fact (list 'seen path))
           (is (plan-external-actions-match-p (gp-last-plan)))
           (is (not (plan-external-actions-supported-p (gp-last-plan))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/plan")
             (is (= 200 code))
             (is (eq t (getf (getf body :plan) :external-matches)))
             (is (null (getf (getf body :plan) :external-supported)))
             (is (= 1 (length (getf (getf body :plan) :external)))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters t))
             (is (= 400 code))
             (is (search "no longer support" (getf body :error))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters nil))
             (is (= 400 code))
             (is (search "no longer support" (getf body :error))))
           (is (eq :plan (context-mode (gp-context))))
           (is-false (file-exists-p marker))
           (is (not (fact-p (list 'open path) (gp-facts))))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (handler-case (gp-run :adapters nil :confirm t)
             (error (condition)
               (is (search "no longer support" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is-false (file-exists-p marker))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (handler-case (gp-simulate)
             (error (condition)
               (is (search "no longer support" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/simulate")
             (is (= 400 code))
             (is (search "no longer support" (getf body :error))))
           (is (eq :plan (context-mode (gp-context))))
           (is (not (fact-p (list 'open path) (gp-facts))))
           (gp-add-fact (list 'seen path))
           (is (plan-external-actions-supported-p (gp-last-plan)))
           (gp-run :adapters t :confirm t)
           (is (equal "noticed" (adapter-read-file-string marker))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test unsupported-external-action-does-not-apply-earlier-steps
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-prefix-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-operator
            (make-operator :name 'mark
                           :preconditions '((ready ?path))
                           :add-list '((marked ?path))))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((open ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (install-procedure!
            (make-procedure
             :name 'mark-then-note
             :goals (list (list 'marked path) (list 'noted path))
             :operators-used '(mark note-file)
             :steps (list
                     (list :operator 'mark
                           :bindings (list (cons '?path path))
                           :goal (list 'marked path))
                     (list :operator 'note-file
                           :bindings (list (cons '?path path))
                           :goal (list 'noted path)))))
           (gp-add-fact (list 'ready path))
           (gp-add-fact (list 'open path))
           (let ((plan (gp-use-procedure :name 'mark-then-note)))
             (is (eq 'mark (getf (first (plan-steps plan)) :operator)))
             (is (eq 'note-file (getf (second (plan-steps plan)) :operator)))
             (is (plan-external-actions-supported-p plan)))
           (gp-remove-fact (list 'open path))
           (is (not (plan-external-actions-supported-p (gp-last-plan))))
           (handler-case (gp-run :adapters nil :confirm t)
             (error (condition)
               (is (search "no longer support" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is (not (fact-p (list 'marked path) (gp-facts))))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (is-false (file-exists-p marker))
           (handler-case (gp-simulate)
             (error (condition)
               (is (search "no longer support" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is (not (fact-p (list 'marked path) (gp-facts))))
           (gp-add-fact (list 'open path))
           (gp-run :adapters nil :confirm t)
           (is (fact-p (list 'marked path) (gp-facts)))
           (is (fact-p (list 'noted path) (gp-facts)))
           (is-false (file-exists-p marker)))
      (gp-clear-memory)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test changed-external-action-does-not-apply-earlier-steps
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-changed-prefix-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-operator
            (make-operator :name 'mark
                           :preconditions '((ready ?path))
                           :add-list '((marked ?path))))
           (gp-add-operator
            (make-operator
             :name 'note-file
             :preconditions '((open ?path))
             :add-list '((noted ?path))
             :meta (list :external
                         (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path
                                           :content "noticed")))))
           (install-procedure!
            (make-procedure
             :name 'mark-then-note
             :goals (list (list 'marked path) (list 'noted path))
             :operators-used '(mark note-file)
             :steps (list
                     (list :operator 'mark
                           :bindings (list (cons '?path path))
                           :goal (list 'marked path))
                     (list :operator 'note-file
                           :bindings (list (cons '?path path))
                           :goal (list 'noted path)))))
           (gp-add-fact (list 'ready path))
           (gp-add-fact (list 'open path))
           (let ((plan (gp-use-procedure :name 'mark-then-note)))
             (is (eq 'mark (getf (first (plan-steps plan)) :operator)))
             (is (eq 'note-file (getf (second (plan-steps plan)) :operator)))
             (is (plan-external-actions-match-p plan)))
           (setf (operator-meta (find-operator (gp-context) 'note-file))
                 (list :external
                       (list :adapter :filesystem
                             :op :write-string
                             :args (list :path '?path
                                         :content "changed"))))
           (is (not (plan-external-actions-match-p (gp-last-plan))))
           (is (plan-external-actions-supported-p (gp-last-plan)))
           (handler-case (gp-run :adapters nil :confirm t)
             (error (condition)
               (is (search "no longer matches" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is (not (fact-p (list 'marked path) (gp-facts))))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (is-false (file-exists-p marker))
           (let ((plan (gp-use-procedure :name 'mark-then-note)))
             (is (plan-external-actions-match-p plan))
             (is (equal "changed"
                        (getf (getf (first (plan-external-actions plan)) :args)
                              :content))))
           (gp-run :adapters nil :confirm t)
           (is (fact-p (list 'marked path) (gp-facts)))
           (is (fact-p (list 'noted path) (gp-facts)))
           (is-false (file-exists-p marker)))
      (gp-clear-memory)
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test a-refused-execute-leaves-the-mode-unchanged
  (gp-clear-memory)
  (gp-reset)
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames
                (format nil "automa-gp-mode-~A/" (get-universal-time))
                (uiop:temporary-directory))))
         (marker (merge-pathnames "marker.txt" dir))
         (path (namestring marker)))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (gp-add-fact (list 'seen path))
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
           (gp-plan :goals (list (list 'noted path)) :archive nil)
           (is (eq :plan (context-mode (gp-context))))
           (gp-remove-fact (list 'seen path))
           (handler-case (gp-run :adapters t :confirm t)
             (error (condition)
               (is (search "no longer support" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is-false (file-exists-p marker))
           (is (not (fact-p (list 'noted path) (gp-facts))))
           (multiple-value-bind (code body)
               (web-api-handle :post "/api/run" '(:confirm t :adapters t))
             (is (= 400 code))
             (is (search "no longer support" (getf body :error))))
           (multiple-value-bind (code body)
               (web-api-handle :get "/api/status")
             (is (= 200 code))
             (is (eq :plan (getf body :mode))))
           (gp-add-fact (list 'seen path))
           (setf (operator-meta (find-operator (gp-context) 'note-file))
                 (list :external
                       (list :adapter :filesystem
                             :op :write-string
                             :args (list :path '?path
                                         :content "changed"))))
           (handler-case (gp-run :adapters t :confirm t)
             (error (condition)
               (is (search "no longer matches" (princ-to-string condition)))))
           (is (eq :plan (context-mode (gp-context))))
           (is (null (gp-last-execution)))
           (is-false (file-exists-p marker))
           (let ((plan (gp-plan :goals (list (list 'noted path)) :archive nil)))
             (is (plan-external-actions-match-p plan))
             (is (plan-external-actions-supported-p plan)))
           (gp-run :adapters t :confirm t)
           (is (eq :execute (context-mode (gp-context))))
           (is (equal "changed" (adapter-read-file-string marker))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))
