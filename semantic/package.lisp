;;;; semantic/package.lisp — package of the semantic standards platform
;;;;
;;;; The platform of docs/PROMPT-SEMANTICA.md, as docs/piattaforma-semantica.md
;;;; reads it for this repository. What is here is its foundation: the
;;;; registry of standards, the levels of support and the evidence each one
;;;; needs, requirements and their traceability, typed diagnostics, and the
;;;; closure of a dependency graph. No standard is implemented yet; the
;;;; registry says so.

(defpackage #:automa-gp/semantic
  (:use #:cl)
  (:import-from #:automa-gp
                #:gp-error)
  (:export
   ;; diagnostics
   #:standards-error
   #:standards-error-code
   #:standards-error-message
   #:standards-error-source
   #:standards-error-location
   #:standards-error-standard
   #:standards-error-version
   #:standards-error-construct
   #:standards-error-suggestion
   #:standard-parse-error
   #:standard-resolution-error
   #:standard-dependency-error
   #:dependency-cycle
   #:dependency-cycle-path
   #:dependency-missing
   #:dependency-missing-name
   #:dependency-missing-required-by
   #:standard-semantic-error
   #:unsupported-construct
   #:implementation-error
   #:conformance-failure
   #:standard-runtime-error
   #:diagnostic
   #:diagnostic-p
   #:make-diagnostic
   #:diagnostic-severity
   #:diagnostic-code
   #:diagnostic-message
   #:diagnostic-source
   #:diagnostic-location
   #:diagnostic-standard
   #:diagnostic-version
   #:diagnostic-construct
   #:diagnostic-support
   #:diagnostic-suggestion
   #:*unsupported-policy*
   #:call-collecting-diagnostics
   #:collecting-diagnostics
   #:note-diagnostic
   #:report-unsupported
   ;; dependency closure
   #:dependency-closure
   ;; support levels and evidence
   #:*support-levels*
   #:support-level-p
   #:support-level-rank
   #:support-level>=
   #:lowest-support-level
   #:construct-status
   #:conformance-verdict
   #:evidence
   #:evidence-p
   #:make-evidence
   #:evidence-kind
   #:evidence-level
   #:evidence-subject
   #:evidence-passed
   #:evidence-failed
   #:evidence-unsupported
   #:evidence-reference
   #:evidence-recorded-at
   #:evidence-establishes-level-p
   #:evidenced-level
   ;; standards
   #:spec-document
   #:spec-document-p
   #:make-spec-document
   #:spec-document-id
   #:spec-document-title
   #:spec-document-url
   #:spec-document-role
   #:test-suite
   #:test-suite-p
   #:make-test-suite
   #:test-suite-id
   #:test-suite-name
   #:test-suite-url
   #:test-suite-note
   #:construct
   #:construct-p
   #:make-construct
   #:construct-id
   #:construct-name
   #:construct-document
   #:construct-section
   #:construct-kind
   #:construct-evidence
   #:standard-definition
   #:standard-definition-p
   #:make-standard-definition
   #:standard-identifier
   #:standard-name
   #:standard-version
   #:standard-release
   #:standard-maturity
   #:standard-specification
   #:standard-documents
   #:standard-dependencies
   #:standard-test-suites
   #:standard-constructs
   #:standard-catalog-status
   #:standard-evidence
   #:standard-note
   #:designator
   #:parse-designator
   #:standard-designator
   #:standard-support
   #:standard-conformance-status
   ;; registry
   #:registry
   #:registry-p
   #:make-registry
   #:*registry*
   #:call-with-registry
   #:with-registry
   #:register-standard
   #:find-standard
   #:standard-versions
   #:list-standards
   #:standard-closure
   #:register-shipped-standards
   ;; requirements and traceability
   #:requirement
   #:requirement-p
   #:make-requirement
   #:requirement-id
   #:requirement-standard
   #:requirement-section
   #:requirement-summary
   #:requirement-modality
   #:requirement-construct
   #:requirement-tests
   #:requirement-implementation
   #:register-requirement
   #:find-requirement
   #:requirements-of
   #:requirements-implemented-by
   #:tests-for-requirement
   #:traceability-gaps
   ;; report and command line
   #:standards-report
   #:modelc-main
   #:*planned-commands*))
