;;;; tests/test-json.lisp — the JSON codec, and how the JSON façade reads a body

(in-package #:automa-gp/tests)

(def-suite json-suite :in automa-gp-suite)

(in-suite json-suite)

(defun %chars (&rest codes)
  "A string of the characters with CODES."
  (map 'string #'code-char codes))

(defun %json-string-text (&rest pieces)
  "A JSON string token made of PIECES, with the quotes around it."
  (format nil "\"~{~A~}\"" pieces))

;;; ---------------------------------------------------------------------------
;;; Encoder
;;; ---------------------------------------------------------------------------

(test json-encodes-every-control-character-as-an-escape
  (loop for code from 0 below 32
        for json = (lisp->json (%chars 97 code 98))
        do (is (every (lambda (c) (>= (char-code c) 32)) json)
               "U+~4,'0X is written raw" code)
           (is (string= (%chars 97 code 98) (json->lisp json))
               "U+~4,'0X does not survive a round trip" code))
  (loop for (code escape) in '((8 "\\b") (9 "\\t") (10 "\\n") (12 "\\f")
                               (13 "\\r") (27 "\\u001B") (34 "\\\"")
                               (92 "\\\\"))
        do (is (string= (%json-string-text escape)
                        (lisp->json (%chars code))))))

(test json-encodes-numbers-as-json-numerals
  (loop for (number text) in '((0 "0") (-17 "-17") (1.0d0 "1.0") (0.5 "0.5")
                               (-2.5d0 "-2.5") (1/2 "0.5") (-3/4 "-0.75")
                               (1d20 "1.0e20") (1.5d-7 "1.5e-7")
                               (123456789012345678901234567890
                                "123456789012345678901234567890"))
        do (is (string= text (lisp->json number))
               "~S encodes as ~A" number (lisp->json number)))
  ;; The reader settings of the image never reach the text.
  (let ((*read-default-float-format* 'double-float)
        (*print-base* 16)
        (*print-radix* t))
    (is (string= "[255,0.5,0.25]" (lisp->json (vector 255 0.5 0.25d0)))))
  ;; A ratio is the nearest double, and reads back as a number.
  (is (< (abs (- 1/3 (rational (let ((*read-default-float-format* 'double-float))
                                 (json->lisp (lisp->json 1/3))))))
         1d-15))
  ;; JSON has no numeral for these: they are strings, never bare tokens.
  (is (stringp (json->lisp (lisp->json #c(1 2))))))

(test json-encodes-the-lisp-shapes
  (loop for (value text) in `((t "true") (nil "false") (:null "null")
                              (,(json-array nil) "[]")
                              ((:a 1 :b-c "x") "{\"a\":1,\"b-c\":\"x\"}")
                              ((:a 1 2) "[\":A\",1,2]")
                              ((a . b) "[\"A\",\"B\"]")
                              (,(vector 1 "two" :three) "[1,\"two\",\":THREE\"]")
                              ((power-state interface-01 on)
                               "[\"POWER-STATE\",\"INTERFACE-01\",\"ON\"]"))
        do (is (string= text (lisp->json value))))
  (is (string= "\"a\\\"b\"" (json-escape-string "a\"b")))
  (is (string= "\"ON\"" (json-escape-string 'on))))

;;; ---------------------------------------------------------------------------
;;; Decoder
;;; ---------------------------------------------------------------------------

(test json-decodes-every-escape
  (loop for (escape . codes) in '(("\\\"" 34) ("\\\\" 92) ("\\/" 47)
                                  ("\\b" 8) ("\\f" 12) ("\\n" 10)
                                  ("\\r" 13) ("\\t" 9)
                                  ("\\u00e8" #xE8) ("\\u00E8" #xE8)
                                  ("\\u0000" 0) ("\\u20AC" #x20AC)
                                  ("\\ud83d\\ude00" #x1F600)
                                  ("\\uD834\\uDD1E" #x1D11E)
                                  ("caff\\u00e8" 99 97 102 102 #xE8))
        do (is (string= (apply #'%chars codes)
                        (json->lisp (%json-string-text escape)))
               "~A decodes wrongly" escape))
  ;; What the encoder does not escape passes through as written.
  (let ((text (%chars 99 97 102 102 #xE8 32 #x1F600)))
    (is (string= text (json->lisp (lisp->json text))))))

(test json-refuses-text-that-is-not-json
  (dolist (text (list "" "   " "{oops" "{\"a\" 1}" "{\"a\":1,}" "[1,]" "[1 2]"
                      "[1" "\"abc" "\"a\\" "\"\\x\"" "\"\\u12\"" "\"\\u12g4\""
                      "\"\\u+123\"" "\"\\ud83d\"" "\"\\ud83dx\""
                      "\"\\ud83d\\u0041\"" "\"\\ude00\""
                      "-" "-a" "1e" "1e+" "1." ".5" "01" "-01" "+1" "1.e3"
                      "tru" "nul" "falsy" "1 2" "{} x" "'a'"
                      (%chars #x663)))
    (signals json-parse-error (json->lisp text)))
  (handler-case (json->lisp "[1, oops]")
    (json-parse-error (c)
      (is (= 4 (json-parse-error-position c)))
      (is (search "at 4" (princ-to-string c)))
      (is (typep c 'parse-error)))))

(test json-decodes-numbers-without-the-lisp-reader
  (let ((*read-default-float-format* 'single-float))
    (loop for (text number) in '(("0" 0) ("-0" 0) ("17" 17) ("-17" -17)
                                 ("123456789012345678901234567890"
                                  123456789012345678901234567890)
                                 ("0.5" 0.5f0) ("-0.25" -0.25f0)
                                 ("1e2" 100f0) ("1E2" 100f0)
                                 ("1.5e+3" 1500f0) ("25e-2" 0.25f0)
                                 ("0.0" 0f0) ("0e999999999" 0f0)
                                 ("1e-999999999" 0f0))
          do (is (eql number (json->lisp text))
                 "~A reads as ~S" text (json->lisp text)))
    (signals json-parse-error (json->lisp "1e39")))
  ;; A float is the one the Lisp reader makes of the same text.
  (dolist (format '(single-float double-float))
    (let ((*read-default-float-format* format))
      (dolist (text '("0.1" "3.141592653589793" "1e10" "2.5e-3" "16777217.0"))
        (is (eql (let ((*read-eval* nil)) (read-from-string text))
                 (json->lisp text))
            "~A as a ~(~A~)" text format))
      ;; Too large for a float is refused; it does not reach the float traps.
      (dolist (text '("1e400" "1e999999999999" "-1e999999999999"))
        (signals json-parse-error (json->lisp text)))))
  ;; The reader variables of the image do not change what a numeral means.
  (let ((*read-base* 16))
    (is (eql 10 (json->lisp "10"))))
  (is (integerp (json->lisp (make-string 400 :initial-element #\7)))))

(test json-bounds-the-digits-of-a-number
  ;; Reading digits costs the square of their count, so a run of them has a
  ;; limit wherever a number has one: integer part, fraction, exponent.
  (let ((limit automa-gp::*json-max-digits*))
    (flet ((sevens (count) (make-string count :initial-element #\7)))
      (loop for (before after) in '(("" "") ("-" "") ("0." "") ("" ".5")
                                    ("1e-" "") ("1.5E" ""))
            do (flet ((numeral (count)
                        (concatenate 'string before (sevens count) after)))
                 (is (numberp (handler-case (json->lisp (numeral limit))
                                ;; 1e777…7 has its digits, and no float.
                                (json-parse-error (c)
                                  (if (search "too large" (princ-to-string c))
                                      0
                                      c))))
                     "~A<~D digits>~A is refused" before limit after)
                 (dolist (count (list (1+ limit) 2000000))
                   (handler-case (progn (json->lisp (numeral count))
                                        (fail "~D digits were read" count))
                     (json-parse-error (c)
                       (is (search "digits" (princ-to-string c)))))))))))

(test json-decodes-objects-without-interning-keys
  (let ((obj (json->lisp "{\"seed_demo\":true,\"domain\":\"documents\"}")))
    (is (eq t (getf obj :seed-demo)))
    (is (string= "documents" (getf obj :domain))))
  (is (null (json->lisp "{}")))
  (is (equalp #() (json->lisp " [ ] ")))
  (is (equalp '(:name :null :fact #("a" 1 nil))
              (json->lisp "{\"name\":null,\"fact\":[\"a\",1,false]}")))
  ;; A key no keyword is named after stays a string and creates no symbol.
  (loop for n from 0 below 20
        for key = (format nil "zq-unseen-key-~D-~D" n (random 1000000))
        for obj = (json->lisp (format nil "{~S:~D}" key n))
        do (is (equal (list key n) obj))
           (is (null (find-symbol (string-upcase key) :keyword)))))

(defun %repeat (piece count)
  "PIECE written COUNT times."
  (with-output-to-string (out)
    (loop repeat count do (write-string piece out))))

(test json-bounds-the-nesting
  (let ((limit automa-gp::*json-max-depth*))
    (loop for (open value close) in '(("[" "" "]") ("{\"a\":" "1" "}"))
          do (flet ((nested (depth)
                      (concatenate 'string (%repeat open depth) value
                                   (%repeat close depth))))
               (finishes (json->lisp (nested limit)))
               ;; Far past the limit the answer is the same condition, not
               ;; an exhausted control stack.
               (dolist (depth (list (1+ limit) 1000 100000))
                 (signals json-parse-error (json->lisp (nested depth)))
                 (signals json-parse-error
                   (json->lisp (%repeat open depth))))))))

(test json-sexp-keeps-words-and-paths-apart
  (loop for (value sexp) in `(("file-created" automa-gp::file-created)
                              ("OPEN" open)
                              (":simulate" :simulate)
                              ("document.pdf" "document.pdf")
                              ("/tmp/notes" "/tmp/notes")
                              ("two words" "two words")
                              ("47391x" "47391x")
                              ("" "")
                              (47391 47391)
                              (:null nil)
                              (t t)
                              (nil nil)
                              (,(vector "a" (vector "b" 1) "c.d")
                               (automa-gp::a (automa-gp::b 1) "c.d"))
                              (("a" "b") (automa-gp::a automa-gp::b))
                              (already-a-symbol already-a-symbol))
        do (is (equal sexp (json->sexp value))
               "~S converts to ~S" value (json->sexp value))))

(test json-bounds-the-names-it-interns
  (let* ((limit automa-gp::*json-max-symbol-length*)
         (fits (make-string limit :initial-element #\q))
         (long (make-string (1+ limit) :initial-element #\q)))
    (is (symbolp (json->sexp fits)))
    (dolist (too-long (list long (concatenate 'string ":" long)))
      (signals json-parse-error (json->sexp too-long))
      (signals json-parse-error (json-string->symbol too-long))
      (signals json-parse-error (json->sexp (vector "fact" too-long))))
    (is (null (find-symbol (string-upcase long) :automa-gp)))
    (is (null (find-symbol (string-upcase long) :keyword)))))

;;; ---------------------------------------------------------------------------
;;; The façade reading a request
;;; ---------------------------------------------------------------------------

(defun %power-session ()
  "A fresh session with one device that POWER-ON can switch on."
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device interface-01))
  (gp-add-fact '(power-state interface-01 off))
  (gp-add-operator
   (make-operator :name 'power-on
                  :preconditions '((device ?d) (power-state ?d off))
                  :add-list '((power-state ?d on))
                  :delete-list '((power-state ?d off)))))

(defun %post-json (path &rest pairs)
  "POST the JSON object made of PAIRS (a keyword plist) to PATH.
Returns (VALUES STATUS-CODE DECODED-BODY)."
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post path (lisp->json pairs))
    (declare (ignore ctype))
    (values code (json->lisp json))))

(test web-api-facts-may-use-common-lisp-words
  ;; OPEN, FIRST or T are COMMON-LISP symbols in every package: a fact that
  ;; uses one is legal at the REPL and is legal here, and nothing is added
  ;; to COMMON-LISP.
  (gp-clear-memory)
  (gp-reset)
  (loop for word in '("open" "close" "first" "step" "count" "time" "position"
                      "list" "set" "print" "t" "nil")
        for n from 0
        for thing = (format nil "zq-thing-~D" n)
        do (multiple-value-bind (code body)
               (%post-json "/api/add-fact" :fact (vector thing word))
             (is (= 200 code) "~A ~A: ~A" thing word (getf body :error))
             (is (fact-p (json->sexp (vector thing word)) (gp-facts))))
           (multiple-value-bind (code body)
               (%post-json "/api/add-goal" :goal (vector thing "other" word))
             (is (= 200 code) "~A: ~A" word (getf body :error)))
           (is (null (find-symbol (string-upcase thing) :common-lisp)))
           (is (= 200 (%post-json "/api/remove-fact"
                                  :fact (vector thing word)))))
  ;; A new word still joins the package of the facts already there.
  (gp-reset)
  (gp-add-fact '(lamp off))
  (multiple-value-bind (code body)
      (%post-json "/api/add-fact" :fact (vector "lamp" "open" "zq-new-word"))
    (is (= 200 code) "~A" (getf body :error))
    (is (fact-p (list 'lamp 'open (find-symbol "ZQ-NEW-WORD" :automa-gp/tests))
                (gp-facts))))
  ;; A word of the context may be the symbol of another locked package, as
  ;; EXIT typed in COMMON-LISP-USER is SB-EXT's: nothing joins that either.
  (gp-reset)
  (gp-add-fact '(lamp sb-ext:exit))
  (multiple-value-bind (code body)
      (%post-json "/api/add-fact" :fact (vector "zq-window" "exit"))
    (is (= 200 code) "~A" (getf body :error))
    (is (fact-p '(automa-gp::zq-window sb-ext:exit) (gp-facts)))
    (is (null (find-symbol "ZQ-WINDOW" :sb-ext)))))

(test web-api-reads-every-flag-one-way
  (let ((keys '(:adapters :auto-confirm :react-events :learn :prefer-archive)))
    (dolist (key keys)
      (loop for (value expected) in '((t t) (1 t) ("true" t) ("YES" t)
                                      (nil nil) (:null nil) (0 nil)
                                      ("false" nil) ("False" nil) ("0" nil)
                                      ("no" nil) ("" nil))
            do (gp-reset)
               (multiple-value-bind (code body)
                   (web-api-handle :post "/api/autonomy/policy" (list key value))
                 (is (= 200 code))
                 (is (eq expected (getf (getf body :policy) key))
                     "~S ~S reads as ~S" key value
                     (getf (getf body :policy) key))))
      ;; A value that says neither yes nor no is refused and installs nothing.
      (dolist (value (list "banana" 2 0.5 (vector t) '(1)))
        (gp-reset)
        (multiple-value-bind (code body)
            (web-api-handle :post "/api/autonomy/policy" (list key value))
          (is (= 400 code))
          (is (search "true or false" (getf body :error)))
          (is (null automa-gp::*autonomy-policy*)))))
    ;; The same reading through JSON text, for the keys that open a gate.
    (gp-reset)
    (multiple-value-bind (code ctype json)
        (web-api-handle-json
         :post "/api/autonomy/policy"
         "{\"adapters\":null,\"auto_confirm\":\"false\",\"learn\":0}")
      (declare (ignore ctype))
      (is (= 200 code))
      (let ((policy (getf (json->lisp json) :policy)))
        (dolist (key '(:adapters :auto-confirm :learn))
          (is (null (getf policy key)) "~S is on" key))))
    (let ((policy (ensure-autonomy-policy)))
      (is-false (policy-adapters policy))
      (is-false (policy-auto-confirm policy))))
  (loop for (body default expected) in '((nil nil nil) (nil t t)
                                         ((:confirm :null) t nil)
                                         ((:confirm "false") t nil)
                                         ((:confirm t) nil t))
        do (is (eq expected (automa-gp::%body-flag body :confirm default)))))

(test web-api-run-is-not-confirmed-unless-the-body-says-so
  (gp-clear-memory)
  (gp-reset)
  (gp-add-fact '(device d1))
  (gp-add-operator
   (make-operator :name 'wipe
                  :preconditions '((device ?d))
                  :add-list '((wiped ?d))
                  :reversible nil
                  :risk :high))
  (gp-plan :goals '((wiped d1)) :archive nil)
  (dolist (body (list nil '(:adapters nil) '(:confirm nil) '(:confirm :null)
                      '(:confirm "false") '(:confirm 0)))
    (multiple-value-bind (code answer)
        (web-api-handle :post "/api/run" body)
      (is (= 200 code))
      (is (null (getf (getf answer :execution) :success))
          "~S ran the irreversible step" body)
      (is (not (fact-p '(wiped d1) (gp-facts))))))
  (multiple-value-bind (code ctype json)
      (web-api-handle-json :post "/api/run" "{}")
    (declare (ignore ctype))
    (is (= 200 code))
    (is (null (getf (getf (json->lisp json) :execution) :success)))
    (is (not (fact-p '(wiped d1) (gp-facts)))))
  (multiple-value-bind (code answer)
      (web-api-handle :post "/api/run" '(:confirm "garbled"))
    (is (= 400 code))
    (is (search "true or false" (getf answer :error)))
    (is (not (fact-p '(wiped d1) (gp-facts)))))
  (multiple-value-bind (code answer)
      (web-api-handle :post "/api/run" '(:confirm t))
    (is (= 200 code))
    (is (eq t (getf (getf answer :execution) :success)))
    (is (fact-p '(wiped d1) (gp-facts)))))

(test web-api-autonomy-request-merges-into-the-session-policy
  (gp-clear-memory)
  (gp-reset)
  (gp-policy :authority :read :max-steps 5 :learn nil :prefer-archive nil
             :react-events nil)
  (let ((session automa-gp::*autonomy-policy*))
    ;; A key the body leaves out keeps the session value.
    (let ((policy (automa-gp::%policy-for-request '(:authority "simulate"))))
      (is (eq :simulate (policy-authority policy)))
      (is (= 5 (policy-max-steps policy)))
      (dolist (reader (list #'policy-learn #'policy-prefer-archive
                            #'policy-react-events #'policy-adapters
                            #'policy-auto-confirm))
        (is-false (funcall reader policy))))
    ;; A body with no authority still states the rest.
    (let ((policy (automa-gp::%policy-for-request
                   '(:adapters t :auto-confirm 1 :max-steps 2.6))))
      (is (eq :read (policy-authority policy)))
      (is (= 3 (policy-max-steps policy)))
      (is-true (policy-adapters policy))
      (is-true (policy-auto-confirm policy)))
    ;; One request does not change the session policy.
    (is (eq session automa-gp::*autonomy-policy*))
    (is (eq :read (policy-authority session)))
    (is-false (policy-adapters session)))
  ;; Step and loop follow the session authority when the body names none.
  (dolist (path '("/api/autonomy/step" "/api/autonomy/loop"))
    (%power-session)
    (gp-add-goal '(power-state interface-01 on))
    (gp-policy :authority :read)
    (multiple-value-bind (code body) (web-api-handle :post path)
      (is (= 200 code))
      (is (eq :read (getf (getf body :autonomy) :authority)))
      (is (not (fact-p '(power-state interface-01 on) (gp-facts))))))
  ;; What is not an authority or a step count is refused, and the text of
  ;; the request does not become a keyword.
  (gp-reset)
  (let ((name (format nil "zq-unseen-authority-~D" (random 1000000))))
    (dolist (path '("/api/autonomy/policy" "/api/autonomy/step"
                    "/api/autonomy/loop"))
      (is (= 400 (web-api-handle :post path (list :authority name))))
      (is (= 400 (web-api-handle :post path '(:max-steps "many")))))
    (is (null (find-symbol (string-upcase name) :keyword)))
    (is (null automa-gp::*autonomy-policy*))))

(test web-api-finds-a-procedure-whose-name-stays-a-string
  (dolist (name '("my proc" "backup v1.2" "2nd-try"))
    (%power-session)
    (gp-plan :goals '((power-state interface-01 on)) :archive nil)
    (is (= 200 (%post-json "/api/archive/remember" :name name)))
    (is (procedure-p (find-procedure name)))
    (dolist (sent (list name (string-upcase name)))
      (multiple-value-bind (code body)
          (%post-json "/api/archive/use" :name sent)
        (is (= 200 code) "use ~S: ~A" sent (getf body :error))
        (is (eq t (getf (getf body :plan) :success)))))
    (multiple-value-bind (code body)
        (%post-json "/api/archive/score" :name name :success nil)
      (is (= 200 code) "score ~S: ~A" name (getf body :error))
      (is (= 1 (getf (getf body :procedure) :failure-count))))
    (is (= 400 (%post-json "/api/archive/use" :name "no such proc")))))

(test web-api-archive-probe-leaves-the-trace-alone
  (%power-session)
  (gp-plan :goals '((power-state interface-01 on)) :archive nil)
  (gp-remember-procedure :name 'switch-on)
  (setf automa-gp::*applies-result-cache* nil)
  (let ((last (gp-last-trace))
        (history (copy-list (gp-trace-history))))
    (multiple-value-bind (code body)
        (web-api-handle :get "/api/archive?applies=1")
      (is (= 200 code))
      (is (eq t (getf (aref (getf body :procedures) 0) :applies))))
    (is (eq last (gp-last-trace)))
    (is (equal history (gp-trace-history)))))

(test web-api-answers-a-bad-body-in-the-json-envelope
  (gp-clear-memory)
  (gp-reset)
  (flet ((refused (text wanted)
           (multiple-value-bind (code ctype json)
               (web-api-handle-json :post "/api/add-fact" text)
             (is (= 400 code) "~S is answered ~D" text code)
             (is (search "application/json" ctype))
             (let ((body (json->lisp json)))
               (is (null (getf body :ok)))
               (is (search wanted (getf body :error))
                   "~S: ~A" text (getf body :error))))))
    (dolist (text '("{oops" "[1,2" "{\"fact\":[\"a\",}" "nul" "{\"fact\":-}"))
      (refused text "not JSON"))
    (dolist (text '("[1,2]" "\"fact\"" "17" "true" "null"))
      (refused text "JSON object"))
    ;; Nesting far past the limit is one more refusal; the image goes on.
    (refused (concatenate 'string "{\"fact\":" (%repeat "[" 20000)
                          (%repeat "]" 20000) "}")
             "nested deeper")
    ;; A word too long to be a symbol is refused and creates none.
    (let ((word (make-string 5000 :initial-element #\w)))
      (refused (lisp->json (list :fact (vector "door" word))) "longer than")
      (is (null (find-symbol (string-upcase word) :automa-gp)))))
  (is (null (gp-facts)))
  ;; A blank body is no body.
  (dolist (text (list nil "" " " (%chars 13 10) (%chars 9 32 10)))
    (is (= 200 (web-api-handle-json :post "/api/reset" text))))
  (is (= 200 (web-api-handle-json :get "/api/status"))))

(test web-api-tells-a-missing-path-from-a-wrong-method
  (gp-clear-memory)
  (gp-reset)
  (loop for (method path wanted) in '((:get "/api/nope" 404)
                                      (:post "/api/nope" 404)
                                      (:post "/api/status" 405)
                                      (:get "/api/reset" 405)
                                      (:put "/api/plan" 405)
                                      ("DELETE" "/api/facts" 405)
                                      ("get" "/api/status" 200)
                                      ("Post" "/api/reset" 200))
        do (multiple-value-bind (code body) (web-api-handle method path)
             (is (= wanted code) "~A ~A is answered ~D" method path code)
             (unless (= 200 code)
               (is (null (getf body :ok)))
               (is (stringp (getf body :error))))))
  (is (find :post (getf (nth-value 1 (web-api-handle :get "/api/reset"))
                        :allow)))
  ;; A method no route has does not become a keyword.
  (let ((method (format nil "zq-unseen-method-~D" (random 1000000))))
    (is (= 405 (web-api-handle method "/api/status")))
    (is (null (find-symbol (string-upcase method) :keyword))))
  ;; Every route is under /api/, answers GET or POST, and refuses the rest.
  (loop for path being the hash-keys of automa-gp::*api-routes*
          using (hash-value routes)
        do (is (eql 0 (search "/api/" path)))
           (is (subsetp (mapcar #'car routes) '(:get :post))
               "~A answers ~S" path (mapcar #'car routes))
           (multiple-value-bind (code body) (web-api-handle :delete path)
             (is (= 405 code))
             (is (equalp (map 'vector #'car routes) (getf body :allow))))))

(defmacro with-test-route ((path function) &body body)
  "Run BODY while GET PATH is answered by FUNCTION, a route function."
  `(unwind-protect
        (progn (automa-gp::%register-api-route :get ,path ,function)
               ,@body)
     (remhash ,path automa-gp::*api-routes*)))

(test web-api-answers-one-request-at-a-time
  (let ((inside 0)
        (overlaps 0))
    (with-test-route ("/api/test/slow"
                      (lambda (body query)
                        (declare (ignore body query))
                        (when (> (incf inside) 1)
                          (incf overlaps))
                        (sleep 0.02)
                        (decf inside)
                        (list :ok t)))
      (let ((threads (loop repeat 6
                           collect (sb-thread:make-thread
                                    (lambda ()
                                      (web-api-handle :get "/api/test/slow"))))))
        (is (equal '(200 200 200 200 200 200)
                   (mapcar #'sb-thread:join-thread threads)))
        (is (zerop overlaps))))))

(test web-api-gives-up-a-request-that-exhausts-storage
  (with-test-route ("/api/test/exhausted"
                    (lambda (body query)
                      (declare (ignore body query))
                      (error 'storage-condition)))
    (multiple-value-bind (code body)
        (web-api-handle :get "/api/test/exhausted")
      (is (= 500 code))
      (is (null (getf body :ok)))
      (is (stringp (getf body :error)))))
  ;; The lock was released: the next request is answered.
  (is (= 200 (web-api-handle :get "/api/status"))))

(test web-api-run-does-not-ask-at-the-terminal
  ;; With an :ASK strategy and nobody to ask, a failed step gives the plan
  ;; up. It must not read the answer from *QUERY-IO*.
  (%power-session)
  (gp-plan :goals '((power-state interface-01 on)) :archive nil)
  (gp-remove-fact '(power-state interface-01 off))
  (gp-failure-strategy :ask)
  (let ((*ask-user-fn* nil)
        (*query-io* (make-two-way-stream (make-string-input-stream "")
                                         (make-broadcast-stream))))
    (multiple-value-bind (code body) (web-api-handle :post "/api/simulate")
      (is (= 200 code) "~A" (getf body :error))
      (let ((execution (getf body :execution)))
        (is (null (getf execution :success)))
        (is (equal '(:abort-execution)
                   (loop for event across (getf execution :strategy-events)
                         when (eq :ask-user (getf event :kind))
                           collect (getf event :choice)))))))
  ;; A function the operator installed is still the one that is asked.
  (let* ((asked nil)
         (*ask-user-fn* (lambda (condition names)
                          (declare (ignore condition names))
                          (setf asked t)
                          :skip)))
    (is (= 200 (web-api-handle :post "/api/simulate")))
    (is-true asked))
  (gp-reset))

(test web-api-load-domain-names-a-known-domain
  (gp-clear-memory)
  (gp-reset)
  (dolist (body (list nil '(:domain :null) '(:domain 7)
                      (list :domain (vector "hardware"))))
    (multiple-value-bind (code answer)
        (web-api-handle :post "/api/load-domain" body)
      (is (= 400 code))
      (is (search "requires :domain" (getf answer :error)))))
  (let ((name (format nil "zq-unseen-domain-~D" (random 1000000))))
    (multiple-value-bind (code answer)
        (web-api-handle :post "/api/load-domain" (list :domain name))
      (is (= 400 code))
      (is (search "Unknown domain" (getf answer :error))))
    (is (null (find-symbol (string-upcase name) :keyword))))
  (dolist (name '("hardware" "Hardware" "HARDWARE" :hardware hardware))
    (gp-reset)
    (multiple-value-bind (code answer)
        (web-api-handle :post "/api/load-domain"
                        (list :domain name :seed-demo nil))
      (is (= 200 code))
      (is (find :hardware (getf answer :domains))))))

(test web-api-reaction-reports-what-was-dropped
  (is (equalp #((ready ?x))
              (getf (automa-gp::%serialize-last-reaction
                     '(:processed 1 :dropped ((ready ?x))))
                    :dropped)))
  (gp-clear-memory)
  (gp-reset)
  (gp-emit '(automa-gp::file-created "brief.pdf"))
  (multiple-value-bind (code body) (web-api-handle :post "/api/react")
    (is (= 200 code))
    (is (equalp #() (getf (getf body :reaction) :dropped)))))

(test web-api-writes-an-empty-list-as-an-empty-array
  (gp-clear-memory)
  (gp-reset)
  (gp-add-operator (make-operator :name 'notice-it :add-list '((noticed))))
  (let ((operator (aref (getf (nth-value 1 (web-api-handle :get "/api/operators"))
                              :operators)
                        0)))
    (is (equalp #((noticed)) (getf operator :add-list)))
    (dolist (key '(:preconditions :delete-list))
      (is (equalp #() (getf operator key)) "~S is ~S" key (getf operator key))))
  (let ((autonomy (automa-gp::%serialize-autonomy
                   '(:status :done
                     :plan (:success t :length 0 :operators nil :remaining nil)
                     :execution (:success t :mode :simulate :divergences nil)))))
    (is (equalp '(:success t :length 0 :operators #() :remaining #())
                (getf autonomy :plan)))
    (is (equalp #() (getf (getf autonomy :execution) :divergences))))
  (let ((autonomy (automa-gp::%serialize-autonomy '(:status :halted))))
    (is (eq :null (getf autonomy :plan)))
    (is (eq :null (getf autonomy :execution)))))

(test web-api-autonomy-loop-reports-its-last-step
  ;; A loop answers with what its last step planned and ran, and GET
  ;; /api/autonomy says the same afterwards.
  (%power-session)
  (gp-add-goal '(power-state interface-01 on))
  (multiple-value-bind (code body)
      (web-api-handle :post "/api/autonomy/loop" '(:authority "simulate"))
    (is (= 200 code) "~A" (getf body :error))
    (dolist (autonomy (list (getf body :autonomy)
                            (getf (nth-value 1 (web-api-handle :get "/api/autonomy"))
                                  :last)))
      (is (eql 1 (getf autonomy :iterations)))
      (is (eq :simulate (getf autonomy :authority)))
      (is (eq t (getf autonomy :authorized)))
      (is (plusp (length (getf autonomy :phases))))
      (is (eq t (getf (getf autonomy :plan) :success)))
      (is (equalp #(power-on) (getf (getf autonomy :plan) :operators)))
      (is (eq t (getf (getf autonomy :execution) :success)))
      (is (equalp #((power-state interface-01 on)) (getf autonomy :goals))))))

(test web-api-goes-on-when-the-archive-file-cannot-be-used
  ;; The file cannot be written. What the request did is answered as done,
  ;; with the reason the file was left as it is.
  (with-archive-file (blocker)
    (%write-archive-text blocker "not a directory")
    (let ((*procedure-archive-path*
            (format nil "~A/archive.agp" (namestring blocker))))
      (flet ((not-written (body)
               (is (eq t (getf body :ok)) "~A" (getf body :error))
               (is (search "Cannot write the procedure archive"
                           (getf body :archive-error)))
               (is (search (namestring blocker) (getf body :archive-error)))))
        (%archive-studio)
        (multiple-value-bind (code body)
            (web-api-handle :post "/api/archive/remember" '(:name "kept"))
          (is (= 200 code))
          (not-written body)
          (is (= 1 (length (getf body :procedures)))))
        (is (procedure-p (gp-find-procedure 'automa-gp::kept)))
        ;; A run that reuses the procedure scores it, and so writes the file.
        (%archive-studio)
        (is (eq 'automa-gp::kept
                (getf (plan-meta (gp-last-plan)) :from-procedure)))
        (multiple-value-bind (code body)
            (web-api-handle :post "/api/run" '(:confirm t))
          (is (= 200 code))
          (not-written body)
          (is (eq t (getf (getf body :execution) :success))))
        (is (fact-p '(connection interface-01 computer) (gp-facts)))
        (multiple-value-bind (code ctype json)
            (web-api-handle-json :post "/api/archive/score"
                                 "{\"name\":\"kept\",\"success\":false}")
          (declare (ignore ctype))
          (is (= 200 code))
          (not-written (json->lisp json)))
        (is (= 1 (procedure-failure-count
                  (gp-find-procedure 'automa-gp::kept)))))
      ;; A request that leaves the archive alone says nothing about it.
      (is (eq :absent (getf (nth-value 1 (web-api-handle :get "/api/archive"))
                            :archive-error :absent)))))
  ;; The file cannot be read. The session goes on without it, a refusal
  ;; says so too, and a later change does not replace the file.
  (dolist (text '("(" "(:kind :not-an-archive)"))
    (with-archive-file (path :autoload t)
      (%write-archive-text path text)
      (flet ((not-read (body)
               (is (search "Cannot read the procedure archive"
                           (getf body :archive-error)))
               (is (search (namestring path) (getf body :archive-error)))))
        (multiple-value-bind (code body)
            (web-api-handle :post "/api/archive/use" '(:name "absent"))
          (is (= 400 code))
          (is (search "No archived procedure" (getf body :error)))
          (not-read body))
        (%archive-studio)
        (multiple-value-bind (code body)
            (web-api-handle :post "/api/archive/remember" '(:name "new"))
          (is (= 200 code))
          (is (eq t (getf body :ok)))
          (not-read body)))
      (is (procedure-p (gp-find-procedure 'automa-gp::new)))
      (is (string= text (uiop:read-file-string path))))))
