;;;; semantic/standard.lisp — what a standard is, as the platform records it
;;;;
;;;; PROMPT-SEMANTICA §3: identifier, name, version, release, official
;;;; specification, dependencies, normative documents, test suites,
;;;; implementation status, conformance status. The specification stays
;;;; where it is published: a standard here is a record about it, never a
;;;; simplified copy of it.

(in-package #:automa-gp/semantic)

(defstruct (spec-document (:constructor %make-spec-document) (:predicate nil))
  "One document of a standard: a Recommendation, an RFC, a wiki page."
  (id nil :type symbol :read-only t)
  (title "" :type string :read-only t)
  (url "" :type string :read-only t)
  (role :normative :type (member :normative :informative) :read-only t))

(defun spec-document-p (object)
  "True if OBJECT is a SPEC-DOCUMENT."
  (typep object (quote spec-document)))

(defun make-spec-document (&key id title url (role :normative))
  "A SPEC-DOCUMENT. ID is a keyword, TITLE the title the publisher gives it,
URL where it is published, ROLE :NORMATIVE or :INFORMATIVE."
  (%make-spec-document :id id :title title :url url :role role))

(defstruct (test-suite (:constructor %make-test-suite) (:predicate nil))
  "An official suite of tests of a standard, and where it is."
  (id nil :type symbol :read-only t)
  (name "" :type string :read-only t)
  (url nil :read-only t)
  (note nil :read-only t))

(defun test-suite-p (object)
  "True if OBJECT is a TEST-SUITE."
  (typep object (quote test-suite)))

(defun make-test-suite (&key id name url note)
  "A TEST-SUITE. URL is NIL for a suite that is known to exist and has not
been located yet; NOTE says so."
  (%make-test-suite :id id :name name :url url :note note))

(defstruct (construct (:constructor %make-construct) (:predicate nil))
  "One construct of a standard: a production of a grammar, an axiom type, a
class expression, a datatype. The catalog of a standard is the list of
these, and each carries the evidence for its level of support."
  (id nil :type symbol :read-only t)
  (name "" :type string :read-only t)
  (document nil :read-only t)
  (section nil :read-only t)
  (kind nil :read-only t)
  (evidence nil :type list :read-only t))

(defun construct-p (object)
  "True if OBJECT is a CONSTRUCT."
  (typep object (quote construct)))

(defun make-construct (&key id name document section kind evidence)
  "A CONSTRUCT. DOCUMENT is the id of the SPEC-DOCUMENT that defines it and
SECTION the section there. EVIDENCE is a list of EVIDENCE."
  (%make-construct :id id :name name :document document :section section
                   :kind kind :evidence evidence))

(defstruct (standard-definition (:conc-name standard-)
                                (:constructor %make-standard-definition)
                                (:predicate nil))
  "A standard: what it is, where it is published, what it depends on, what
it contains, and the evidence for what has been done with it."
  (identifier nil :type keyword :read-only t)
  (name "" :type string :read-only t)
  (version "" :type string :read-only t)
  (release "" :type string :read-only t)
  (maturity :recommendation
   :type (member :recommendation :candidate-recommendation :note :rfc
                 :living-document)
   :read-only t)
  (specification "" :type string :read-only t)
  (documents nil :type list :read-only t)
  (dependencies nil :type list :read-only t)
  (test-suites nil :type list :read-only t)
  (constructs nil :type list :read-only t)
  (catalog-status :pending :type (member :pending :partial :complete)
   :read-only t)
  (evidence nil :type list :read-only t)
  (note nil :read-only t))

(defun standard-definition-p (object)
  "True if OBJECT is a STANDARD-DEFINITION."
  (typep object (quote standard-definition)))

;;; ---------------------------------------------------------------------------
;;; Designators: standard@version
;;; ---------------------------------------------------------------------------

(defun designator (identifier version)
  "The text IDENTIFIER@VERSION that names a standard at a version, with
IDENTIFIER written in lower case."
  (format nil "~(~A~)@~A" identifier version))

(defun parse-designator (text)
  "Take TEXT, IDENTIFIER@VERSION or just IDENTIFIER, apart.
Returns (VALUES IDENTIFIER VERSION): IDENTIFIER a keyword, VERSION a string
or NIL. Signals STANDARD-RESOLUTION-ERROR for an empty identifier or version."
  (let* ((text (string-trim " " (string text)))
         (at (position #\@ text))
         (name (if at (subseq text 0 at) text))
         (version (and at (subseq text (1+ at)))))
    (when (or (zerop (length name))
              (and at (zerop (length version)))
              (find #\@ (or version "")))
      (error 'standard-resolution-error
             :code :bad-designator
             :message (format nil "~S is not a designator" text)
             :suggestion "write IDENTIFIER@VERSION, for example owl2@2"))
    (values (intern (string-upcase name) :keyword) version)))

(defun standard-designator (definition)
  "The designator of DEFINITION."
  (designator (standard-identifier definition) (standard-version definition)))

(defun make-standard-definition (&key identifier name version release
                                   (maturity :recommendation) specification
                                   documents dependencies test-suites
                                   constructs (catalog-status :pending)
                                   evidence note)
  "A STANDARD-DEFINITION. DEPENDENCIES are designators with a version, such
as \"rdf@1.1\": a dependency that does not say which version is not
reproducible. Signals STANDARD-RESOLUTION-ERROR for one that does not."
  (dolist (dependency dependencies)
    (multiple-value-bind (id version) (parse-designator dependency)
      (declare (ignore id))
      (unless version
        (error 'standard-resolution-error
               :code :unversioned-dependency
               :message (format nil "the dependency ~S has no version" dependency)
               :standard identifier :version version
               :suggestion "write IDENTIFIER@VERSION"))))
  (%make-standard-definition
   :identifier identifier :name name :version version :release release
   :maturity maturity :specification specification
   :documents documents :dependencies (mapcar (lambda (d) (string-downcase d))
                                              dependencies)
   :test-suites test-suites :constructs constructs
   :catalog-status catalog-status :evidence evidence :note note))

;;; ---------------------------------------------------------------------------
;;; Support and conformance, derived and never stored
;;; ---------------------------------------------------------------------------

(defun standard-support (definition)
  "What can be said about the support of DEFINITION, as a plist:
:CATALOG the catalog status; :CONSTRUCTS how many constructs are cataloged;
:LEVEL the lowest level among them, NIL when there are none or one has no
evidence; :BY-LEVEL an alist (LEVEL . COUNT), NIL for no support; and
:CLAIMABLE, true only when the catalog is :COMPLETE and every construct has
a level. A standard is called supported at :LEVEL only when :CLAIMABLE.
Otherwise the honest statement is that some constructs are, and the report
says which."
  (let* ((constructs (standard-constructs definition))
         (levels (mapcar (lambda (construct)
                           (evidenced-level (construct-evidence construct)))
                         constructs))
         (lowest (lowest-support-level levels))
         (counts nil))
    (dolist (level (append *support-levels* (list nil)))
      (let ((n (count level levels)))
        (when (plusp n) (push (cons level n) counts))))
    (list :catalog (standard-catalog-status definition)
          :constructs (length constructs)
          :level lowest
          :by-level (nreverse counts)
          :claimable (and (eq :complete (standard-catalog-status definition))
                          constructs
                          lowest
                          t))))

(defun standard-conformance-status (definition)
  "PASS, FAIL, PARTIAL or NONE for DEFINITION: the verdict of its
:CONFORMANCE-REPORT evidence, the worst one if there are several, NONE when
there is none. A standard with no report is not conformant, whatever else is
known about it."
  (let* ((reports (remove-if-not
                   (lambda (evidence)
                     (eq :conformance-report (evidence-kind evidence)))
                   (standard-evidence definition)))
         (verdicts (mapcar (lambda (evidence)
                             (conformance-verdict (evidence-passed evidence)
                                                  (evidence-failed evidence)
                                                  (evidence-unsupported evidence)))
                           reports)))
    (cond ((null verdicts) :none)
          ((member :fail verdicts) :fail)
          ((member :partial verdicts) :partial)
          ((member :none verdicts) :none)
          (t :pass))))
