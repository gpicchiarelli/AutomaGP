;;;; tests/test-persistence.lisp — Phase 7 persistence service

(in-package #:automa-gp/tests)

(def-suite persistence-suite :in automa-gp-suite)
(in-suite persistence-suite)

(defun %persist-tmp (name)
  (uiop:merge-pathnames*
   (format nil "automa-gp-test-~A-~A.agp" name (get-universal-time))
   (uiop:temporary-directory)))

(defmacro with-persist-directory ((dir) &body body)
  "Run BODY with DIR bound to a fresh, empty directory that is deleted
afterwards with everything in it."
  `(let ((,dir (uiop:ensure-directory-pathname
                (uiop:merge-pathnames*
                 (format nil "automa-gp-persist-~D-~D/"
                         (get-universal-time)
                         (random 1000000 (make-random-state t)))
                 (uiop:temporary-directory)))))
     (ensure-directories-exist ,dir)
     (unwind-protect (progn ,@body)
       (uiop:delete-directory-tree ,dir :validate t
                                        :if-does-not-exist :ignore))))

(defmacro with-scratch-procedural-memory (&body body)
  "Run BODY with an empty procedural memory of its own, which no archive
file is loaded into unless BODY loads one."
  `(let ((*procedural-memory* nil)
         (*procedure-archive-autoload* nil)
         (automa-gp::*procedure-archive-loaded* t))
     ,@body))

(defun %write-text (path text)
  "Make PATH a UTF-8 file that holds TEXT."
  (with-open-file (out path :direction :output :if-exists :supersede
                            :external-format :utf-8)
    (write-string text out))
  path)

(defun %file-text (path)
  (uiop:read-file-string path :external-format :utf-8))

(defun %persistence-failure-of (thunk)
  "The PERSISTENCE-ERROR that calling THUNK signals, or NIL when it returns."
  (handler-case (progn (funcall thunk) nil)
    (persistence-error (c) c)))

(defun %data= (a b)
  "True when A and B are the same data: EQUAL, with simple vectors compared
element by element and uninterned symbols by name."
  (cond ((and (consp a) (consp b))
         (and (%data= (car a) (car b)) (%data= (cdr a) (cdr b))))
        ((and (simple-vector-p a) (simple-vector-p b))
         (and (= (length a) (length b)) (every #'%data= a b)))
        ((and (symbolp a) (symbolp b)
              (null (symbol-package a)) (null (symbol-package b)))
         (string= a b))
        (t (equal a b))))

(defun %lisp-read (text)
  "The one datum in TEXT as the Lisp reader reads it under standard syntax
in the package AUTOMA-GP, without evaluation."
  (with-standard-io-syntax
    (let ((*package* (find-package :automa-gp))
          (*read-eval* nil))
      (values (read-from-string text)))))

(defun %persist-rich-context ()
  "A context that holds three of everything a context keeps in order, an
unnamed rule, and two events."
  (let ((ctx (create-context
              :name 'rich
              :facts '((device interface-01) (label interface-01 "Scheda città"))
              :goals '((ready interface-01))
              :mode :simulate
              :meta '(:owner "test" :level 3))))
    (dolist (name '(item-a item-b item-c))
      (register-operator!
       ctx (make-operator :name name
                          :preconditions '((device ?d))
                          :add-list `((,name ?d))
                          :cost 2.5 :risk :high :reversible nil
                          :meta '(:note "kept")))
      (register-action!
       ctx (make-action :name name
                        :parameters '(?d)
                        :preconditions '((device ?d))
                        :effects `((,name ?d))
                        :cost 3 :risk :medium :reversible nil
                        :adapter 'files :authorization 'operator))
      (register-rule!
       ctx (make-rule :name name :if '((device ?d)) :then `(,name ?d)))
      (register-event-reaction!
       ctx (make-event-reaction :name name
                                :when '(file-created ?f)
                                :assert `((,name ?f))
                                :goals '((filed ?f)))))
    (register-rule! ctx (make-rule :if '((label ?d ?l)) :then '(labelled ?d)))
    (emit-event! ctx '(file-created "a.pdf"))
    (emit-event! ctx '(file-created "b.pdf"))
    ctx))

;;; ---------------------------------------------------------------------------
;;; Contexts and snapshots
;;; ---------------------------------------------------------------------------

(test suspend-resume-context-roundtrip
  (let* ((ctx (create-context
               :name 'studio
               :facts '((device interface-01) (power-state interface-01 off))
               :goals '((connection interface-01 computer))
               :mode :plan))
         (_ (register-operator!
             ctx
             (make-operator :name 'power-on
                            :preconditions '((device ?d) (power-state ?d off))
                            :add-list '((power-state ?d on))
                            :delete-list '((power-state ?d off))))
             )
         (_r (register-rule!
              ctx
              (make-rule :name 'device-fact
                         :if '(device ?d)
                         :then '(tracked ?d))))
         (form (suspend-context ctx))
         (restored (resume-context form)))
    (declare (ignore _ _r))
    (is (eq :context (car form)))
    (is (context-p restored))
    (is (eq 'studio (context-name restored)))
    (is (fact-p '(device interface-01) (context-facts restored)))
    (is (= 1 (length (context-operators restored))))
    (is (= 1 (length (context-rules restored))))
    (is (eq :plan (context-mode restored)))))

(test persist-and-restore-context-file
  (let* ((path (%persist-tmp "ctx"))
         (ctx (create-context :name 'alpha
                              :facts '((ok true))
                              :goals '((done true)))))
    (unwind-protect
         (progn
           (persist-context ctx path)
           (let ((loaded (restore-context path)))
             (is (context-p loaded))
             (is (eq 'alpha (context-name loaded)))
             (is (fact-p '(ok true) (context-facts loaded)))
             (is (equal '((done true)) (context-goals loaded)))))
      (uiop:delete-file-if-exists path))))

(test snapshot-save-load-apply
  (gp-clear-memory)
  (gp-reset)
  (gp-context :name 'studio)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off))))
  (gp-add-operator
   (make-operator :name 'connect
                  :preconditions '((device ?d) (power-state ?d on))
                  :add-list '((connection ?d computer))))
  (gp-knowledge-add '(device spare-01))
  (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
    (gp-remember-procedure :plan plan :name 'connect-iface))
  (let ((path (%persist-tmp "snap")))
    (unwind-protect
         (progn
           (gp-save path)
           (gp-clear-memory)
           (gp-reset)
           (is (null (gp-facts)))
           (let ((bundle (gp-load path)))
             (is (context-p (getf bundle :context)))
             (is (eq 'studio (context-name (gp-context))))
             (is (fact-p '(device interface-01) (gp-facts)))
             (is (knowledge-memory-p (getf bundle :knowledge)))
             (is (fact-p '(device spare-01)
                         (knowledge-memory-facts (gp-knowledge))))
             (is (procedure-p (gp-find-procedure 'connect-iface)))
             (is (plusp (length (gp-episodes))))))
      (uiop:delete-file-if-exists path))))

(test persistence-separate-from-planner
  "Persistence helpers are callable without invoking the planner."
  (let* ((ctx (create-context :name 'x :facts '((a 1))))
         (path (%persist-tmp "sep")))
    (unwind-protect
         (progn
           (is (pathnamep (persist-context ctx path)))
           (is (context-p (restore-context path))))
      (uiop:delete-file-if-exists path))))

(test context-roundtrip-keeps-every-slot-and-its-order
  "Operators, actions, rules, reactions and events come back in the order
they were saved in, however many times the context is saved and loaded."
  (let* ((ctx (%persist-rich-context))
         (form (serialize-context ctx))
         (names '(item-c item-b item-a)))
    (is (equal names (mapcar #'operator-name (context-operators ctx))))
    (let ((trip ctx))
      (dotimes (i 3)
        (setf trip (resume-context (suspend-context trip)))
        (is (equal form (serialize-context trip)))))
    (let ((restored (resume-context form)))
      (is (equal names (mapcar #'operator-name (context-operators restored))))
      (is (equal names (mapcar #'car (context-actions restored))))
      (is (equal names (mapcar #'action-name (actions-of restored))))
      (is (equal (mapcar #'rule-name (context-rules ctx))
                 (mapcar #'rule-name (context-rules restored))))
      (is (= 4 (length (context-rules restored))))
      (is (equal names (mapcar #'event-reaction-name
                               (context-event-reactions restored))))
      (is (equal '(("a.pdf") ("b.pdf"))
                 (mapcar #'event-data (context-events restored))))
      (is (eq :simulate (context-mode restored))))
    (with-persist-directory (dir)
      (let ((context-file (merge-pathnames "context.agp" dir))
            (snapshot-file (merge-pathnames "snapshot.agp" dir)))
        (persist-context ctx context-file)
        (save-snapshot snapshot-file :context ctx)
        (dolist (loaded (list (restore-context context-file)
                              (restore-context snapshot-file)
                              (getf (load-snapshot snapshot-file) :context)))
          (is (equal form (serialize-context loaded))))))))

(test events-emitted-after-a-restore-get-fresh-ids
  (let* ((form (let ((*event-counter* 0))
                 (serialize-context (%persist-rich-context))))
         (*event-counter* 0)
         (restored (resume-context form)))
    (emit-event! restored '(file-created "c.pdf"))
    (let ((ids (mapcar #'event-id (context-events restored))))
      (is (= 3 (length ids)))
      (is (equal ids (remove-duplicates ids))))
    (is (= 3 *event-counter*))))

(test deserializers-refuse-a-form-of-another-shape
  (loop for (deserialize tag)
          in '((deserialize-rule :rule) (deserialize-operator :operator)
               (deserialize-action :action) (deserialize-context :context)
               (resume-context :context) (deserialize-episode :episode)
               (deserialize-procedure :procedure)
               (deserialize-knowledge-memory :knowledge)
               (deserialize-episodic-memory :episodic)
               (deserialize-procedural-memory :procedural))
        do (dolist (form (list '(:bogus :name x) 42 nil "text"
                               (list tag :name) (list* tag :name 'x)))
             (is (typep (%persistence-failure-of
                         (lambda () (funcall deserialize form)))
                        'persistence-error)
                 "~A accepted ~S" deserialize form))))

;;; ---------------------------------------------------------------------------
;;; Files: written whole, read as data
;;; ---------------------------------------------------------------------------

(defparameter *persist-sample*
  (let ((shared (list 'shared "structure"))
        (fresh (make-symbol "FRESH")))
    (list :integers '(0 -1 255 4096 123456789012345678901234567890)
          :ratios '(1/3 -22/7)
          :floats '(1.5 -0.25 1.0e10 6.02e23 1.5d0 1.0d-300)
          :strings '("" "plain" "with \"quotes\" and \\ backslash"
                     "città è più" "two
lines")
          :characters '(#\a #\A #\Space #\Newline #\Tab #\( #\; #\\ #\" #\è)
          :symbols '(plain |Mixed Case| |with space| |123| |1E5| |a:b|
                     :keyword cl:car cl-user::persist-sample)
          :dotted '((a . b) (a b . c) (1 . 2.5))
          :quoted '('x #'car ''y)
          :vector #(1 "two" (three) #(4))
          :pathname #p"/tmp/some file.agp"
          :uninterned (list fresh fresh)
          :shared (list shared shared)))
  "Every kind of datum a file may hold.")

(test sexp-file-roundtrip-under-any-printer-and-reader-settings
  "What is written does not depend on the printer variables of the caller,
and what is read does not depend on its reader variables."
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "sample.agp" dir))
          (reference nil))
      (dolist (bindings `(()
                          ((*print-base* . 16) (*print-radix* . t))
                          ((*print-base* . 2) (*read-base* . 16))
                          ((*read-default-float-format* . double-float))
                          ((*print-case* . :downcase) (*print-escape* . nil)
                           (*print-readably* . nil))
                          ((*print-length* . 2) (*print-level* . 1)
                           (*print-pretty* . nil) (*print-circle* . nil))
                          ((*package* . ,(find-package :keyword)))
                          ((*package* . ,(find-package :cl-user))
                           (*read-eval* . nil))))
        (let ((back (progv (mapcar #'car bindings) (mapcar #'cdr bindings)
                      (write-sexp-file path *persist-sample*)
                      (read-sexp-file path)))
              (text (%file-text path)))
          (is (%data= *persist-sample* back) "Under ~S" bindings)
          (is (string= (or reference (setf reference text)) text)
              "The file differs under ~S" bindings)
          (destructuring-bind (first second) (getf back :shared)
            (is (eq first second)))
          (destructuring-bind (first second) (getf back :uninterned)
            (is (eq first second))
            (is (null (symbol-package first)))))))))

(test files-are-utf-8
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "utf-8.agp" dir)))
      (write-sexp-file path '(:label "città"))
      (let ((octets (with-open-file (in path :element-type '(unsigned-byte 8))
                      (let ((buffer (make-array (file-length in)
                                                :element-type '(unsigned-byte 8))))
                        (read-sequence buffer in)
                        buffer))))
        (is (search #(#xC3 #xA0) octets)))
      (is (equal '(:label "città") (read-sexp-file path))))))

(test data-reader-agrees-with-the-lisp-reader
  "On the syntax it accepts, the reader of files returns what READ returns."
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "syntax.agp" dir)))
      (dolist (text '("(a b c)" "(a . b)" "(a b . c)" "(a . (b c))" "()" "( )"
                      "nil" "NIL" "t"
                      "0" "-1" "+1" "1." "0005" "-0"
                      "123456789012345678901234567890"
                      "1/2" "-3/4" "+1/2"
                      "1.5" ".5" "+.5" "-.5e-3" "-1.5e3" "1e5" "1.e5" "1E+5"
                      "1e-5" "1.5d0" "1.0d-300" "1f0" "1s0" "1l0" "1.0e+5"
                      "(1 .5)" "(1 . .5)"
                      ;; tokens that look like numbers and are symbols
                      "1e" "1+" "+" "-" "1d" "1/" "/1" "1.0e" "1.0e+" "1.2.3"
                      "a.b" ".a" "1_000"
                      "car" "CAR" "Car" "c\\ar" "|car|" "|two words|" "||"
                      "\\123" "a#b"
                      ":key" "cl:car" "common-lisp::car" "cl-user::car"
                      "|COMMON-LISP|:car" "automa-gp::|odd name|"
                      "\"\"" "\"str\\\"ing\\\\\"" "\"due
righe\"" "\"città\"" "(a\"b\"c)"
                      "#\\a" "#\\A" "#\\Space" "#\\space" "#\\Newline" "#\\Tab"
                      "#\\(" "#\\)" "#\\;" "#\\\\" "#\\\"" "#\\|" "#\\è"
                      "#\\LATIN_SMALL_LETTER_E_WITH_GRAVE"
                      "(#\\a #\\b)" "(#\\a . #\\b)"
                      "#(1 2 3)" "#()" "#(a #(b) \"c\")"
                      "'x" "''x" "'(a b)" "#'car" "(quote x)"
                      "#:fresh" "#:|two words|" "(#:a . #:b)"
                      "(#1=(a b) #1#)" "(#1=#:g #1# #1#)" "(#1=\"s\" . #1#)"
                      "(#1=a #2=#1# #2#)" "(a . #1=(b) )"
                      "#P\"/tmp/x.agp\"" "#p\"x\""
                      "; a comment first
 (a ; and one inside
  b) ; and one after"))
        (%write-text path text)
        (is (%data= (%lisp-read text) (read-sexp-file path))
            "~S is read as ~S" text (read-sexp-file path))))))

(defvar *persist-canary* nil
  "Set by code that a loader must never run.")

(test data-reader-refuses-what-is-not-data
  "Code, structures, reader conditionals, circular data, more or less than
one datum and broken syntax are all a PERSISTENCE-ERROR that names the file."
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "refused.agp" dir))
          (*persist-canary* nil))
      (dolist (text '("" "   " "; only a comment" "(a b" "(a . b c)" "(a . )"
                      "(. a)" "(a . b . c)" ")" "a b" "(a) (b)" "a'b"
                      "\"open" "|open" "a\\" "..." "(a ... b)"
                      "#.(setf automa-gp/tests::*persist-canary* t)"
                      "(a #.(setf automa-gp/tests::*persist-canary* t))"
                      "#S(automa-gp::no-such-structure)" "#+sbcl 1" "#-sbcl 1"
                      "#b101" "#x1F" "#c(1 2)" "#*101" "#2A((1) (2))" "#3(1)"
                      "#|c|# a" "`(a ,b)" ",a"
                      "#1=(a . #1#)" "#1=(#1#)" "#1#" "(#1=a #1=b)" "#1=#1#"
                      "#" "#\\" "#\\nonsuch" "#'" "'" "#P 3"
                      "a:b:c" "a:::b" "a:" ":"
                      "automa-gp-no-such-package::x"
                      "1/0" "1e999"))
        (%write-text path text)
        (let ((failure (%persistence-failure-of
                        (lambda () (read-sexp-file path)))))
          (is (typep failure 'persistence-error) "~S was read" text)
          (when failure
            (is (equal path (persistence-error-path failure))))))
      (is (null *persist-canary*))
      (is (null (find-package "AUTOMA-GP-NO-SUCH-PACKAGE"))))))

(test loaders-never-evaluate-the-file
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "code.agp" dir))
          (*persist-canary* nil))
      (dolist (text '("#.(setf automa-gp/tests::*persist-canary* t)"
                      "(:snapshot :format-version \"0.7\"
                        :meta #.(setf automa-gp/tests::*persist-canary* t))"
                      "(:context
                        :name #.(setf automa-gp/tests::*persist-canary* t))"
                      "(:kind :automa-gp-procedure-archive :format 1
                        :saved-at #.(setf automa-gp/tests::*persist-canary* t)
                        :procedures nil)"))
        (%write-text path text)
        (dolist (loader '(read-sexp-file load-snapshot restore-context
                          load-procedure-archive gp-load gp-load-context
                          gp-archive-load))
          (with-scratch-procedural-memory
            (is (typep (%persistence-failure-of
                        (lambda () (funcall loader path)))
                       'persistence-error)
                "~A loaded ~S" loader text))
          (is (null *persist-canary*) "~A ran the code in ~S" loader text))))))

(test reading-creates-a-bounded-number-of-symbols
  (with-persist-directory (dir)
    (let* ((path (merge-pathnames "symbols.agp" dir))
           (names (loop for i below 6
                        collect (format nil "PERSIST-FRESH-~D-~D"
                                        (get-universal-time) i))))
      (flet ((forget ()
               (dolist (name names)
                 (let ((symbol (find-symbol name :automa-gp)))
                   (when symbol
                     (unintern symbol :automa-gp))))))
        (%write-text path (format nil "(~{~A~^ ~})" names))
        (unwind-protect
             (progn
               (loop for (limit readable)
                       in '((0 nil) (5 nil) (6 t) (7 t) (nil t))
                     do (forget)
                        (let ((*persistence-symbol-limit* limit))
                          (if readable
                              (is (= 6 (length (read-sexp-file path)))
                                  "Limit ~S" limit)
                              (signals persistence-error
                                (read-sexp-file path)))))
               ;; The symbols exist now, and a symbol that exists is not
               ;; counted.
               (let ((*persistence-symbol-limit* 0))
                 (is (= 6 (length (read-sexp-file path))))))
          (forget))))))

(test reading-creates-symbols-only-in-allowed-packages
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "packages.agp" dir))
          (package (make-package "AUTOMA-GP-PERSIST-SCRATCH" :use nil)))
      (unwind-protect
           (flet ((made ()
                    (find-symbol "MADE-BY-FILE" package)))
             (%write-text path "(automa-gp-persist-scratch::made-by-file)")
             (signals persistence-error (read-sexp-file path))
             (is (null (made)))
             ;; Allowed as the current package, by name, and by T.
             (loop for (packages current)
                     in `((("AUTOMA-GP") ,package)
                          (("AUTOMA-GP-PERSIST-SCRATCH") ,*package*)
                          (t ,*package*))
                   do (let ((*persistence-symbol-packages* packages)
                            (*package* current))
                        (is (eq (first (read-sexp-file path)) (made)))
                        (is (not (null (made))))
                        (unintern (made) package)))
             ;; A symbol that exists is read whatever its package.
             (intern "MADE-BY-FILE" package)
             (is (eq (made) (first (read-sexp-file path)))))
        (delete-package package)))))

(test reading-and-writing-stop-at-the-depth-limit
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "depth.agp" dir)))
      (flet ((nested-text (depth)
               (concatenate 'string
                            (make-string depth :initial-element #\()
                            (make-string depth :initial-element #\))))
             (nested-data (depth)
               (let ((data :leaf))
                 (dotimes (i depth data)
                   (setf data (list data))))))
        (loop for (limit depth readable)
                in '((1000 1000 t) (1000 1001 nil) (1000 100000 nil)
                     (10 10 t) (10 11 nil))
              do (%write-text path (nested-text depth))
                 (let ((*persistence-depth-limit* limit))
                   (if readable
                       (is (consp (read-sexp-file path)))
                       (signals persistence-error (read-sexp-file path)))))
        ;; What could not be read back is not written.
        (let ((*persistence-depth-limit* 10))
          (write-sexp-file path (nested-data 5))
          (signals persistence-error (write-sexp-file path (nested-data 50)))
          (is (equal (nested-data 5) (read-sexp-file path))))))))

(test a-failed-write-leaves-the-file-as-it-was
  "An object that cannot be printed as data stops the write before the file
is touched, and no temporary file stays behind."
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "kept.agp" dir))
          (circular (list 1 2)))
      (setf (cdr (last circular)) circular)
      (write-sexp-file path '(:kept "before"))
      (let ((before (%file-text path)))
        (dolist (unprintable (list #'car
                                   (make-hash-table)
                                   (make-condition 'simple-error)
                                   (make-context :name 'not-data)
                                   (find-package :automa-gp)
                                   *standard-output*
                                   circular))
          (signals persistence-error
            (write-sexp-file path (list :snapshot :meta unprintable)))
          (is (string= before (%file-text path)))
          (is (= 1 (length (uiop:directory-files dir)))))
        (signals persistence-error
          (write-sexp-file (merge-pathnames "never.agp" dir) (list #'car)))
        (is (= 1 (length (uiop:directory-files dir))))
        ;; The error is signalled where it can be reported: not under the
        ;; printer settings of the write.
        (is (null (block signalled
                    (handler-bind ((persistence-error
                                     (lambda (c)
                                       (return-from signalled
                                         (and *print-readably*
                                              (princ-to-string c))))))
                      (write-sexp-file path (list #'car))))))
        ;; A write that succeeds replaces the file and leaves only it.
        (write-sexp-file path '(:kept "after"))
        (is (equal '(:kept "after") (read-sexp-file path)))
        (is (= 1 (length (uiop:directory-files dir))))))))

(test a-failed-save-keeps-the-previous-snapshot
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "session.agp" dir)))
      (gp-clear-memory)
      (gp-reset)
      (gp-context :name 'kept)
      (gp-add-fact '(saved once))
      (gp-save path)
      (record-episode! :kind :event :payload (list :stream *standard-output*))
      (signals persistence-error (gp-save path))
      (gp-clear-memory)
      (gp-reset)
      (gp-load path)
      (is (eq 'kept (context-name (gp-context))))
      (is (fact-p '(saved once) (gp-facts))))))

;;; ---------------------------------------------------------------------------
;;; Paths
;;; ---------------------------------------------------------------------------

(test a-path-without-a-type-means-agp
  (loop for (path type) in '(("snap" "agp") (#p"snap" "agp") ("dir/snap" "agp")
                             ("snap.agp" "agp") ("snap.sexp" "sexp")
                             ("snap.v2" "v2") ("/tmp/dir.d/snap" "agp"))
        do (is (equal type (pathname-type
                            (ensure-snapshot-path path :ensure-directory nil)))
               "~S" path)))

(test relative-paths-resolve-once
  "A relative path lands under *DEFAULT-SNAPSHOT-DIRECTORY*, relative or
absolute, or under *DEFAULT-PATHNAME-DEFAULTS*, and is found there again."
  (with-persist-directory (dir)
    (let ((ctx (make-context :name 'placed)))
      (loop for (directory path file)
              in `((nil "plain" "plain.agp")
                   (nil "deeper/plain.agp" "deeper/plain.agp")
                   ("snaps/" "inner" "snaps/inner.agp")
                   (,(merge-pathnames "abs/" dir) "sub/inner" "abs/sub/inner.agp")
                   ("snaps/" ,(merge-pathnames "outside.agp" dir) "outside.agp"))
            do (let ((*default-pathname-defaults* dir)
                     (*default-snapshot-directory* directory))
                 (persist-context ctx path)
                 (is (probe-file (merge-pathnames file dir))
                     "~S under ~S" path directory)
                 (is (eq 'placed (context-name (restore-context path))))
                 (save-snapshot path :context ctx)
                 (is (eq 'placed (context-name
                                  (getf (load-snapshot path) :context)))))))))

(test a-snapshot-saved-under-a-bare-name-is-still-found
  "A string without a type once named a file without one."
  (with-persist-directory (dir)
    (let ((bare (namestring (merge-pathnames "bare" dir))))
      (%write-text bare "(:context :name automa-gp/tests::bare-context)")
      (is (eq 'bare-context (context-name (restore-context bare))))
      (persist-context (make-context :name 'typed-context) bare)
      (is (probe-file (merge-pathnames "bare.agp" dir)))
      (is (eq 'typed-context (context-name (restore-context bare)))))))

;;; ---------------------------------------------------------------------------
;;; Format versions and files of another kind
;;; ---------------------------------------------------------------------------

(test a-snapshot-of-another-format-version-is-refused-unless-continued
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "version.agp" dir))
          (context (serialize-context (make-context :name 'versioned))))
      (dolist (version '("99.0" "0.6" nil 7))
        (write-sexp-file path (list :snapshot :format-version version
                                              :context context))
        (dolist (loader '(load-snapshot restore-context))
          (let ((failure (%persistence-failure-of
                          (lambda () (funcall loader path)))))
            (is (typep failure 'persistence-version-error)
                "~A accepted the version ~S" loader version)
            (when failure
              (is (equal version (persistence-version-error-found failure)))
              (is (equal *persistence-format-version*
                         (persistence-version-error-expected failure)))
              (is (equal path (persistence-error-path failure)))))
          (let ((loaded (handler-bind ((persistence-version-error #'continue))
                          (funcall loader path))))
            (is (eq 'versioned
                    (context-name (if (context-p loaded)
                                      loaded
                                      (getf loaded :context)))))))))))

(test an-archive-of-another-format-is-refused-unless-continued
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "archive.agp" dir))
          (procedure (serialize-procedure
                      (make-procedure :name 'archived :goals '((done))))))
      (dolist (format '(2 nil "1"))
        (with-scratch-procedural-memory
          (write-sexp-file path (list :kind :automa-gp-procedure-archive
                                      :format format
                                      :procedures (list procedure)))
          (signals persistence-version-error (load-procedure-archive path))
          (is (null (find-procedure 'archived)))
          (handler-bind ((persistence-version-error #'continue))
            (load-procedure-archive path))
          (is (procedure-p (find-procedure 'archived))))))))

(test loaders-refuse-a-file-of-another-kind
  "A missing file, a file of another kind and a file whose sections are
malformed are a PERSISTENCE-ERROR that names the file."
  (with-persist-directory (dir)
    (let* ((path (merge-pathnames "kind.agp" dir))
           (version *persistence-format-version*)
           (context (serialize-context (make-context :name 'c)))
           (snapshot (make-snapshot :context (make-context :name 'c)))
           (archive (list :kind :automa-gp-procedure-archive
                          :format *procedure-archive-format*
                          :procedures nil)))
      (with-scratch-procedural-memory
        (loop for (loader form)
              in `((load-snapshot ,context)
                   (load-snapshot ,archive)
                   (load-snapshot 42)
                   (load-snapshot (:snapshot :format-version))
                   (load-snapshot (:snapshot :format-version ,version
                                             :context (:rule :name r)))
                   (load-snapshot (:snapshot :format-version ,version
                                             :context (:context :facts 5)))
                   (load-snapshot (:snapshot :format-version ,version
                                             :context (:context :mode :fly)))
                   (load-snapshot (:snapshot :format-version ,version
                                             :episodic (:episodic :limit -1)))
                   (load-snapshot (:snapshot :format-version ,version
                                             :knowledge (:knowledge :rules (r))))
                   (restore-context ,archive)
                   (restore-context ,(make-snapshot))
                   (restore-context (:context :name))
                   (load-procedure-archive ,snapshot)
                   (load-procedure-archive ,context)
                   (load-procedure-archive (:kind :automa-gp-procedure-archive))
                   (load-procedure-archive
                    (:kind :automa-gp-procedure-archive
                     :format ,*procedure-archive-format*
                     :procedures ((:procedure :name merged-first)
                                  (:rule :name not-a-procedure)))))
            do (write-sexp-file path form)
               (let ((failure (%persistence-failure-of
                               (lambda () (funcall loader path)))))
                 (is (typep failure 'persistence-error)
                     "~A accepted ~S" loader form)
                 (when failure
                   (is (equal (truename path)
                              (truename (persistence-error-path failure)))))))
        (is (null (find-procedure 'merged-first))))
      (let ((missing (merge-pathnames "missing.agp" dir)))
        (dolist (loader '(read-sexp-file load-snapshot restore-context
                          load-procedure-archive))
          (let ((failure (%persistence-failure-of
                          (lambda () (funcall loader missing)))))
            (is (typep failure 'persistence-error) "~A" loader)
            (when failure
              (is (equal missing (persistence-error-path failure))))))))))

;;; ---------------------------------------------------------------------------
;;; Procedure archive
;;; ---------------------------------------------------------------------------

(defun %persist-procedures (&rest names)
  "A procedural memory of one procedure for each of NAMES, in that order."
  (make-procedural-memory
   :procedures (mapcar (lambda (name)
                         (make-procedure :name name :goals `((,name done))))
                       names)))

(test an-archive-keeps-its-order-and-merges-nothing-on-failure
  (with-persist-directory (dir)
    (let ((path (merge-pathnames "order.agp" dir)))
      (flet ((names ()
               (mapcar #'procedure-name
                       (procedural-memory-procedures *procedural-memory*))))
        (with-scratch-procedural-memory
          (save-procedure-archive
           :path path :memory (%persist-procedures 'alpha 'beta 'gamma))
          (dotimes (trip 3)
            (setf *procedural-memory* nil)
            (load-procedure-archive path)
            (is (equal '(alpha beta gamma) (names)))
            (save-procedure-archive :path path))
          (write-sexp-file
           path (list :kind :automa-gp-procedure-archive
                      :format *procedure-archive-format*
                      :procedures (list (serialize-procedure
                                         (make-procedure :name 'delta))
                                        '(:rule :name not-a-procedure))))
          (signals persistence-error (load-procedure-archive path))
          (is (equal '(alpha beta gamma) (names))))))))

(test an-archive-path-finds-the-agp-or-the-sexp-file
  "LOAD-PROCEDURE-ARCHIVE reads the agp file, else its sexp sibling, for a
path with or without a type, given as a string or as a pathname."
  (with-persist-directory (dir)
    (loop for (written asked) in '(("a.agp" "a") ("b.sexp" "b")
                                   ("c.sexp" "c.agp") ("d.sexp" "d.sexp")
                                   ("e.agp" "e.agp"))
          do (save-procedure-archive :path (merge-pathnames written dir)
                                     :memory (%persist-procedures 'found))
             (dolist (path (list (merge-pathnames asked dir)
                                 (namestring (merge-pathnames asked dir))))
               (with-scratch-procedural-memory
                 (load-procedure-archive path)
                 (is (procedure-p (find-procedure 'found))
                     "~S written, ~S asked" written path))))))

(test an-applied-snapshot-is-not-overridden-by-the-archive-file
  "The procedural memory of a snapshot replaces the session's, and the
archive file is merged into it only on request."
  (with-persist-directory (dir)
    (let ((*procedure-archive-path* (merge-pathnames "archive.agp" dir))
          (*procedure-archive-autoload* t)
          (*procedure-archive-autosave* nil)
          (automa-gp::*procedure-archive-loaded* nil)
          (*procedural-memory* nil))
      (flet ((memory (origin)
               (make-procedural-memory
                :procedures (list (make-procedure :name 'shared
                                                  :goals `((from ,origin)))))))
        (save-procedure-archive :memory (memory 'archive))
        (apply-snapshot! (list :procedural (memory 'snapshot)))
        (is (equal '((from snapshot)) (procedure-goals (find-procedure 'shared))))
        (load-procedure-archive)
        (is (equal '((from archive))
                   (procedure-goals (find-procedure 'shared))))))))

;;; ---------------------------------------------------------------------------
;;; Files written before this format was checked
;;; ---------------------------------------------------------------------------

(defparameter *legacy-snapshot-text*
  "(:SNAPSHOT :FORMAT-VERSION \"0.7\" :SAVED-AT 3999857093 :META NIL :CONTEXT
 (:CONTEXT :NAME STUDIO :FACTS
  (#1=(DEVICE INTERFACE-01) #2=(LABEL INTERFACE-01 #3=\"Scheda audio città\")
   #4=(FILE-CREATED #5=\"doc.pdf\") (POWER-STATE INTERFACE-01 ON)
   (CONNECTION INTERFACE-01 COMPUTER))
  :GOALS NIL :RULES
  ((:RULE :NAME POWERED :IF ((POWER-STATE COMMON-LISP-USER::?D ON)) :THEN
    ((POWERED COMMON-LISP-USER::?D)) :META NIL))
  :OPERATORS
  ((:OPERATOR :NAME CONNECT :PARAMETERS NIL :PRECONDITIONS
    ((DEVICE COMMON-LISP-USER::?D) (POWER-STATE COMMON-LISP-USER::?D ON))
    :ADD-LIST ((CONNECTION COMMON-LISP-USER::?D COMPUTER)) :DELETE-LIST NIL
    :COST 2.5 :ACTION NIL :REVERSIBLE T :RISK :LOW :META NIL)
   (:OPERATOR :NAME POWER-ON :PARAMETERS NIL :PRECONDITIONS
    ((DEVICE COMMON-LISP-USER::?D) (POWER-STATE COMMON-LISP-USER::?D OFF))
    :ADD-LIST ((POWER-STATE COMMON-LISP-USER::?D ON)) :DELETE-LIST
    ((POWER-STATE COMMON-LISP-USER::?D OFF)) :COST 1 :ACTION NIL :REVERSIBLE T
    :RISK :LOW :META NIL))
  :ACTIONS NIL :EVENTS
  ((:EVENT :ID EVT-1 :TYPE FILE-CREATED :DATA (#5#) :TIMESTAMP 3999857093
    :STATUS :PENDING :META NIL))
  :EVENT-REACTIONS NIL :MODE :EXECUTE :META NIL)
 :KNOWLEDGE
 (:KNOWLEDGE :NAME DEFAULT :FACTS ((STUDIO READY)) :RULES NIL :META NIL)
 :EPISODIC
 (:EPISODIC :LIMIT 256 :EPISODES
  ((:EPISODE :ID COMMON-LISP-USER::EP-6 :KIND :EXECUTE :CONTEXT-NAME STUDIO
    :SUMMARY (:MODE :EXECUTE :STEPS 2) :SUCCESS T :PAYLOAD
    (:MODE :EXECUTE :STEPS
     ((:OPERATOR POWER-ON :BINDINGS ((COMMON-LISP-USER::?D . INTERFACE-01))
       :STATUS :EXECUTED :MISSING NIL :EXTERNAL NIL :BEFORE
       ((DEVICE INTERFACE-01) (POWER-STATE INTERFACE-01 OFF)
        (LABEL INTERFACE-01 #3#) (FILE-CREATED #5#))
       :AFTER
       ((DEVICE INTERFACE-01) (LABEL INTERFACE-01 #3#) (FILE-CREATED #5#)
        (POWER-STATE INTERFACE-01 ON))))
     :DIVERGENCES
     (:FACTS-ONLY-IN-A NIL :FACTS-ONLY-IN-B NIL :EQUAL T :KIND-A :EXPECTED
      :KIND-B :OBSERVED)
     :STRATEGY-EVENTS NIL)
    :TIMESTAMP 3999857093)
   (:EPISODE :ID COMMON-LISP-USER::EP-2 :KIND :PLAN :CONTEXT-NAME STUDIO
    :SUMMARY
    (:GOALS ((CONNECTION INTERFACE-01 COMPUTER)) :OPERATORS (POWER-ON CONNECT)
     :LENGTH 2)
    :SUCCESS T :PAYLOAD NIL :TIMESTAMP 3999857093)))
 :PROCEDURAL
 (:PROCEDURAL :PROCEDURES
  ((:PROCEDURE :NAME CONNECT-INTERFACE :GOALS
    ((CONNECTION INTERFACE-01 COMPUTER)) :STEPS
    ((:OPERATOR POWER-ON :BINDINGS ((COMMON-LISP-USER::?D . INTERFACE-01))
      :GOAL (POWER-STATE INTERFACE-01 ON) :SUBGOALS NIL :ACTION NIL :COST 1
      :ADDS ((POWER-STATE INTERFACE-01 ON)) :DELETES
      ((POWER-STATE INTERFACE-01 OFF)) :EFFECTS-STORED T :PRECONDITIONS
      ((DEVICE INTERFACE-01) (POWER-STATE INTERFACE-01 OFF))
      :PRECONDITIONS-STORED T :RISK :LOW :REVERSIBLE T)
     (:OPERATOR CONNECT :BINDINGS ((COMMON-LISP-USER::?D . INTERFACE-01)) :GOAL
      (CONNECTION INTERFACE-01 COMPUTER) :SUBGOALS
      ((POWER-STATE INTERFACE-01 ON)) :ACTION NIL :COST 2.5 :ADDS
      ((CONNECTION INTERFACE-01 COMPUTER)) :DELETES NIL :EFFECTS-STORED T
      :PRECONDITIONS ((DEVICE INTERFACE-01) (POWER-STATE INTERFACE-01 ON))
      :PRECONDITIONS-STORED T :RISK :LOW :REVERSIBLE T))
    :OPERATORS-USED (POWER-ON CONNECT) :INITIAL-STATE
    (#1# (POWER-STATE INTERFACE-01 OFF) #2# #4#) :SUCCESS-COUNT 1
    :FAILURE-COUNT 0 :LAST-SUCCESS-AT 3999857093 :LAST-FAILURE-AT NIL :SCORE
    0.7324082 :META (:FROM-PLAN T :CONTEXT STUDIO)))
  :META NIL))
"
  "A snapshot as GP-SAVE wrote it before files were read as data: symbols
without a prefix are in AUTOMA-GP, episode ids are symbols of the package
that was current, and shared structure carries #n= labels.")

(test a-snapshot-written-before-is-still-read
  (with-persist-directory (dir)
    (let* ((path (%write-text (merge-pathnames "legacy.agp" dir)
                              *legacy-snapshot-text*))
           (*event-counter* 0)
           (bundle (load-snapshot path))
           (context (getf bundle :context))
           (procedure (first (procedural-memory-procedures
                              (getf bundle :procedural)))))
      (flet ((names (objects)
               (mapcar #'symbol-name objects)))
        (is (equal "0.7" (getf bundle :format-version)))
        (is (string= "STUDIO" (context-name context)))
        (is (= 5 (length (context-facts context))))
        (is (equal "Scheda audio città" (third (second (context-facts context)))))
        (is (equal '("CONNECT" "POWER-ON")
                   (names (mapcar #'operator-name (context-operators context)))))
        (is (eql 2.5 (operator-cost (first (context-operators context)))))
        (is (equal '("POWERED")
                   (names (mapcar #'rule-name (context-rules context)))))
        (is (equal '("EVT-1")
                   (names (mapcar #'event-id (context-events context)))))
        (is (eq :execute (context-mode context)))
        (is (= 1 (length (knowledge-memory-facts (getf bundle :knowledge)))))
        (is (equal '(cl-user::ep-6 cl-user::ep-2)
                   (mapcar #'episode-id
                           (episodic-memory-episodes (getf bundle :episodic)))))
        (is (string= "CONNECT-INTERFACE" (procedure-name procedure)))
        (is (= 4 (length (procedure-initial-state procedure))))
        (is (= 2 (plan-length (procedure->plan procedure))))
        ;; The event that comes next does not take the id EVT-1 again.
        (is (string= "EVT-2" (event-id (make-event :type 'later))))))))
