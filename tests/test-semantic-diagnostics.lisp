;;;; tests/test-semantic-diagnostics.lisp — typed failures and the rule that
;;;; nothing is lost silently

(in-package #:automa-gp/tests)

(def-suite semantic-diagnostics-suite :in automa-gp-suite)
(in-suite semantic-diagnostics-suite)

(test every-failure-of-the-platform-is-a-standards-error-with-its-own-code
  "Each entry is (CONDITION-TYPE CODE)."
  (loop for (type code)
          in '((sem:standard-parse-error :parse-error)
               (sem:standard-resolution-error :resolution-error)
               (sem:standard-dependency-error :dependency-error)
               (sem:dependency-cycle :dependency-cycle)
               (sem:dependency-missing :dependency-missing)
               (sem:standard-semantic-error :semantic-error)
               (sem:unsupported-construct :unsupported-construct)
               (sem:implementation-error :implementation-error)
               (sem:conformance-failure :conformance-failure)
               (sem:standard-runtime-error :runtime-error))
        do (let ((condition (make-condition type)))
             (is (typep condition 'sem:standards-error) "~S" type)
             (is (typep condition 'gp-error) "~S" type)
             (is (typep condition 'error) "~S" type)
             (is (eq code (sem:standards-error-code condition)) "~S" type))))

(test an-error-carries-what-section-28-asks-for
  (let ((condition (make-condition 'sem:standard-parse-error
                                   :message "a quote is not closed"
                                   :source "model.nt" :location 12
                                   :standard :ntriples :version "1.1"
                                   :construct :string-literal-quote
                                   :suggestion "close it with a quote")))
    (is (eq :parse-error (sem:standards-error-code condition)))
    (is (equal "a quote is not closed" (sem:standards-error-message condition)))
    (is (equal "model.nt" (sem:standards-error-source condition)))
    (is (= 12 (sem:standards-error-location condition)))
    (is (eq :ntriples (sem:standards-error-standard condition)))
    (is (equal "1.1" (sem:standards-error-version condition)))
    (is (eq :string-literal-quote (sem:standards-error-construct condition)))
    (is (equal "close it with a quote" (sem:standards-error-suggestion condition)))
    (is (string= "[parse-error] a quote is not closed (NTRIPLES@1.1, STRING-LITERAL-QUOTE) at model.nt:12. Suggestion: close it with a quote"
                 (princ-to-string condition)))))

(test an-error-reports-only-what-is-known
  (is (string= "[parse-error] the standards platform could not go on"
               (princ-to-string (make-condition 'sem:standard-parse-error
                                                :message nil))))
  ;; A version with no standard is not printed in the place of a source.
  (is (string= "[parse-error] oops (NTRIPLES)"
               (princ-to-string (make-condition 'sem:standard-parse-error
                                                :message "oops" :standard :ntriples))))
  (is (string= "[parse-error] oops (STRING)"
               (princ-to-string (make-condition 'sem:standard-parse-error
                                                :message "oops" :version "1.1"
                                                :construct :string))))
  (is (string= "[parse-error] oops at 7"
               (princ-to-string (make-condition 'sem:standard-parse-error
                                                :message "oops" :location 7))))
  (is (string= "[runtime-error] it broke at here"
               (princ-to-string (make-condition 'sem:standard-runtime-error
                                                :message "it broke"
                                                :source "here")))))

(test a-missing-dependency-names-what-was-asked-for-and-by-whom
  (let ((condition (make-condition 'sem:dependency-missing
                                   :name "rdf@1.1" :required-by "ntriples@1.1")))
    (is (string= "[dependency-missing] rdf@1.1 is required by ntriples@1.1 but is not registered"
                 (princ-to-string condition)))
    (is (equal "rdf@1.1" (sem:dependency-missing-name condition)))
    (is (equal "ntriples@1.1" (sem:dependency-missing-required-by condition)))))

(test a-diagnostic-has-defaults-and-refuses-nonsense
  (let ((diagnostic (sem:make-diagnostic :code :x :message "m")))
    (is (eq :warning (sem:diagnostic-severity diagnostic)))
    (is (null (sem:diagnostic-support diagnostic)))
    (is (eq :x (sem:diagnostic-code diagnostic))))
  (loop for support in '(:implemented :partially-implemented :not-implemented
                         :invalid nil)
        do (is (eq support (sem:diagnostic-support
                            (sem:make-diagnostic :support support)))))
  (signals type-error (sem:make-diagnostic :severity :fatal))
  (signals type-error (sem:make-diagnostic :support :maybe)))

(test diagnostics-are-collected-in-the-order-they-are-noted
  (multiple-value-bind (result diagnostics)
      (sem:collecting-diagnostics
        (sem:note-diagnostic :severity :info :code :one)
        (sem:note-diagnostic :severity :warning :code :two)
        (sem:note-diagnostic :severity :error :code :three)
        :result)
    (is (eq :result result))
    (is (equal '(:one :two :three) (mapcar #'sem:diagnostic-code diagnostics)))))

(test collectors-nest-and-do-not-leak
  (multiple-value-bind (outer-result outer)
      (sem:collecting-diagnostics
        (sem:note-diagnostic :severity :info :code :before)
        (multiple-value-bind (inner-result inner)
            (sem:collecting-diagnostics
              (sem:note-diagnostic :severity :info :code :inside)
              :inner)
          (is (eq :inner inner-result))
          (is (equal '(:inside) (mapcar #'sem:diagnostic-code inner))))
        (sem:note-diagnostic :severity :info :code :after)
        :outer)
    (is (eq :outer outer-result))
    (is (equal '(:before :after) (mapcar #'sem:diagnostic-code outer)))))

(test a-diagnostic-that-would-be-lost-is-signalled-instead
  "Without a collector an :ERROR or :WARNING is not dropped: it is signalled.
An :INFO has nothing a caller must act on and is returned."
  (loop for severity in '(:error :warning)
        do (let ((condition (handler-case
                                (sem:note-diagnostic :severity severity
                                                     :code :lost
                                                     :message "x"
                                                     :standard :owl2)
                              (sem:standards-error (c) c))))
             (is (typep condition 'sem:standards-error) "~S" severity)
             (is (eq :lost (sem:standards-error-code condition)))
             (is (eq :owl2 (sem:standards-error-standard condition)))))
  (is (eq :info (sem:diagnostic-severity
                 (sem:note-diagnostic :severity :info :code :fyi)))))

(test an-unsupported-construct-is-signalled-with-a-way-to-go-on
  (let ((signalled nil))
    (multiple-value-bind (result diagnostics)
        (sem:collecting-diagnostics
          (handler-bind ((sem:unsupported-construct
                           (lambda (condition)
                             (setf signalled condition)
                             (invoke-restart :continue-unsupported))))
            (sem:report-unsupported :owl-key :standard :owl2 :version "2"
                                             :source "model.ofn" :location 4
                                             :suggestion "remove the HasKey axiom")
            :went-on))
      (is (eq :went-on result))
      (is (typep signalled 'sem:unsupported-construct))
      (is (eq :owl-key (sem:standards-error-construct signalled)))
      (is (= 1 (length diagnostics)) "the diagnostic stays on record")
      (let ((diagnostic (first diagnostics)))
        (is (eq :not-implemented (sem:diagnostic-support diagnostic)))
        (is (eq :error (sem:diagnostic-severity diagnostic)))
        (is (eq :owl-key (sem:diagnostic-construct diagnostic)))
        (is (equal "model.ofn" (sem:diagnostic-source diagnostic)))
        (is (= 4 (sem:diagnostic-location diagnostic)))))))

(test an-unsupported-construct-with-no-handler-is-not-ignored
  (signals sem:unsupported-construct
    (sem:collecting-diagnostics (sem:report-unsupported :x)))
  (signals sem:unsupported-construct (sem:report-unsupported :x)))

(test the-record-policy-records-and-goes-on-only-with-a-collector
  (let ((sem:*unsupported-policy* :record))
    (multiple-value-bind (result diagnostics)
        (sem:collecting-diagnostics
          (sem:report-unsupported :a)
          (sem:report-unsupported :b)
          :done)
      (is (eq :done result))
      (is (equal '(:a :b) (mapcar #'sem:diagnostic-construct diagnostics))))
    ;; With nowhere to record it, the policy does not let a construct vanish.
    (signals sem:unsupported-construct (sem:report-unsupported :c))))

(test every-unsupported-construct-ends-up-recorded-or-signalled
  "Whatever the policy and whatever the collector, none vanishes: a property
over the four combinations."
  (loop for policy in '(:signal :record)
        do (dolist (collector '(t nil))
             (let* ((sem:*unsupported-policy* policy)
                    (signalled 0)
                    (recorded 0))
               (flet ((attempt ()
                        (handler-bind ((sem:unsupported-construct
                                         (lambda (condition)
                                           (declare (ignore condition))
                                           (incf signalled)
                                           (invoke-restart :continue-unsupported))))
                          (sem:report-unsupported :thing))))
                 (if collector
                     (setf recorded (length (nth-value 1 (sem:collecting-diagnostics (attempt)))))
                     (attempt)))
               (is (plusp (+ signalled recorded))
                   "policy ~S, collector ~S: lost" policy collector)))))
