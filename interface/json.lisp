;;;; interface/json.lisp — minimal JSON encode/decode (Phase 11)
;;;;
;;;; No Quicklisp JSON dependency. Sufficient for the operator-console API:
;;;; objects, arrays, strings, numbers, booleans, null. Lisp symbols encode
;;;; as uppercase name strings; keywords as ":NAME".

(in-package #:automa-gp)

(defun json-escape-string (s)
  (with-output-to-string (out)
    (write-char #\" out)
    (loop for c across (string s) do
      (case c
        (#\" (write-string "\\\"" out))
        (#\\ (write-string "\\\\" out))
        (#\Newline (write-string "\\n" out))
        (#\Return (write-string "\\r" out))
        (#\Tab (write-string "\\t" out))
        (t (write-char c out))))
    (write-char #\" out)))

(defun json-array (&optional list)
  "Wrap LIST as a vector so LISP->JSON emits a JSON array (incl. empty [])."
  (coerce list 'vector))

(defun lisp->json (value)
  "Encode VALUE as a JSON string.
NIL encodes as false; use :NULL for null; use JSON-ARRAY for [].
Plists (list starting with a keyword) encode as objects."
  (cond
    ((eq value :null) "null")
    ((eq value t) "true")
    ((eq value nil) "false")
    ((numberp value) (princ-to-string value))
    ((stringp value) (json-escape-string value))
    ((keywordp value)
     (json-escape-string (format nil ":~A" (symbol-name value))))
    ((symbolp value)
     (json-escape-string (symbol-name value)))
    ((and (consp value) (atom (cdr value)) (not (null (cdr value))))
     ;; dotted pair → two-element array
     (lisp->json (list (car value) (cdr value))))
    ((and (consp value) (keywordp (car value)))
     ;; plist → JSON object
     (with-output-to-string (out)
       (write-char #\{ out)
       (loop for (k v) on value by #'cddr
             for first = t then nil
             do (unless first (write-char #\, out))
                (write-string (json-escape-string
                               (if (keywordp k)
                                   (string-downcase (symbol-name k))
                                   (string k)))
                              out)
                (write-char #\: out)
                (write-string (lisp->json v) out))
       (write-char #\} out)))
    ((and (listp value) (null (cdr (last value))))
     ;; proper list → JSON array
     (with-output-to-string (out)
       (write-char #\[ out)
       (loop for x in value
             for first = t then nil
             do (unless first (write-char #\, out))
                (write-string (lisp->json x) out))
       (write-char #\] out)))
    ((vectorp value)
     (with-output-to-string (out)
       (write-char #\[ out)
       (loop for i from 0 below (length value)
             for first = t then nil
             do (unless first (write-char #\, out))
                (write-string (lisp->json (aref value i)) out))
       (write-char #\] out)))
    (t (json-escape-string (prin1-to-string value)))))

;;; ---------------------------------------------------------------------------
;;; Decoder (recursive descent)
;;; ---------------------------------------------------------------------------

(defun %skip-ws (s i)
  (loop while (and (< i (length s))
                   (member (char s i) '(#\Space #\Tab #\Newline #\Return)))
        do (incf i))
  i)

(defun %parse-string (s i)
  (unless (char= (char s i) #\")
    (error "JSON string expected at ~D" i))
  (incf i)
  (let ((out (make-array 16 :element-type 'character
                         :adjustable t :fill-pointer 0)))
    (loop
      (when (>= i (length s))
        (error "Unterminated JSON string"))
      (let ((c (char s i)))
        (cond
          ((char= c #\")
           (return (values (coerce out 'string) (1+ i))))
          ((char= c #\\)
           (incf i)
           (when (>= i (length s))
             (error "Bad JSON escape"))
           (let ((e (char s i)))
             (vector-push-extend
              (case e
                (#\" #\")
                (#\\ #\\)
                (#\/ #\/)
                (#\n #\Newline)
                (#\r #\Return)
                (#\t #\Tab)
                (t e))
              out)
             (incf i)))
          (t
           (vector-push-extend c out)
           (incf i)))))))

(defun %parse-number (s i)
  (let ((start i))
    (when (and (< i (length s)) (char= (char s i) #\-))
      (incf i))
    (loop while (and (< i (length s)) (digit-char-p (char s i)))
          do (incf i))
    (when (and (< i (length s)) (char= (char s i) #\.))
      (incf i)
      (loop while (and (< i (length s)) (digit-char-p (char s i)))
            do (incf i)))
    (when (and (< i (length s)) (member (char s i) '(#\e #\E)))
      (incf i)
      (when (and (< i (length s)) (member (char s i) '(#\+ #\-)))
        (incf i))
      (loop while (and (< i (length s)) (digit-char-p (char s i)))
            do (incf i)))
    (let* ((txt (subseq s start i))
           (num (read-from-string txt)))
      (values num i))))

(defun %parse-literal (s i lit value)
  (let ((n (length lit)))
    (unless (and (<= (+ i n) (length s))
                 (string= s lit :start1 i :end1 (+ i n)))
      (error "Expected ~S at ~D" lit i))
    (values value (+ i n))))

(defun %parse-array (s i)
  "Parse a JSON array into a vector (empty array → #(), not NIL/false)."
  (unless (char= (char s i) #\[)
    (error "JSON array expected at ~D" i))
  (incf i)
  (setf i (%skip-ws s i))
  (if (and (< i (length s)) (char= (char s i) #\]))
      (values (json-array nil) (1+ i))
      (let ((items nil))
        (loop
          (multiple-value-bind (v ni) (%parse-value s i)
            (push v items)
            (setf i (%skip-ws s ni)))
          (cond
            ((and (< i (length s)) (char= (char s i) #\,))
             (setf i (%skip-ws s (1+ i))))
            ((and (< i (length s)) (char= (char s i) #\]))
             (return (values (json-array (nreverse items)) (1+ i))))
            (t (error "Bad JSON array at ~D" i)))))))

(defun %parse-object (s i)
  (unless (char= (char s i) #\{)
    (error "JSON object expected at ~D" i))
  (incf i)
  (setf i (%skip-ws s i))
  (if (and (< i (length s)) (char= (char s i) #\}))
      (values nil (1+ i))
      (let ((plist nil))
        (loop
          (multiple-value-bind (key ni) (%parse-string s i)
            (setf i (%skip-ws s ni))
            (unless (and (< i (length s)) (char= (char s i) #\:))
              (error "Expected ':' after key at ~D" i))
            (setf i (%skip-ws s (1+ i)))
            (multiple-value-bind (val nj) (%parse-value s i)
              (let* ((norm (substitute #\- #\_ (string-upcase key)))
                     (kw (intern norm :keyword)))
                ;; Append (not push+nreverse): nreverse would scramble plist pairs.
                (setf plist (nconc plist (list kw val))))
              (setf i (%skip-ws s nj))))
          (cond
            ((and (< i (length s)) (char= (char s i) #\,))
             (setf i (%skip-ws s (1+ i))))
            ((and (< i (length s)) (char= (char s i) #\}))
             (return (values plist (1+ i))))
            (t (error "Bad JSON object at ~D" i)))))))

(defun %parse-value (s i)
  (setf i (%skip-ws s i))
  (when (>= i (length s))
    (error "Unexpected end of JSON"))
  (let ((c (char s i)))
    (cond
      ((char= c #\") (%parse-string s i))
      ((char= c #\{) (%parse-object s i))
      ((char= c #\[) (%parse-array s i))
      ((char= c #\t) (%parse-literal s i "true" t))
      ((char= c #\f) (%parse-literal s i "false" nil))
      ((char= c #\n) (%parse-literal s i "null" :null))
      ((or (char= c #\-) (digit-char-p c)) (%parse-number s i))
      (t (error "Unexpected JSON char ~S at ~D" c i)))))

(defun json->lisp (string)
  "Parse JSON STRING into Lisp values (objects → plists, arrays → lists)."
  (let ((s (string string)))
    (multiple-value-bind (v i) (%parse-value s 0)
      (setf i (%skip-ws s i))
      (unless (= i (length s))
        (error "Trailing JSON junk at ~D" i))
      v)))

(defun json-string->symbol (s &optional (package (find-package :automa-gp)))
  "Map a JSON string to a symbol in PACKAGE (or keyword if it starts with ':')."
  (cond
    ((and (plusp (length s)) (char= (char s 0) #\:))
     (intern (string-upcase (subseq s 1)) :keyword))
    (t (intern (string-upcase s) package))))

(defun json->sexp (value)
  "Convert decoded JSON VALUE into a Lisp sexp for facts/goals/events.
Strings become symbols in #:automa-gp (except obvious path-like strings
containing '.' '/' or starting with digit stay strings). Numbers stay numbers.
JSON arrays (vectors) become proper lists."
  (cond
    ((eq value :null) nil)
    ((eq value t) t)
    ((null value) nil)
    ((numberp value) value)
    ((stringp value)
     (if (or (find #\. value) (find #\/ value) (find #\Space value)
             (and (plusp (length value)) (digit-char-p (char value 0)))
             (char= (char value 0) #\:))
         (if (and (plusp (length value)) (char= (char value 0) #\:))
             (json-string->symbol value)
             value)
         (json-string->symbol value)))
    ((vectorp value)
     (map 'list #'json->sexp value))
    ((listp value)
     (mapcar #'json->sexp value))
    (t value)))
