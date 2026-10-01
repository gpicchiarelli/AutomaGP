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

;;; ---------------------------------------------------------------------------
;;; The gates speak through a typed condition, in both runners
;;; ---------------------------------------------------------------------------

(defun call-with-unwritten-marker (function)
  "Call FUNCTION with the name of a file in a directory nobody created.
The directory is removed afterwards, whatever FUNCTION left there."
  (let ((dir (uiop:ensure-directory-pathname
              (merge-pathnames
               (format nil "automa-gp-gate-~A-~A/" (get-universal-time)
                       (random 1000000))
               (uiop:temporary-directory)))))
    (unwind-protect
         (funcall function (namestring (merge-pathnames "marker.txt" dir)))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(defun note-file-operator (name preconditions &key (content "noticed"))
  "An operator that notes ?PATH and would write CONTENT there."
  (make-operator
   :name name
   :preconditions preconditions
   :add-list '((noted ?path))
   :meta (list :external (list :adapter :filesystem
                               :op :write-string
                               :args (list :path '?path :content content)))))

(defun mark-then-note-case (path)
  "A context that can mark PATH and then note it through the filesystem
adapter, and the plan that does both. Returns (VALUES CONTEXT PLAN)."
  (let ((ctx (create-context :name 'gate
                             :facts (list (list 'ready path)
                                          (list 'seen path)))))
    (register-operator! ctx (make-operator :name 'mark
                                           :preconditions '((ready ?path))
                                           :add-list '((marked ?path))))
    (register-operator! ctx (note-file-operator 'note-file '((seen ?path))))
    (values ctx
            (plan-from-context ctx :goals (list (list 'marked path)
                                                (list 'noted path))))))

(defun run-with-adapters (mode ctx plan)
  (ecase mode
    (:simulate (let ((*invoke-adapters* t))
                 (simulate-plan plan :context ctx)))
    (:execute (execute-plan! ctx plan :adapters t))))

(test the-external-gates-signal-plan-refused-with-a-reason
  (loop
    for (reason text break)
      in (list (list :external-mismatch "no longer matches"
                     (lambda (ctx path)
                       (declare (ignore path))
                       (setf (operator-meta (find-operator ctx 'note-file))
                             (operator-meta
                              (note-file-operator 'note-file nil
                                                  :content "changed")))))
               (list :external-unsupported "no longer support"
                     (lambda (ctx path)
                       (setf (context-facts ctx)
                             (list (list 'ready path))))))
    do (dolist (mode '(:simulate :execute))
         (call-with-unwritten-marker
          (lambda (path)
            (multiple-value-bind (ctx plan) (mark-then-note-case path)
              (is (equal '(mark note-file)
                         (mapcar (lambda (step) (getf step :operator))
                                 (plan-steps plan))))
              (funcall break ctx path)
              (let ((facts (copy-list (context-facts ctx)))
                    (refusal (handler-case (run-with-adapters mode ctx plan)
                               (plan-refused (c) c))))
                (is (typep refusal 'plan-refused)
                    "~A did not refuse (~A)" mode reason)
                (when (typep refusal 'plan-refused)
                  (is (typep refusal 'gp-error))
                  (is (eq reason (plan-refused-reason refusal)))
                  (is (eq ctx (gp-condition-context refusal)))
                  (is (search text (princ-to-string refusal))))
                ;; MARK, the step before the external one, was not applied.
                (is (equal facts (context-facts ctx)))
                (is-false (file-exists-p path)))))))))

(test simulation-never-reaches-an-adapter
  (call-with-unwritten-marker
   (lambda (path)
     (multiple-value-bind (ctx plan) (mark-then-note-case path)
       (let ((facts (copy-list (context-facts ctx)))
             (result (run-with-adapters :simulate ctx plan)))
         (is-true (execution-success result))
         (is (fact-p (list 'noted path)
                     (state-facts (execution-final-state result))))
         (is (every (lambda (step) (null (getf step :external)))
                    (execution-steps result)))
         (is (equal facts (context-facts ctx)))
         (is-false (file-exists-p path)))))))

(test an-alternative-operator-cannot-run-an-unrecorded-external-action
  ;; The plan names NOTE, which has no external action, so the plan record
  ;; holds none. FORCE-NOTE, offered through USE-ALTERNATIVE, would write a
  ;; file nobody was shown.
  (flet ((attempt (path &key adapters on-refusal)
           (let ((ctx (create-context :name 'gate
                                      :facts (list (list 'seen path))))
                 (force (note-file-operator 'force-note '((seen ?path))))
                 (*plan-runner-default-abort* nil))
             (register-operator! ctx (make-operator
                                      :name 'note
                                      :preconditions '((seen ?path) (open ?path))
                                      :add-list '((noted ?path))))
             (let ((plan (make-instance
                          'plan
                          :goals (list (list 'noted path))
                          :steps (list (list :operator 'note
                                             :bindings (list (cons '?path path))
                                             :goal (list 'noted path)))
                          :success t)))
               (automa-gp::remember-plan-external-actions plan :context ctx)
               (is (null (plan-external-actions plan :context ctx)))
               (values
                (handler-case
                    (handler-bind ((precondition-failure
                                     (lambda (c)
                                       (declare (ignore c))
                                       (invoke-restart :use-alternative force)))
                                   (plan-refused
                                     (lambda (c)
                                       (declare (ignore c))
                                       (when on-refusal
                                         (invoke-restart on-refusal)))))
                      (execute-plan! ctx plan :adapters adapters))
                  (plan-refused (c) c))
                ctx)))))
    ;; Adapters on: the alternative is refused, under the step restarts.
    (loop for (restart status) in '((:skip :skipped)
                                    (:abort-execution :aborted))
          do (call-with-unwritten-marker
              (lambda (path)
                (multiple-value-bind (result ctx)
                    (attempt path :adapters t :on-refusal restart)
                  (is (execution-result-p result) "~A is not offered" restart)
                  (when (execution-result-p result)
                    (is-false (execution-success result))
                    (is (equal (list status)
                               (mapcar (lambda (step) (getf step :status))
                                       (execution-steps result)))))
                  (is (equal (list (list 'seen path)) (context-facts ctx)))
                  (is-false (file-exists-p path))))))
    ;; With nobody recovering, the caller sees the typed refusal.
    (call-with-unwritten-marker
     (lambda (path)
       (multiple-value-bind (refusal ctx) (attempt path :adapters t)
         (is (typep refusal 'plan-refused))
         (when (typep refusal 'plan-refused)
           (is (eq :external-mismatch (plan-refused-reason refusal)))
           (is (eq 'force-note
                   (operator-name (gp-condition-operator refusal)))))
         (is (equal (list (list 'seen path)) (context-facts ctx)))
         (is-false (file-exists-p path)))))
    ;; Adapters off: the alternative is an ordinary symbolic step.
    (call-with-unwritten-marker
     (lambda (path)
       (multiple-value-bind (result ctx) (attempt path :adapters nil)
         (is (execution-result-p result))
         (when (execution-result-p result)
           (is-true (execution-success result)))
         (is (fact-p (list 'noted path) (context-facts ctx)))
         (is-false (file-exists-p path)))))))
