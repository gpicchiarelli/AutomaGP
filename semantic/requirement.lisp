;;;; semantic/requirement.lisp — requirements, and the line from one to code
;;;;
;;;; PROMPT-SEMANTICA §24 and §25: a requirement of a standard has an id, a
;;;; place in the specification, the construct it is about, the tests that
;;;; check it and the definitions that implement it. Then three questions
;;;; have answers: which part of the standard does this function implement,
;;;; which test checks this requirement, and what is not covered yet.
;;;;
;;;; A requirement's SUMMARY is the maintainer's own words. The text of the
;;;; specification is not copied here: it stays where it is published.

(in-package #:automa-gp/semantic)

(defstruct (requirement (:constructor %make-requirement) (:predicate nil))
  "One requirement of a standard, with what covers it."
  (id "" :type string :read-only t)
  (standard "" :type string :read-only t)
  (section nil :read-only t)
  (summary "" :type string :read-only t)
  (modality :must :type (member :must :should :may) :read-only t)
  (construct nil :read-only t)
  (tests nil :type list :read-only t)
  (implementation nil :type list :read-only t))

(defun requirement-p (object)
  "True if OBJECT is a REQUIREMENT."
  (typep object (quote requirement)))

(defun %valid-requirement-id-p (id)
  "True for REQ-NAME-0001: the prefix, a name in capitals, digits and
hyphens that neither starts nor ends with a hyphen nor holds two in a row,
and a number after the last hyphen."
  (and (stringp id)
       (uiop:string-prefix-p "REQ-" id)
       (let ((last (position #\- id :from-end t)))
         (and (> last 4)
              (let ((name (subseq id 4 last))
                    (digits (subseq id (1+ last))))
                (and (plusp (length digits))
                     (every #'digit-char-p digits)
                     (every (lambda (char)
                              (or (upper-case-p char) (digit-char-p char)
                                  (char= char #\-)))
                            name)
                     (char/= (char name 0) #\-)
                     (char/= (char name (1- (length name))) #\-)
                     (not (search "--" name))))))))

(defun make-requirement (&key id standard section (summary "") (modality :must)
                           construct tests implementation)
  "A REQUIREMENT. ID reads REQ-OWL2-SYNTAX-0001: the prefix, the name of a
group of requirements in capitals, and a number. STANDARD is the designator
of the standard, with its version. SUMMARY is in the maintainer's words.
TESTS are the symbols of the tests that check it, IMPLEMENTATION the symbols
of the definitions that implement it. Signals STANDARD-RESOLUTION-ERROR for
an id or a designator that is malformed."
  (unless (%valid-requirement-id-p id)
    (error 'standard-resolution-error
           :code :bad-requirement-id
           :message (format nil "~S is not a requirement id" id)
           :suggestion "write REQ-GROUP-0001, with the group in capitals"))
  (multiple-value-bind (identifier version) (parse-designator standard)
    (declare (ignore identifier))
    (unless version
      (error 'standard-resolution-error
             :code :unversioned-requirement
             :message (format nil "the requirement ~A names ~S, which has no version"
                              id standard)
             :suggestion "write IDENTIFIER@VERSION")))
  (%make-requirement :id id :standard (string-downcase standard)
                     :section section :summary summary :modality modality
                     :construct construct :tests tests
                     :implementation implementation))

(defun register-requirement (requirement &key replace)
  "Add REQUIREMENT to the registry. Its standard must be registered, its
construct, when the catalog of that standard has any, must be in it, and its
id must be new unless REPLACE is true; each failure is a
STANDARD-RESOLUTION-ERROR. Returns REQUIREMENT."
  (check-type requirement requirement)
  (let ((definition (find-standard (requirement-standard requirement)))
        (table (registry-requirements *registry*))
        (id (requirement-id requirement)))
    (unless definition
      (error 'standard-resolution-error
             :code :unknown-standard
             :message (format nil "~A is not registered; ~A cannot belong to it"
                              (requirement-standard requirement) id)
             :suggestion "register the standard first"))
    (let ((construct (requirement-construct requirement)))
      (when (and construct
                 (standard-constructs definition)
                 (not (find construct (standard-constructs definition)
                            :key #'construct-id)))
        (error 'standard-resolution-error
               :code :unknown-construct
               :message (format nil "~A names the construct ~S, which ~A does not catalog"
                                id construct (requirement-standard requirement))
               :standard (standard-identifier definition)
               :version (standard-version definition)
               :construct construct)))
    (when (and (gethash id table) (not replace))
      (error 'standard-resolution-error
             :code :duplicate-requirement
             :message (format nil "~A is already registered" id)
             :suggestion "register it with :REPLACE T, or use another id"))
    (setf (gethash id table) requirement)))

(defun find-requirement (id)
  "The requirement with ID, or NIL."
  (values (gethash id (registry-requirements *registry*))))

(defun requirements-of (designator)
  "The requirements of the standard DESIGNATOR names, by id."
  (let ((wanted (string-downcase designator))
        (found nil))
    (maphash (lambda (id requirement)
               (declare (ignore id))
               (when (string= wanted (requirement-standard requirement))
                 (push requirement found)))
             (registry-requirements *registry*))
    (sort found #'string< :key #'requirement-id)))

(defun requirements-implemented-by (symbol)
  "The requirements that name SYMBOL among their implementation, by id: the
answer to which part of a standard a function implements."
  (let ((found nil))
    (maphash (lambda (id requirement)
               (declare (ignore id))
               (when (member symbol (requirement-implementation requirement))
                 (push requirement found)))
             (registry-requirements *registry*))
    (sort found #'string< :key #'requirement-id)))

(defun tests-for-requirement (id)
  "The symbols of the tests that check the requirement ID: the answer to
which test verifies a piece of semantics."
  (let ((requirement (find-requirement id)))
    (and requirement (requirement-tests requirement))))

(defun traceability-gaps (designator &key (test-exists-p (constantly t))
                                       (implementation-exists-p
                                        (lambda (symbol)
                                          (or (fboundp symbol) (boundp symbol)
                                              (find-class symbol nil)))))
  "What is not covered, among the requirements of DESIGNATOR, as a list of
plists (:REQUIREMENT id :GAP kind [:SYMBOL symbol]). KIND is :NO-TEST for a
requirement no test checks, :NO-IMPLEMENTATION for one nothing implements,
:UNKNOWN-TEST and :UNKNOWN-IMPLEMENTATION for a symbol TEST-EXISTS-P or
IMPLEMENTATION-EXISTS-P does not accept. By default every test symbol is
taken to exist, since this package does not know FiveAM; a caller that does
passes the predicate that asks it."
  (let ((gaps nil))
    (dolist (requirement (requirements-of designator))
      (let ((id (requirement-id requirement)))
        (if (null (requirement-tests requirement))
            (push (list :requirement id :gap :no-test) gaps)
            (dolist (test (requirement-tests requirement))
              (unless (funcall test-exists-p test)
                (push (list :requirement id :gap :unknown-test :symbol test)
                      gaps))))
        (if (null (requirement-implementation requirement))
            (push (list :requirement id :gap :no-implementation) gaps)
            (dolist (symbol (requirement-implementation requirement))
              (unless (funcall implementation-exists-p symbol)
                (push (list :requirement id :gap :unknown-implementation
                            :symbol symbol)
                      gaps))))))
    (nreverse gaps)))
