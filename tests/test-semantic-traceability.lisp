;;;; tests/test-semantic-traceability.lisp — requirement, construct, code, test

(in-package #:automa-gp/tests)

(def-suite semantic-traceability-suite :in automa-gp-suite)
(in-suite semantic-traceability-suite)

(defun %registry-with-requirements ()
  "A registry with one standard and the requirements of the tests below."
  (let ((registry (sem:make-registry)))
    (sem:with-registry (registry)
      (sem:register-standard
       (%standard :alpha "1"
                  :constructs (list (sem:make-construct :id :triple :name "triple")
                                    (sem:make-construct :id :literal :name "literal"))))
      (sem:register-standard (%standard :empty "1")))
    registry))

(test a-requirement-id-is-req-group-and-number
  (loop for (id valid)
          in '(("REQ-ALPHA-0001" t)
               ("REQ-ALPHA-1" t)
               ("REQ-OWL2-SYNTAX-0001" t)
               ("REQ-OWL2-0001" t)
               ("REQ-A-1" t)
               ("REQ--1" nil)
               ("REQ-A-" nil)
               ("REQ-A-x" nil)
               ("REQ-a-1" nil)
               ("REQ-alpha-0001" nil)
               ("req-A-1" nil)
               ("REQ-A--1" nil)
               ("REQ--A-1" nil)
               ("REQ-A-B-" nil)
               ("ALPHA-1" nil)
               ("" nil)
               ("REQ-1" nil))
        do (is (eq valid (and (sem::%valid-requirement-id-p id) t)) "~S" id))
  (is-false (sem::%valid-requirement-id-p nil))
  (is-false (sem::%valid-requirement-id-p 'req-a-1)))

(test a-requirement-is-refused-with-a-bad-id-or-an-unversioned-standard
  (let ((id-error (handler-case (sem:make-requirement :id "R-1" :standard "alpha@1")
                    (sem:standard-resolution-error (c) c)))
        (version-error (handler-case (sem:make-requirement :id "REQ-ALPHA-1"
                                                           :standard "alpha")
                         (sem:standard-resolution-error (c) c))))
    (is (eq :bad-requirement-id (sem:standards-error-code id-error)))
    (is (eq :unversioned-requirement (sem:standards-error-code version-error)))))

(test a-requirement-belongs-to-a-registered-standard-and-a-cataloged-construct
  (let ((registry (%registry-with-requirements)))
    (sem:with-registry (registry)
      (flet ((code-of (&rest args)
               (handler-case (progn (sem:register-requirement
                                     (apply #'sem:make-requirement args))
                                    :registered)
                 (sem:standard-resolution-error (c) (sem:standards-error-code c)))))
        (is (eq :registered
                (code-of :id "REQ-ALPHA-1" :standard "alpha@1" :construct :triple)))
        (is (eq :unknown-standard
                (code-of :id "REQ-NOWHERE-1" :standard "nowhere@1")))
        (is (eq :unknown-construct
                (code-of :id "REQ-ALPHA-2" :standard "alpha@1" :construct :quad)))
        (is (eq :duplicate-requirement
                (code-of :id "REQ-ALPHA-1" :standard "alpha@1")))
        ;; A standard whose catalog is not written yet cannot be checked
        ;; against it, so any construct is taken on trust until it is.
        (is (eq :registered
                (code-of :id "REQ-EMPTY-1" :standard "empty@1" :construct :anything)))
        (is (eq :registered
                (progn (sem:register-requirement
                        (sem:make-requirement :id "REQ-ALPHA-1" :standard "alpha@1"
                                              :summary "new")
                        :replace t)
                       :registered)))
        (is (equal "new" (sem:requirement-summary (sem:find-requirement "REQ-ALPHA-1"))))))))

(test requirements-are-listed-by-standard-and-by-id
  (let ((registry (%registry-with-requirements)))
    (sem:with-registry (registry)
      (dolist (id '("REQ-ALPHA-2" "REQ-ALPHA-1" "REQ-ALPHA-10"))
        (sem:register-requirement
         (sem:make-requirement :id id :standard "alpha@1")))
      (sem:register-requirement (sem:make-requirement :id "REQ-EMPTY-1" :standard "empty@1"))
      (is (equal '("REQ-ALPHA-1" "REQ-ALPHA-10" "REQ-ALPHA-2")
                 (mapcar #'sem:requirement-id (sem:requirements-of "alpha@1"))))
      (is (equal '("REQ-EMPTY-1")
                 (mapcar #'sem:requirement-id (sem:requirements-of "EMPTY@1"))))
      (is (null (sem:requirements-of "none@1"))))))

(defun %fixture-implementation () :implemented)

(test the-line-from-a-requirement-to-code-and-test-can-be-walked-both-ways
  (let ((registry (%registry-with-requirements)))
    (sem:with-registry (registry)
      (sem:register-requirement
       (sem:make-requirement :id "REQ-ALPHA-1" :standard "alpha@1"
                             :construct :triple :summary "a triple has three terms"
                             :tests '(a-test) :implementation '(%fixture-implementation)))
      (sem:register-requirement
       (sem:make-requirement :id "REQ-ALPHA-2" :standard "alpha@1"
                             :implementation '(%fixture-implementation other-fn)))
      (is (equal '("REQ-ALPHA-1" "REQ-ALPHA-2")
                 (mapcar #'sem:requirement-id
                         (sem:requirements-implemented-by '%fixture-implementation))))
      (is (equal '("REQ-ALPHA-2")
                 (mapcar #'sem:requirement-id (sem:requirements-implemented-by 'other-fn))))
      (is (null (sem:requirements-implemented-by 'nothing)))
      (is (equal '(a-test) (sem:tests-for-requirement "REQ-ALPHA-1")))
      (is (null (sem:tests-for-requirement "REQ-ALPHA-2")))
      (is (null (sem:tests-for-requirement "REQ-NONE-1"))))))

(test gaps-in-coverage-are-listed-with-their-kind
  (let ((registry (%registry-with-requirements)))
    (sem:with-registry (registry)
      (sem:register-requirement
       (sem:make-requirement :id "REQ-ALPHA-1" :standard "alpha@1"))
      (sem:register-requirement
       (sem:make-requirement :id "REQ-ALPHA-2" :standard "alpha@1"
                             :tests '(real-test missing-test)
                             :implementation '(%fixture-implementation not-defined)))
      (sem:register-requirement
       (sem:make-requirement :id "REQ-ALPHA-3" :standard "alpha@1"
                             :tests '(real-test)
                             :implementation '(%fixture-implementation)))
      (let ((gaps (sem:traceability-gaps
                   "alpha@1"
                   :test-exists-p (lambda (symbol) (eq symbol 'real-test)))))
        (is (equal '((:requirement "REQ-ALPHA-1" :gap :no-test)
                     (:requirement "REQ-ALPHA-1" :gap :no-implementation)
                     (:requirement "REQ-ALPHA-2" :gap :unknown-test
                      :symbol missing-test)
                     (:requirement "REQ-ALPHA-2" :gap :unknown-implementation
                      :symbol not-defined))
                   gaps))))))

(test a-standard-with-no-requirements-has-no-gaps-to-report
  (let ((registry (%registry-with-requirements)))
    (sem:with-registry (registry)
      (is (null (sem:traceability-gaps "alpha@1"))))))
