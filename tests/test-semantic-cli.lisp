;;;; tests/test-semantic-cli.lisp — modelc: what works answers, what does not says so

(in-package #:automa-gp/tests)

(def-suite semantic-cli-suite :in automa-gp-suite)
(in-suite semantic-cli-suite)

(defun %modelc (&rest arguments)
  "Run modelc on ARGUMENTS. Returns (VALUES STATUS OUTPUT)."
  (let* ((status nil)
         (output (with-output-to-string (stream)
                   (setf status (sem:modelc-main arguments :stream stream)))))
    (values status output)))

(test modelc-answers-what-it-can-from-the-registry
  "Each entry is (ARGUMENTS STATUS SUBSTRINGS)."
  (loop for (arguments status substrings)
          in '((() 0 ("usage: modelc" "commands that work today"))
               (("help") 0 ("usage: modelc"))
               (("--help") 0 ("usage: modelc"))
               (("standard" "list") 0 ("owl2@2" "shacl@1.0" "16 standards registered"))
               (("standard" "show" "owl2@2") 0
                ("OWL 2 Web Ontology Language" "Direct Semantics" "level:          none"
                 "https://www.w3.org/TR/owl2-overview/" "(to be located)"))
               (("standard" "show" "rdf@1.1") 0
                ("dependencies:   iri@rfc3987, bcp47@rfc5646, xsd-datatypes@1.1"))
               (("standard" "show" "OWL2@2") 0 ("owl2@2"))
               (("standard" "closure" "ntriples@1.1") 0
                ("iri@rfc3987" "rdf@1.1" "ntriples@1.1"))
               (("requirements" "owl2@2") 0 ("0 requirements of owl2@2" "0 gaps in coverage")))
        do (multiple-value-bind (code output) (apply #'%modelc arguments)
             (is (= status code) "~S -> ~D" arguments code)
             (dolist (substring substrings)
               (is (search substring output) "~S lacks ~S" arguments substring)))))

(test modelc-reports-a-registry-failure-in-a-line-and-status-1
  (loop for arguments in '(("standard" "show" "nowhere@1")
                           ("standard" "show" "owl2@9")
                           ("standard" "closure" "nowhere@1")
                           ("standard" "closure" "owl2")
                           ("standard" "show" "@1"))
        do (multiple-value-bind (code output) (apply #'%modelc arguments)
             (is (= 1 code) "~S" arguments)
             (is (uiop:string-prefix-p "modelc: " output) "~S: ~S" arguments output)
             (is (= 1 (count #\Newline output)) "one line: ~S" output))))

(test modelc-refuses-a-planned-command-with-its-own-status-and-the-phase
  (dolist (entry sem:*planned-commands*)
    (multiple-value-bind (code output) (apply #'%modelc (append (car entry) '("x")))
      (is (= 3 code) "~S" (car entry))
      (is (search "is not implemented" output) "~S" (car entry))
      (is (search (cdr entry) output) "~S names its phase" (car entry))))
  ;; Every command the prompt lists is either implemented or planned.
  (is (= 13 (length sem:*planned-commands*))))

(test modelc-refuses-what-is-not-a-command-with-status-2
  (dolist (arguments '(("bogus") ("standard") ("standard" "list" "extra")
                       ("standard" "show") ("requirements") ("standard" "nuke" "x")))
    (multiple-value-bind (code output) (apply #'%modelc arguments)
      (is (= 2 code) "~S" arguments)
      (is (search "is not a command" output) "~S" arguments)
      (is (search "usage: modelc" output)))))

(test the-usage-lists-every-planned-command-aligned-with-its-phase
  (multiple-value-bind (code output) (%modelc "help")
    (declare (ignore code))
    (dolist (entry sem:*planned-commands*)
      (is (search (format nil "~{~A~^ ~}" (car entry)) output))
      (is (search (cdr entry) output)))
    (is (null (search "((" output)) "no list printed as a list")))
