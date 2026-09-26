;;;; tests/test-queries.lisp

(in-package #:automa-gp/tests)

(def-suite queries-suite :in automa-gp-suite)
(in-suite queries-suite)

(test query-facts-only
  (let ((ctx (create-context :name 'q
                             :facts '((device a) (device b)
                                      (power-state a on)))))
    (let ((hits (query '(device ?x) ctx :infer nil)))
      (is (= 2 (length hits)))
      (is (eq :fact (getf (first hits) :source))))))

(test query-with-backward-chain
  (let* ((ctx (create-context
               :name 'q
               :facts '((device interface-01)
                        (power-state interface-01 on)))))
    (register-rule! ctx
                    (make-rule :name 'powered-when-on
                               :if '((device ?d) (power-state ?d on))
                               :then '(powered ?d)))
    (let ((hits (query '(powered ?x) ctx :infer t)))
      (is (plusp (length hits)))
      (is (equal '(powered interface-01) (getf (first hits) :fact)))
      (is (equal 'interface-01
                 (cdr (assoc '?x (getf (first hits) :bindings) :test #'eq)))))))

(test query-bindings-helper
  (let ((ctx (create-context :facts '((device-type interface-01 audio-interface)))))
    (let ((binds (query-bindings '(device-type ?x audio-interface) ctx :infer nil)))
      (is (= 1 (length binds)))
      (is (equal 'interface-01 (cdr (assoc '?x (first binds) :test #'eq)))))))
