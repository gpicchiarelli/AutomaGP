;;;; tests/test-semantic-support.lisp — levels of support and the evidence for them

(in-package #:automa-gp/tests)

(def-suite semantic-support-suite :in automa-gp-suite)
(in-suite semantic-support-suite)

(defun %evidence (level kind passed &optional (failed 0) (unsupported 0))
  (sem:make-evidence :level level :kind kind :subject "fixture"
                     :passed passed :failed failed :unsupported unsupported))

(defun %evidence-for-every-level-up-to (top &key (unsupported 0))
  "Evidence that establishes every level from :PARSED to TOP; the report for
:CONFORMANT is one that left UNSUPPORTED tests out."
  (loop for level in sem:*support-levels*
        collect (ecase level
                  ((:parsed :represented :validated :semantically-implemented)
                   (%evidence level :test-run 3))
                  (:executable (%evidence level :build 1))
                  (:conformant (%evidence level :conformance-report 9 0
                                          unsupported)))
        until (eq level top)))

(test levels-are-six-and-ordered
  (is (equal '(:parsed :represented :validated :semantically-implemented
               :executable :conformant)
             sem:*support-levels*))
  (loop for level in sem:*support-levels*
        for rank from 1
        do (is-true (sem:support-level-p level))
           (is (= rank (sem:support-level-rank level))))
  (is (zerop (sem:support-level-rank nil)))
  (is-false (sem:support-level-p :implemented))
  (signals type-error (sem:support-level-rank :implemented)))

(test comparing-levels
  "Each entry is (LEVEL OTHER AT-LEAST): NIL, no support, is below every level."
  (loop for (level other expected)
          in '((:parsed :parsed t) (:represented :parsed t)
               (:parsed :represented nil) (:conformant :executable t)
               (:executable :conformant nil) (nil :parsed nil)
               (:parsed nil t) (nil nil t))
        do (is (eq expected (sem:support-level>= level other))
               "~S >= ~S" level other)))

(test a-set-is-as-supported-as-its-weakest-member
  "Each entry is (LEVELS LOWEST)."
  (loop for (levels lowest)
          in '(((:executable :parsed :conformant) :parsed)
               ((:validated) :validated)
               ((:validated nil) nil)
               (() nil)
               ((nil nil) nil))
        do (is (eq lowest (sem:lowest-support-level levels)) "~S" levels)))

(test a-construct-is-implemented-from-its-semantics-upward
  (loop for (level status)
          in '((nil :not-implemented)
               (:parsed :partially-implemented)
               (:represented :partially-implemented)
               (:validated :partially-implemented)
               (:semantically-implemented :implemented)
               (:executable :implemented)
               (:conformant :implemented))
        do (is (eq status (sem:construct-status level)) "~S" level)))

(test a-conformance-verdict-needs-something-passed-and-nothing-failed-or-left-out
  "Each entry is (PASSED FAILED UNSUPPORTED VERDICT)."
  (loop for (passed failed unsupported verdict)
          in '((0 0 0 :none) (0 0 7 :none) (5 0 0 :pass) (5 1 0 :fail)
               (5 0 2 :partial) (0 3 0 :fail) (5 1 2 :fail) (1 0 0 :pass))
        do (is (eq verdict (sem:conformance-verdict passed failed unsupported))
               "~D passed, ~D failed, ~D left out" passed failed unsupported))
  (signals type-error (sem:conformance-verdict -1 0 0))
  (signals type-error (sem:conformance-verdict 1.5 0 0)))

(test evidence-establishes-a-level-only-of-the-right-kind-and-outcome
  "Each entry is (LEVEL KIND PASSED FAILED UNSUPPORTED ESTABLISHES)."
  (loop for (level kind passed failed unsupported expected)
          in '((:parsed :test-run 3 0 0 t)
               (:parsed :test-run 0 0 0 nil)
               (:parsed :test-run 3 1 0 nil)
               (:validated :test-run 3 0 0 t)
               (:semantically-implemented :test-run 1 0 0 t)
               (:semantically-implemented :build 1 0 0 nil)
               (:semantically-implemented :conformance-report 9 0 0 nil)
               (:executable :build 1 0 0 t)
               (:executable :build 1 1 0 nil)
               (:executable :test-run 5 0 0 nil)
               (:conformant :conformance-report 9 0 0 t)
               (:conformant :conformance-report 9 0 1 nil)
               (:conformant :conformance-report 9 1 0 nil)
               (:conformant :conformance-report 0 0 0 nil)
               (:conformant :test-run 9 0 0 nil))
        do (is (eq expected
                   (sem:evidence-establishes-level-p
                    (%evidence level kind passed failed unsupported)))
               "~S ~S ~D/~D/~D" level kind passed failed unsupported))
  (is-false (sem:evidence-establishes-level-p nil)))

(test evidence-refuses-a-level-or-a-kind-it-does-not-have
  (signals type-error (sem:make-evidence :level :implemented :kind :test-run))
  (signals type-error (sem:make-evidence :level :parsed :kind :hunch))
  (signals type-error (sem:make-evidence :level :parsed :kind :test-run
                                         :passed -1)))

(test a-level-is-evidenced-only-with-every-level-below-it
  (loop for top in sem:*support-levels*
        do (is (eq top (sem:evidenced-level
                        (%evidence-for-every-level-up-to top)))
               "evidence up to ~S" top))
  (is (null (sem:evidenced-level nil)))
  ;; Evidence for :EXECUTABLE alone proves nothing: nothing is parsed.
  (is (null (sem:evidenced-level (list (%evidence :executable :build 1)))))
  ;; A gap stops the climb at the level below it.
  (is (eq :represented
          (sem:evidenced-level
           (list (%evidence :parsed :test-run 3)
                 (%evidence :represented :test-run 3)
                 (%evidence :semantically-implemented :test-run 3)))))
  ;; A failing run does not establish its level.
  (is (eq :parsed
          (sem:evidenced-level
           (list (%evidence :parsed :test-run 3)
                 (%evidence :represented :test-run 3 1)))))
  ;; A conformance report that left tests out stops at :EXECUTABLE.
  (is (eq :executable
          (sem:evidenced-level
           (%evidence-for-every-level-up-to :conformant :unsupported 2)))))
