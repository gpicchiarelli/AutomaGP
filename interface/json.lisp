;;;; interface/json.lisp — JSON encode/decode for the operator-console API
;;;;
;;;; No JSON dependency. Both directions are RFC 8259 text: objects, arrays,
;;;; strings, numbers, true, false, null.
;;;;
;;;; Lisp → JSON. A keyword plist is an object, a vector or any other proper
;;;; list an array, NIL is false and :NULL is null. A symbol is its name in
;;;; upper case; a keyword is ":NAME".
;;;;
;;;; JSON → Lisp. An object is a plist, an array a vector, null is :NULL.
;;;; The text comes from outside the image, so reading it is bounded: the
;;;; nesting has a limit, a number has a limit of digits, an object key never
;;;; creates a symbol, and a word that becomes a symbol has a length limit.
;;;; Nothing is handed to the Lisp reader.

(in-package #:automa-gp)

(defparameter *json-max-depth* 64
  "How deep arrays and objects may nest in a text JSON->LISP reads.
The decoder recurses once per level, so without a limit one request could
exhaust the control stack. The bodies of the console API nest three deep.")

(defparameter *json-max-symbol-length* 128
  "Longest JSON string JSON-STRING->SYMBOL turns into a symbol.
Symbols are never collected, so the names a request can create are bounded.")

(defparameter *json-max-digits* 1024
  "Longest run of digits in a number JSON->LISP reads.
Turning digits into an integer takes time that grows with the square of
their count: a numeral of a million digits holds a thread for most of a
minute, one of ten million for over an hour.")

(define-condition json-parse-error (parse-error)
  ((reason
    :initarg :reason
    :reader json-parse-error-reason
    :documentation "A sentence saying what is wrong.")
   (position
    :initarg :position
    :reader json-parse-error-position
    :initform nil
    :documentation "Index in the text where it went wrong, or NIL."))
  (:report (lambda (condition stream)
             (format stream "~A~@[ at ~D~]"
                     (json-parse-error-reason condition)
                     (json-parse-error-position condition))))
  (:documentation "A text is not JSON, or it is JSON this codec refuses:
nested deeper than *JSON-MAX-DEPTH*, a number no float can hold or with
more than *JSON-MAX-DIGITS* digits in a row, a name longer than
*JSON-MAX-SYMBOL-LENGTH*."))

(defun %json-error (position control &rest arguments)
  "Signal JSON-PARSE-ERROR for POSITION with the reason CONTROL and
ARGUMENTS format."
  (error 'json-parse-error
         :position position
         :reason (apply #'format nil control arguments)))

;;; ---------------------------------------------------------------------------
;;; Encoder
;;; ---------------------------------------------------------------------------

(defun %write-json-string (string out)
  "Write STRING to OUT as a JSON string. Every character below U+0020 is
escaped, as RFC 8259 requires."
  (write-char #\" out)
  (loop for c across string
        do (case c
             (#\" (write-string "\\\"" out))
             (#\\ (write-string "\\\\" out))
             (#\Newline (write-string "\\n" out))
             (#\Return (write-string "\\r" out))
             (#\Tab (write-string "\\t" out))
             (#\Backspace (write-string "\\b" out))
             (#\Page (write-string "\\f" out))
             (t (if (< (char-code c) #x20)
                    (format out "\\u~4,'0X" (char-code c))
                    (write-char c out)))))
  (write-char #\" out))

(defun json-escape-string (s)
  "The string designator S as a JSON string, quotes included."
  (with-output-to-string (out)
    (%write-json-string (string s) out)))

(defun json-array (&optional list)
  "Wrap LIST as a vector so LISP->JSON emits a JSON array (incl. empty [])."
  (coerce list 'vector))

(defun %plist-looking-p (value)
  "True if VALUE looks like a property list (even length, keyword keys)."
  (and (consp value)
       (null (cdr (last value)))
       (evenp (length value))
       (loop for (k) on value by #'cddr
             always (keywordp k))))

(defun %json-number-text (number)
  "The JSON numeral for NUMBER, or NIL when JSON has none: a complex, an
infinity, a NaN.
A ratio is written as the nearest double. A float is printed in its own
format, so no Lisp exponent marker (1.0d0) reaches the text."
  (typecase number
    (integer (format nil "~D" number))
    (ratio (%json-number-text (coerce number 'double-float)))
    (float
     ;; A NaN is not equal to itself; an infinity exceeds every float.
     (when (and (= number number)
                (<= (abs number) most-positive-long-float))
       (let ((*read-default-float-format*
               (find-if (lambda (format) (typep number format))
                        '(single-float double-float short-float long-float))))
         (prin1-to-string number))))))

(defun %write-json-items (items out)
  "Write the sequence ITEMS to OUT as a JSON array."
  (write-char #\[ out)
  (let ((first t))
    (map nil (lambda (item)
               (if first
                   (setf first nil)
                   (write-char #\, out))
               (%write-json item out))
         items))
  (write-char #\] out))

(defun %write-json (value out)
  "Write VALUE to OUT as JSON. See LISP->JSON."
  (cond
    ((eq value :null) (write-string "null" out))
    ((eq value t) (write-string "true" out))
    ((eq value nil) (write-string "false" out))
    ((numberp value)
     (let ((numeral (%json-number-text value)))
       (if numeral
           (write-string numeral out)
           (%write-json-string (prin1-to-string value) out))))
    ((stringp value) (%write-json-string value out))
    ((keywordp value)
     (%write-json-string (format nil ":~A" (symbol-name value)) out))
    ((symbolp value)
     (%write-json-string (symbol-name value) out))
    ((and (consp value) (atom (cdr value)) (not (null (cdr value))))
     ;; dotted pair → two-element array
     (%write-json-items (list (car value) (cdr value)) out))
    ((%plist-looking-p value)
     (write-char #\{ out)
     (loop for (k v) on value by #'cddr
           for first = t then nil
           do (unless first (write-char #\, out))
              (%write-json-string (string-downcase (symbol-name k)) out)
              (write-char #\: out)
              (%write-json v out))
     (write-char #\} out))
    ((or (vectorp value)
         (and (listp value) (null (cdr (last value)))))
     (%write-json-items value out))
    (t (%write-json-string (prin1-to-string value) out))))

(defun lisp->json (value)
  "Encode VALUE as a JSON string.
NIL encodes as false; use :NULL for null; use JSON-ARRAY for [].
Even-length keyword plists encode as objects; other lists as arrays.
An integer or a float is a JSON number and a ratio the nearest double.
Anything JSON has no form for (an infinity, a structure) is the string of
its printed representation, so the result is always valid JSON."
  (with-output-to-string (out)
    (%write-json value out)))

;;; ---------------------------------------------------------------------------
;;; Decoder (recursive descent)
;;; ---------------------------------------------------------------------------

(defun %skip-ws (s i)
  (loop while (and (< i (length s))
                   (member (char s i) '(#\Space #\Tab #\Newline #\Return)))
        do (incf i))
  i)

(defun %char-at-p (s i char)
  "True when I is inside S and the character there is CHAR."
  (and (< i (length s)) (char= (char s i) char)))

(defun %ascii-digit-p (char)
  "True for 0-9 only. DIGIT-CHAR-P also accepts the digits of other scripts,
which are not JSON."
  (char<= #\0 char #\9))

(defun %digits-end (s i)
  "Index after the run of ASCII digits that starts at I in S.
A run longer than *JSON-MAX-DIGITS* is a JSON-PARSE-ERROR, signalled before
any of it is read as a number."
  (let ((end (or (position-if-not #'%ascii-digit-p s :start i) (length s))))
    (when (> (- end i) *json-max-digits*)
      (%json-error i "A JSON number has more than ~D digits" *json-max-digits*))
    end))

(defun %parse-hex4 (s i)
  "The code unit that the four hexadecimal digits at I in S write."
  (let ((end (+ i 4)))
    (unless (and (<= end (length s))
                 (loop for k from i below end
                       always (digit-char-p (char s k) 16)))
      (%json-error i "\\u needs four hexadecimal digits"))
    (parse-integer s :start i :end end :radix 16)))

(defun %parse-unicode-escape (s i)
  "Decode the escape whose four digits start at I in S, after \\u.
A character beyond U+FFFF is written as two escapes, a high and a low
surrogate; they are joined into the one character. A surrogate on its own
names no character and is an error.
Returns (VALUES CHARACTER NEXT-INDEX)."
  (let* ((unit (%parse-hex4 s i))
         (next (+ i 4))
         (code
           (cond
             ((<= #xD800 unit #xDBFF)
              (unless (and (%char-at-p s next #\\)
                           (%char-at-p s (1+ next) #\u))
                (%json-error i "A high surrogate needs a low surrogate after it"))
              (let ((low (%parse-hex4 s (+ next 2))))
                (unless (<= #xDC00 low #xDFFF)
                  (%json-error i "A high surrogate needs a low surrogate after it"))
                (incf next 6)
                (+ #x10000 (ash (- unit #xD800) 10) (- low #xDC00))))
             ((<= #xDC00 unit #xDFFF)
              (%json-error i "A low surrogate has no high surrogate before it"))
             (t unit))))
    (unless (< code char-code-limit)
      (%json-error i "This Lisp has no character U+~X" code))
    (values (code-char code) next)))

(defun %parse-escape (s i)
  "Decode the escape whose letter is at I in S, after the backslash.
Returns (VALUES CHARACTER NEXT-INDEX)."
  (when (>= i (length s))
    (%json-error i "Unterminated JSON string"))
  (let ((letter (char s i)))
    (flet ((plain (char) (values char (1+ i))))
      (case letter
        (#\" (plain #\"))
        (#\\ (plain #\\))
        (#\/ (plain #\/))
        (#\n (plain #\Newline))
        (#\r (plain #\Return))
        (#\t (plain #\Tab))
        (#\b (plain #\Backspace))
        (#\f (plain #\Page))
        (#\u (%parse-unicode-escape s (1+ i)))
        (t (%json-error i "Unknown JSON escape \\~C" letter))))))

(defun %parse-string (s i)
  (unless (%char-at-p s i #\")
    (%json-error i "JSON string expected"))
  (incf i)
  (let ((out (make-array 16 :element-type 'character
                            :adjustable t :fill-pointer 0)))
    (loop
      (when (>= i (length s))
        (%json-error i "Unterminated JSON string"))
      (let ((c (char s i)))
        (cond
          ((char= c #\")
           (return (values (coerce out 'simple-string) (1+ i))))
          ((char= c #\\)
           (multiple-value-bind (char next) (%parse-escape s (1+ i))
             (vector-push-extend char out)
             (setf i next)))
          (t
           (vector-push-extend c out)
           (incf i)))))))

(defun %json-float (mantissa exponent position)
  "MANTISSA × 10^EXPONENT as a float of *READ-DEFAULT-FLOAT-FORMAT*, the
float the Lisp reader makes of the same numeral. So a number a client sends
back equals the one typed at the REPL. A magnitude too large for that
format is a JSON-PARSE-ERROR at POSITION; one too small is zero.
The power of ten is formed only when the magnitude is within 10^±5000,
which no float format reaches, so a numeral like 1e999999999 costs nothing."
  (let ((format *read-default-float-format*)
        (bits (integer-length mantissa)))
    (flet ((out-of-range ()
             (%json-error position "The number is too large for a ~(~A~)"
                          format)))
      ;; BITS/4 ≤ decimal digits of MANTISSA ≤ BITS/3 + 1.
      (cond
        ((zerop mantissa) (coerce 0 format))
        ((> (+ exponent (floor bits 4)) 5000) (out-of-range))
        ((< (+ exponent (ceiling bits 3) 1) -5000) (coerce 0 format))
        (t (handler-case (coerce (* mantissa (expt 10 exponent)) format)
             (floating-point-overflow () (out-of-range))
             (floating-point-underflow () (coerce 0 format))))))))

(defun %parse-number (s i)
  "Parse the JSON number at I in S. Returns (VALUES NUMBER NEXT-INDEX).
A numeral with neither fraction nor exponent is an integer, a bignum when
it needs to be. Any other is a float, see %JSON-FLOAT. The grammar is that
of RFC 8259: a bare minus sign, a leading zero, a point or an exponent with
no digit after it are errors. So is a run of more than *JSON-MAX-DIGITS*
digits, see %DIGITS-END."
  (let* ((start i)
         (negative (%char-at-p s i #\-))
         (digits (if negative (1+ i) i))
         (end (%digits-end s digits))
         (mantissa 0)
         (exponent 0)
         (float nil))
    (when (= end digits)
      (%json-error start "A JSON number needs a digit"))
    (when (and (> (- end digits) 1) (char= (char s digits) #\0))
      (%json-error start "A JSON number has no leading zero"))
    (setf mantissa (parse-integer s :start digits :end end)
          i end)
    (when (%char-at-p s i #\.)
      (let* ((fraction (1+ i))
             (end (%digits-end s fraction)))
        (when (= end fraction)
          (%json-error i "A JSON fraction needs a digit"))
        (setf mantissa (+ (* mantissa (expt 10 (- end fraction)))
                          (parse-integer s :start fraction :end end))
              exponent (- fraction end)
              float t
              i end)))
    (when (and (< i (length s)) (char-equal (char s i) #\e))
      (let* ((signed (and (< (1+ i) (length s))
                          (find (char s (1+ i)) "+-")))
             (digits (if signed (+ i 2) (1+ i)))
             (end (%digits-end s digits)))
        (when (= end digits)
          (%json-error i "A JSON exponent needs a digit"))
        (incf exponent (parse-integer s :start (1+ i) :end end))
        (setf float t
              i end)))
    (let ((magnitude (if float
                         (%json-float mantissa exponent start)
                         mantissa)))
      (values (if negative (- magnitude) magnitude) i))))

(defun %parse-literal (s i lit value)
  (let ((n (length lit)))
    (unless (and (<= (+ i n) (length s))
                 (string= s lit :start1 i :end1 (+ i n)))
      (%json-error i "Expected ~S" lit))
    (values value (+ i n))))

(defun %parse-array (s i depth)
  "Parse a JSON array into a vector (empty array → #(), not NIL/false)."
  (incf i)
  (setf i (%skip-ws s i))
  (if (%char-at-p s i #\])
      (values (json-array nil) (1+ i))
      (let ((items nil))
        (loop
          (multiple-value-bind (v ni) (%parse-value s i depth)
            (push v items)
            (setf i (%skip-ws s ni)))
          (cond
            ((%char-at-p s i #\,)
             (setf i (%skip-ws s (1+ i))))
            ((%char-at-p s i #\])
             (return (values (json-array (nreverse items)) (1+ i))))
            (t (%json-error i "Bad JSON array")))))))

(defun %json-key (key)
  "The plist key for the object key KEY: the keyword of that name in upper
case with _ read as -, when the image already has that keyword, else KEY
itself. A key is never interned: every key this program looks up is a
keyword in its source, and the others are the client's to invent."
  (or (find-symbol (substitute #\- #\_ (string-upcase key)) :keyword)
      key))

(defun %parse-object (s i depth)
  "Parse a JSON object into a plist. See %JSON-KEY for its keys."
  (incf i)
  (setf i (%skip-ws s i))
  (if (%char-at-p s i #\})
      (values nil (1+ i))
      (let ((plist nil))
        (loop
          (multiple-value-bind (key ni) (%parse-string s i)
            (setf i (%skip-ws s ni))
            (unless (%char-at-p s i #\:)
              (%json-error i "Expected ':' after key"))
            (setf i (%skip-ws s (1+ i)))
            (multiple-value-bind (val nj) (%parse-value s i depth)
              (push (%json-key key) plist)
              (push val plist)
              (setf i (%skip-ws s nj))))
          (cond
            ((%char-at-p s i #\,)
             (setf i (%skip-ws s (1+ i))))
            ((%char-at-p s i #\})
             (return (values (nreverse plist) (1+ i))))
            (t (%json-error i "Bad JSON object")))))))

(defun %parse-value (s i depth)
  "Parse the JSON value at I in S; DEPTH arrays and objects enclose it.
Returns (VALUES VALUE NEXT-INDEX)."
  (setf i (%skip-ws s i))
  (when (>= i (length s))
    (%json-error i "Unexpected end of JSON"))
  (let ((c (char s i)))
    (flet ((nested (parser)
             (when (>= depth *json-max-depth*)
               (%json-error i "JSON nested deeper than ~D levels"
                            *json-max-depth*))
             (funcall parser s i (1+ depth))))
      (cond
        ((char= c #\") (%parse-string s i))
        ((char= c #\{) (nested #'%parse-object))
        ((char= c #\[) (nested #'%parse-array))
        ((char= c #\t) (%parse-literal s i "true" t))
        ((char= c #\f) (%parse-literal s i "false" nil))
        ((char= c #\n) (%parse-literal s i "null" :null))
        ((or (char= c #\-) (%ascii-digit-p c)) (%parse-number s i))
        (t (%json-error i "Unexpected JSON char ~S" c))))))

(defun json->lisp (string)
  "Parse the JSON text STRING into Lisp values.
An array is a vector; true, false and null are T, NIL and :NULL; a string
is a string. A number with neither fraction nor exponent is an integer,
any other the float the Lisp reader would make of it. An object is a plist
whose key is a keyword when the image already has one of that name (in
upper case, _ read as -) and the key string otherwise, so a text cannot
create keywords; {} is NIL.
Signals JSON-PARSE-ERROR for a text that is not JSON, that nests deeper
than *JSON-MAX-DEPTH*, or that writes a number with more than
*JSON-MAX-DIGITS* digits in a row."
  (let ((s (string string)))
    (multiple-value-bind (v i) (%parse-value s 0 0)
      (setf i (%skip-ws s i))
      (unless (= i (length s))
        (%json-error i "Trailing JSON junk"))
      v)))

(defun json-string->symbol (s &optional (package (find-package :automa-gp)))
  "Map a JSON string to a symbol in PACKAGE (or keyword if it starts with ':').
The name is S in upper case. A string longer than *JSON-MAX-SYMBOL-LENGTH*
is a JSON-PARSE-ERROR and creates no symbol."
  (when (> (length s) *json-max-symbol-length*)
    (%json-error nil "A name of ~D characters is longer than the ~D a symbol may have"
                 (length s) *json-max-symbol-length*))
  (if (and (plusp (length s)) (char= (char s 0) #\:))
      (intern (string-upcase (subseq s 1)) :keyword)
      (intern (string-upcase s) package)))

(defun json->sexp (value)
  "Convert decoded JSON VALUE into a Lisp sexp for facts/goals/events.
A string becomes a symbol in #:automa-gp, or a keyword when it starts with
':'. A string that reads like a path or a sentence stays a string: the
empty string, one that starts with a digit, one that contains '.', '/' or
a space. Numbers stay numbers. JSON arrays (vectors) become proper lists
and null becomes NIL. Signals JSON-PARSE-ERROR for a word too long to be a
symbol, see JSON-STRING->SYMBOL."
  (cond
    ((eq value :null) nil)
    ((stringp value)
     (cond
       ((zerop (length value)) value)
       ((char= (char value 0) #\:) (json-string->symbol value))
       ((or (digit-char-p (char value 0))
            (find-if (lambda (c) (find c "./ ")) value))
        value)
       (t (json-string->symbol value))))
    ((vectorp value)
     (map 'list #'json->sexp value))
    ((listp value)
     (mapcar #'json->sexp value))
    (t value)))
