;;;; semantic/cli.lisp — the command line of the platform: modelc
;;;;
;;;; PROMPT-SEMANTICA §29 lists the commands. Only those that can work today
;;;; do: they read the registry. The others are named, with the phase that
;;;; brings them, and refuse with their own exit status, so that a script
;;;; never mistakes a command that does nothing for one that succeeded.
;;;;
;;;; Exit status: 0 done; 1 the command failed; 2 not a command, or its
;;;; arguments are wrong; 3 a planned command that does not exist yet.

(in-package #:automa-gp/semantic)

(defparameter *planned-commands*
  '((("standard" "fetch") . "S2 — acquisition")
    (("standard" "install") . "S2 — acquisition")
    (("ontology" "fetch") . "S2 — acquisition")
    (("ontology" "resolve") . "S2 — ontology resolver")
    (("ontology" "imports") . "S2 — ontology resolver")
    (("knowledge" "query") . "S6 — knowledge sources")
    (("validate") . "S4 — SHACL")
    (("reason") . "S3 — OWL reasoning")
    (("dump-model") . "S1 — canonical model")
    (("dump-ir") . "S9 — implementation model")
    (("generate") . "S9 — semantic compilation")
    (("build") . "S9 — semantic compilation")
    (("conform") . "S1 and following — conformance runner"))
  "The commands of PROMPT-SEMANTICA §29 that do not exist yet, each with the
phase of docs/piattaforma-semantica.md that brings it.")

(defun %usage (stream)
  (format stream "usage: modelc COMMAND [ARGUMENT...]~%~%~
                  commands that work today:~%~
                  ~2@Tstandard list              the registry, one line per standard~%~
                  ~2@Tstandard show ID@VERSION   what is known about one standard~%~
                  ~2@Tstandard closure ID@VERSION  the standard and what it depends on~%~
                  ~2@Trequirements ID@VERSION    requirements and what is not covered~%~
                  ~2@Thelp                        this text~%~%~
                  planned, not implemented (exit status 3):~%~:{~2@T~{~A~^ ~}~30T~A~%~}"
          (mapcar (lambda (entry)
                    (list (car entry) (cdr entry)))
                  *planned-commands*)))

(defun %show-standard (definition stream)
  (let ((support (standard-support definition)))
    (format stream "~A  ~A~%  release:        ~A~%  maturity:       ~(~A~)~%  ~
                    specification:  ~A~%  level:          ~A (catalog ~(~A~), ~D construct~:P)~%  ~
                    conformance:    ~(~A~)~%"
            (standard-designator definition) (standard-name definition)
            (standard-release definition) (standard-maturity definition)
            (standard-specification definition)
            (%level-text (getf support :level)) (getf support :catalog)
            (getf support :constructs)
            (standard-conformance-status definition))
    (format stream "  dependencies:   ~:[none declared~;~:*~{~A~^, ~}~]~%"
            (standard-dependencies definition))
    (format stream "  documents:~%")
    (dolist (document (standard-documents definition))
      (format stream "    ~(~A~)  ~A~%      ~A~%"
              (spec-document-role document) (spec-document-title document)
              (spec-document-url document)))
    (format stream "  test suites:~:[    none~;~]~%"
            (standard-test-suites definition))
    (dolist (suite (standard-test-suites definition))
      (format stream "    ~A  ~A~%" (test-suite-name suite)
              (or (test-suite-url suite) "(to be located)")))
    (when (standard-note definition)
      (format stream "  note: ~A~%" (standard-note definition)))))

(defun %command (arguments stream)
  "Run ARGUMENTS and return the exit status."
  (let ((verb (first arguments)))
    (cond
      ((or (null arguments) (member verb '("help" "--help" "-h") :test #'string=))
       (%usage stream)
       0)
      ((and (string= verb "standard") (equal (second arguments) "list")
            (null (cddr arguments)))
       (standards-report stream)
       0)
      ((and (string= verb "standard") (equal (second arguments) "show")
            (= 3 (length arguments)))
       (let ((definition (find-standard (third arguments))))
         (cond (definition (%show-standard definition stream) 0)
               (t (format stream "modelc: ~A is not registered~%" (third arguments))
                  1))))
      ((and (string= verb "standard") (equal (second arguments) "closure")
            (= 3 (length arguments)))
       (format stream "~{~A~%~}" (mapcar #'standard-designator
                                         (standard-closure (third arguments))))
       0)
      ((and (string= verb "requirements") (= 2 (length arguments)))
       (let ((requirements (requirements-of (second arguments)))
             (gaps (traceability-gaps (second arguments))))
         (format stream "~D requirement~:P of ~A~%" (length requirements)
                 (second arguments))
         (dolist (requirement requirements)
           (format stream "  ~A  ~A~%" (requirement-id requirement)
                   (requirement-summary requirement)))
         (format stream "~D gap~:P in coverage~%" (length gaps))
         (dolist (gap gaps)
           (format stream "  ~A  ~(~A~)~@[ ~S~]~%" (getf gap :requirement)
                   (getf gap :gap) (getf gap :symbol)))
         0))
      (t
       (let ((planned (find-if (lambda (entry)
                                 (let ((words (car entry)))
                                   (and (<= (length words) (length arguments))
                                        (every #'string= words arguments))))
                               *planned-commands*)))
         (cond
           (planned
            (format stream "modelc: ~{~A~^ ~} is not implemented. Planned: ~A.~%"
                    (car planned) (cdr planned))
            3)
           (t
            (format stream "modelc: ~{~A~^ ~} is not a command~%~%" arguments)
            (%usage stream)
            2)))))))

(defun modelc-main (arguments &key (stream *standard-output*))
  "Run the modelc command ARGUMENTS, a list of strings, writing to STREAM.
Returns the exit status: 0, 1, 2 or 3 as described at the top of this file.
A STANDARDS-ERROR is reported on STREAM and is status 1."
  (handler-case (%command arguments stream)
    (standards-error (condition)
      (format stream "modelc: ~A~%" condition)
      1)))
