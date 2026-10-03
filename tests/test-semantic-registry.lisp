;;;; tests/test-semantic-registry.lisp — the registry of standards, the shipped
;;;; catalog, and the support that is claimed for each

(in-package #:automa-gp/tests)

(def-suite semantic-registry-suite :in automa-gp-suite)
(in-suite semantic-registry-suite)

(defun %standard (identifier version &key dependencies constructs
                                       (catalog-status :pending) evidence)
  "A STANDARD-DEFINITION for a test."
  (sem:make-standard-definition
   :identifier identifier :name (string-downcase (symbol-name identifier))
   :version version :release "fixture"
   :specification "https://example.org/spec"
   :dependencies dependencies :constructs constructs
   :catalog-status catalog-status :evidence evidence))

(defun %fresh-registry (&rest definitions)
  (let ((registry (sem:make-registry)))
    (sem:with-registry (registry)
      (dolist (definition definitions)
        (sem:register-standard definition)))
    registry))

;;; ---------------------------------------------------------------------------
;;; Designators
;;; ---------------------------------------------------------------------------

(test a-designator-is-identifier-at-version
  "Each entry is (TEXT IDENTIFIER VERSION)."
  (loop for (text identifier version)
          in '(("owl2@2" :owl2 "2")
               ("OWL2@2" :owl2 "2")
               ("rdf@1.1" :rdf "1.1")
               ("wikibase-data-model@unversioned" :wikibase-data-model "unversioned")
               ("shacl" :shacl nil)
               ("  rdf@1.1  " :rdf "1.1"))
        do (multiple-value-bind (id v) (sem:parse-designator text)
             (is (eq identifier id) "~S" text)
             (is (equal version v) "~S" text)))
  (is (string= "owl2@2" (sem:designator :owl2 "2")))
  (is (string= "rdf@1.1" (sem:designator :RDF "1.1"))))

(test a-malformed-designator-is-a-resolution-error
  (dolist (text '("" "@1" "owl2@" "a@b@c" "@" "  "))
    (let ((condition (handler-case (sem:parse-designator text)
                       (sem:standard-resolution-error (c) c))))
      (is (typep condition 'sem:standard-resolution-error) "~S" text)
      (is (eq :bad-designator (sem:standards-error-code condition))))))

;;; ---------------------------------------------------------------------------
;;; Registering and finding
;;; ---------------------------------------------------------------------------

(test a-standard-is-registered-and-found-by-identifier-and-version
  (let ((registry (%fresh-registry (%standard :alpha "1") (%standard :alpha "2")
                                   (%standard :beta "1"))))
    (sem:with-registry (registry)
      (is (equal "1" (sem:standard-version (sem:find-standard :alpha "1"))))
      (is (equal "2" (sem:standard-version (sem:find-standard "alpha@2"))))
      (is (null (sem:find-standard :alpha "3")))
      (is (null (sem:find-standard :gamma)))
      (is (equal '("1" "2") (sem:standard-versions :alpha)))
      (is (equal '("alpha@1" "alpha@2" "beta@1")
                 (mapcar #'sem:standard-designator (sem:list-standards)))))))

(test no-version-means-the-one-version-or-an-error-naming-them
  (let ((registry (%fresh-registry (%standard :alpha "1") (%standard :alpha "2")
                                   (%standard :beta "7"))))
    (sem:with-registry (registry)
      (is (equal "7" (sem:standard-version (sem:find-standard :beta))))
      (let ((condition (handler-case (sem:find-standard :alpha)
                         (sem:standard-resolution-error (c) c))))
        (is (typep condition 'sem:standard-resolution-error))
        (is (eq :ambiguous-version (sem:standards-error-code condition)))
        (is (search "1, 2" (princ-to-string condition)))))))

(test a-duplicate-is-refused-unless-replacement-is-asked-for
  (let ((registry (%fresh-registry (%standard :alpha "1"))))
    (sem:with-registry (registry)
      (let ((condition (handler-case (sem:register-standard (%standard :alpha "1"))
                         (sem:standard-resolution-error (c) c))))
        (is (eq :duplicate-standard (sem:standards-error-code condition))))
      (let ((new (%standard :alpha "1" :dependencies nil)))
        (is (eq new (sem:register-standard new :replace t)))
        (is (eq new (sem:find-standard :alpha "1"))))
      ;; The restart does the same from a handler.
      (let ((newer (%standard :alpha "1")))
        (handler-bind ((sem:standard-resolution-error
                         (lambda (c)
                           (declare (ignore c))
                           (invoke-restart :replace-standard))))
          (sem:register-standard newer))
        (is (eq newer (sem:find-standard :alpha "1")))))))

(test a-dependency-must-say-which-version
  (let ((condition (handler-case (%standard :alpha "1" :dependencies '("beta"))
                     (sem:standard-resolution-error (c) c))))
    (is (typep condition 'sem:standard-resolution-error))
    (is (eq :unversioned-dependency (sem:standards-error-code condition))))
  (is (equal '("beta@2") (sem:standard-dependencies
                          (%standard :alpha "1" :dependencies '("BETA@2"))))))

;;; ---------------------------------------------------------------------------
;;; Closure over standards
;;; ---------------------------------------------------------------------------

(test the-closure-of-a-standard-is-its-dependencies-first
  (let ((registry (%fresh-registry
                   (%standard :a "1" :dependencies '("b@1" "c@1"))
                   (%standard :b "1" :dependencies '("d@1"))
                   (%standard :c "1" :dependencies '("d@1"))
                   (%standard :d "1"))))
    (sem:with-registry (registry)
      (is (equal '("d@1" "b@1" "c@1" "a@1")
                 (mapcar #'sem:standard-designator (sem:standard-closure "a@1"))))
      (is (equal '("d@1") (mapcar #'sem:standard-designator
                                  (sem:standard-closure "d@1")))))))

(test a-missing-dependency-names-what-needs-it
  (let ((registry (%fresh-registry (%standard :a "1" :dependencies '("b@1")))))
    (sem:with-registry (registry)
      (let ((condition (handler-case (sem:standard-closure "a@1")
                         (sem:dependency-missing (c) c))))
        (is (typep condition 'sem:dependency-missing))
        (is (equal "b@1" (sem:dependency-missing-name condition)))
        (is (equal "a@1" (sem:dependency-missing-required-by condition))))
      (let ((condition (handler-case (sem:standard-closure "nowhere@1")
                         (sem:dependency-missing (c) c))))
        (is (typep condition 'sem:dependency-missing))
        (is (equal "nowhere@1" (sem:dependency-missing-name condition))))
      ;; A closure is asked for a version: there is no guessing one.
      (signals sem:dependency-missing (sem:standard-closure "a")))))

(test a-cycle-among-standards-is-reported-with-its-designators
  (let ((registry (%fresh-registry
                   (%standard :x "1" :dependencies '("y@1"))
                   (%standard :y "1" :dependencies '("x@1")))))
    (sem:with-registry (registry)
      (let ((condition (handler-case (sem:standard-closure "x@1")
                         (sem:dependency-cycle (c) c))))
        (is (typep condition 'sem:dependency-cycle))
        (is (equal '("x@1" "y@1" "x@1")
                   (sem:dependency-cycle-path condition)))))))

;;; ---------------------------------------------------------------------------
;;; Support and conformance of a standard, derived from evidence
;;; ---------------------------------------------------------------------------

(defun %construct (id &optional (top nil))
  "A construct whose evidence reaches TOP, or has none when TOP is NIL."
  (sem:make-construct :id id :name (string-downcase (symbol-name id))
                      :evidence (and top (%evidence-for-every-level-up-to top))))

(test a-standard-with-no-catalog-claims-nothing
  (let ((support (sem:standard-support (%standard :alpha "1"))))
    (is (null (getf support :level)))
    (is (zerop (getf support :constructs)))
    (is (eq :pending (getf support :catalog)))
    (is (null (getf support :claimable)))
    (is (null (getf support :by-level)))))

(test the-level-of-a-standard-is-that-of-its-weakest-construct
  (let* ((definition (%standard :alpha "1"
                                :catalog-status :complete
                                :constructs (list (%construct :a :executable)
                                                  (%construct :b :validated)
                                                  (%construct :c :conformant))))
         (support (sem:standard-support definition)))
    (is (eq :validated (getf support :level)))
    (is (= 3 (getf support :constructs)))
    (is-true (getf support :claimable))
    (is (equal '((:validated . 1) (:executable . 1) (:conformant . 1))
               (getf support :by-level)))))

(test a-standard-is-claimable-only-with-a-complete-catalog-and-every-construct-levelled
  "Each entry is (CATALOG-STATUS TOPS CLAIMABLE): TOPS is the top level of
each construct, NIL for a construct with no evidence."
  (loop for (status tops claimable)
          in '((:complete (:parsed :parsed) t)
               (:complete (:parsed nil) nil)
               (:partial (:parsed :parsed) nil)
               (:pending (:parsed :parsed) nil)
               (:complete () nil))
        do (let ((support (sem:standard-support
                           (%standard :alpha "1" :catalog-status status
                                                 :constructs
                                                 (loop for top in tops
                                                       for i from 0
                                                       collect (%construct
                                                                (intern (format nil "C~D" i) :keyword)
                                                                top))))))
             (is (eq claimable (getf support :claimable))
                 "~S ~S" status tops))))

(test conformance-status-is-the-worst-verdict-of-the-reports
  "Each entry is (REPORTS STATUS), each report (PASSED FAILED UNSUPPORTED)."
  (loop for (reports status)
          in '((() :none)
               (((9 0 0)) :pass)
               (((9 0 0) (4 0 0)) :pass)
               (((9 0 0) (4 0 2)) :partial)
               (((9 0 0) (4 1 0)) :fail)
               (((9 0 2) (4 1 0)) :fail)
               (((0 0 0)) :none))
        do (let ((definition
                   (%standard :alpha "1"
                              :evidence (mapcar (lambda (counts)
                                                  (destructuring-bind (p f u) counts
                                                    (%evidence :conformant
                                                               :conformance-report p f u)))
                                                reports))))
             (is (eq status (sem:standard-conformance-status definition))
                 "~S" reports)))
  ;; Evidence that is not a conformance report is not conformance.
  (is (eq :none (sem:standard-conformance-status
                 (%standard :alpha "1" :evidence (list (%evidence :parsed :test-run 9)))))))

;;; ---------------------------------------------------------------------------
;;; The shipped catalog
;;; ---------------------------------------------------------------------------

(defun %shipped ()
  "The shipped standards, registered in a registry of their own."
  (let ((registry (sem:make-registry)))
    (values (sem:register-shipped-standards registry) registry)))

(test the-shipped-catalog-has-the-standards-the-prompts-name
  (multiple-value-bind (definitions registry) (%shipped)
    (is (= 16 (length definitions)))
    (sem:with-registry (registry)
      (dolist (designator '("rdf@1.1" "rdfs@1.1" "ntriples@1.1" "nquads@1.1"
                            "turtle@1.1" "rdfxml@1.1" "jsonld@1.1" "owl2@2"
                            "shacl@1.0" "sparql@1.1" "wikibase-data-model@unversioned"
                            "rdf12@1.2" "prov-o@2013" "xsd-datatypes@1.1"
                            "iri@rfc3987" "bcp47@rfc5646"))
        (is-true (sem:find-standard designator) "~S is not shipped" designator)))))

(test every-shipped-standard-says-where-it-is-published
  (dolist (definition (%shipped))
    (let ((designator (sem:standard-designator definition)))
      (is (uiop:string-prefix-p "https://" (sem:standard-specification definition))
          "~A: specification" designator)
      (is (plusp (length (sem:standard-name definition))) "~A: name" designator)
      (is (plusp (length (sem:standard-release definition))) "~A: release" designator)
      (is (sem:standard-documents definition) "~A: no documents" designator)
      (dolist (document (sem:standard-documents definition))
        (is (uiop:string-prefix-p "https://" (sem:spec-document-url document))
            "~A: ~S" designator (sem:spec-document-id document))
        (is (member (sem:spec-document-role document) '(:normative :informative))))
      (dolist (suite (sem:standard-test-suites definition))
        (is (or (null (sem:test-suite-url suite))
                (uiop:string-prefix-p "https://" (sem:test-suite-url suite)))
            "~A: ~A" designator (sem:test-suite-name suite))
        (when (null (sem:test-suite-url suite))
          (is (sem:test-suite-note suite)
              "~A: a suite with no URL says why" designator))))))

(test the-shipped-dependencies-are-all-registered-and-acyclic
  (multiple-value-bind (definitions registry) (%shipped)
    (sem:with-registry (registry)
      (dolist (definition definitions)
        (let ((closure (sem:standard-closure (sem:standard-designator definition))))
          (is (eq definition (car (last closure)))
              "~A is last in its own closure" (sem:standard-designator definition))
          (is (= (length closure)
                 (length (remove-duplicates closure))))))
      (is (equal '("iri@rfc3987" "bcp47@rfc5646" "xsd-datatypes@1.1" "rdf@1.1"
                   "sparql@1.1" "turtle@1.1" "shacl@1.0")
                 (mapcar #'sem:standard-designator (sem:standard-closure "shacl@1.0")))
          "SHACL needs what its normative references name"))))

(test where-a-specification-has-not-been-read-no-dependency-is-guessed
  "OWL 2 and SPARQL declare none, and say that is why."
  (multiple-value-bind (definitions registry) (%shipped)
    (declare (ignore definitions))
    (sem:with-registry (registry)
      (dolist (designator '("owl2@2" "sparql@1.1"))
        (let ((definition (sem:find-standard designator)))
          (is (null (sem:standard-dependencies definition)) "~A" designator)
          (is (search "normative references" (sem:standard-note definition))
              "~A" designator))))))

(test rdf-1.2-is-registered-as-what-it-is
  (multiple-value-bind (definitions registry) (%shipped)
    (declare (ignore definitions))
    (sem:with-registry (registry)
      (let ((definition (sem:find-standard "rdf12@1.2")))
        (is (eq :candidate-recommendation (sem:standard-maturity definition)))
        (is (search "Candidate Recommendation" (sem:standard-release definition)))
        (is (search "Not a Recommendation" (sem:standard-note definition)))))))

(test owl-2-keeps-its-two-semantics-as-two-documents
  (multiple-value-bind (definitions registry) (%shipped)
    (declare (ignore definitions))
    (sem:with-registry (registry)
      (let ((ids (mapcar #'sem:spec-document-id
                         (sem:standard-documents (sem:find-standard "owl2@2")))))
        (is (member :direct-semantics ids))
        (is (member :rdf-based-semantics ids))
        (is (member :syntax ids))
        (is (member :profiles ids))
        (is (member :conformance ids))))))

(test no-shipped-standard-claims-support-it-has-no-evidence-for
  "The truth today: nothing is implemented, so no standard has a catalog, a
construct, evidence, a level or a conformance verdict. The day one does, this
test is where that is written down, with its evidence."
  (dolist (definition (%shipped))
    (let ((designator (sem:standard-designator definition))
          (support (sem:standard-support definition)))
      (is (null (sem:standard-constructs definition)) "~A" designator)
      (is (null (sem:standard-evidence definition)) "~A" designator)
      (is (eq :pending (sem:standard-catalog-status definition)) "~A" designator)
      (is (null (getf support :level)) "~A" designator)
      (is (null (getf support :claimable)) "~A" designator)
      (is (eq :none (sem:standard-conformance-status definition)) "~A" designator))))

(test the-library-loads-with-the-shipped-standards-registered
  (is-true (sem:find-standard "owl2@2"))
  (is (>= (length (sem:list-standards)) 16)))

(test the-report-says-how-many-standards-have-any-support
  (multiple-value-bind (definitions registry) (%shipped)
    (declare (ignore definitions))
    (sem:with-registry (registry)
      (let* ((claimable nil)
             (text (with-output-to-string (out)
                     (setf claimable (sem:standards-report out)))))
        (is (eql 0 claimable))
        (is (search "16 standards registered, 0 with some support, 0 with a claimable level." text))
        (is (search "owl2@2" text))
        (is (search "candidate-recommendation" text))
        (is (search "parsed < represented < validated < semantically-implemented < executable < conformant" text))
        (is (null (search "  
" text)) "no trailing blanks")))))

(test the-report-counts-a-standard-once-it-has-evidence
  (let ((registry (%fresh-registry
                   (%standard :alpha "1" :catalog-status :complete
                                         :constructs (list (%construct :a :parsed)))
                   (%standard :beta "1" :catalog-status :pending
                                        :constructs (list (%construct :b :parsed)))
                   (%standard :gamma "1"))))
    (sem:with-registry (registry)
      (let* ((claimable nil)
             (text (with-output-to-string (out)
                     (setf claimable (sem:standards-report out)))))
        (is (eql 1 claimable) "only alpha has a complete catalog")
        (is (search "3 standards registered, 2 with some support, 1 with a claimable level." text))))))
