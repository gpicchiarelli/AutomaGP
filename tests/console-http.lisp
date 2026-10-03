;;;; tests/console-http.lisp — the operator console over a real loopback socket
;;;;
;;;; The system AUTOMA-GP/WEB-TESTS. It starts the Hunchentoot console on an
;;;; ephemeral port of 127.0.0.1 and talks to it with raw HTTP/1.1 over
;;;; SB-BSD-SOCKETS, so no HTTP client library is needed. The request policy
;;;; (tests/test-console.lisp) is also tested without a socket; this file
;;;; checks that the acceptor applies it.
;;;;
;;;; Not part of AUTOMA-GP/TESTS, which does not depend on Hunchentoot.
;;;; Run with `make web-test`.

(in-package #:automa-gp/tests)

(def-suite console-http-suite
  :description "The console, started on a loopback port and driven over TCP.")
(in-suite console-http-suite)

(defvar *console-port* nil "The port of the console under test.")

(defparameter +crlf+ (coerce '(#\Return #\Linefeed) 'string))

(defun %http (request &key (port *console-port*))
  "Send the text REQUEST to the console and read the answer until the
server closes the connection. Returns (VALUES STATUS HEADERS BODY): STATUS
an integer, HEADERS an alist of (LOWER-CASE-NAME . VALUE), BODY a string.
The read gives up after five seconds."
  (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                               :type :stream :protocol :tcp)))
    (unwind-protect
         (progn
           (sb-bsd-sockets:socket-connect socket #(127 0 0 1) port)
           (let ((stream (sb-bsd-sockets:socket-make-stream
                          socket :input t :output t :buffering :full
                                 :element-type :default
                                 :external-format :utf-8)))
             (write-string request stream)
             (finish-output stream)
             (let ((text (with-output-to-string (out)
                           (handler-case
                               (sb-ext:with-timeout 5
                                 (loop for char = (read-char stream nil)
                                       while char do (write-char char out)))
                             (sb-ext:timeout () nil)
                             (error () nil)))))
               (%parse-response text))))
      (sb-bsd-sockets:socket-close socket))))

(defun %parse-response (text)
  (let* ((split (search (format nil "~A~A" +crlf+ +crlf+) text))
         (head (subseq text 0 (or split (length text))))
         (body (if split (subseq text (+ split 4)) ""))
         (lines (uiop:split-string head :separator '(#\Linefeed)))
         (status-line (string-right-trim '(#\Return) (first lines))))
    (values (if (and (> (length status-line) 12)
                     (digit-char-p (char status-line 9)))
                (parse-integer status-line :start 9 :end 12)
                0)
            (loop for line in (rest lines)
                  for colon = (position #\: line)
                  when colon
                    collect (cons (string-downcase (subseq line 0 colon))
                                  (string-trim '(#\Space #\Return)
                                               (subseq line (1+ colon)))))
            body)))

(defun %request (method path &key (host (format nil "127.0.0.1:~D" *console-port*))
                              origin content-type body headers
                              (content-length nil content-length-p))
  "The text of one HTTP/1.1 request. BODY, when given, is sent with its own
Content-Length unless CONTENT-LENGTH says otherwise (NIL: none)."
  (with-output-to-string (out)
    (format out "~A ~A HTTP/1.1~A" method path +crlf+)
    (when host (format out "Host: ~A~A" host +crlf+))
    (when origin (format out "Origin: ~A~A" origin +crlf+))
    (when content-type (format out "Content-Type: ~A~A" content-type +crlf+))
    (dolist (header headers) (format out "~A~A" header +crlf+))
    (let ((length (if content-length-p
                      content-length
                      (and body (length (babel-free-octets body))))))
      (when length (format out "Content-Length: ~A~A" length +crlf+)))
    (format out "Connection: close~A~A" +crlf+ +crlf+)
    (when body (write-string body out))))

(defun babel-free-octets (string)
  "STRING as UTF-8 octets, by the SBCL function: no library."
  (sb-ext:string-to-octets string :external-format :utf-8))

(defun %header (headers name)
  (cdr (assoc name headers :test #'string=)))

(defmacro with-console (() &body body)
  "Run BODY with the console started on an ephemeral loopback port and a
fresh session; stop it after."
  `(progn
     (gp-clear-memory)
     (gp-reset)
     (let* ((acceptor (let ((*standard-output* (make-broadcast-stream)))
                        (automa-gp/web:start-web :port 0)))
            (*console-port* (hunchentoot:acceptor-port acceptor)))
       (unwind-protect (progn ,@body)
         (automa-gp/web:stop-web)))))

(test the-console-binds-loopback-and-names-itself
  (with-console ()
    (is (equal "127.0.0.1"
               (hunchentoot:acceptor-address automa-gp/web::*web-acceptor*)))
    (is (plusp *console-port*))
    (is (equal (format nil "http://127.0.0.1:~D/" *console-port*)
               (automa-gp/web:web-url)))))

(test a-get-is-answered-in-json
  (with-console ()
    (multiple-value-bind (status headers body)
        (%http (%request "GET" "/api/status"))
      (is (= 200 status))
      (is (search "application/json" (%header headers "content-type")))
      (is (search "\"ok\":true" body))
      (is (search (format nil "\"version\":\"~A\"" *version*) body))
      (is (equal "Close" (%header headers "connection"))
          "the connection is kept alive"))))

(test the-page-cannot-be-framed
  (with-console ()
    (multiple-value-bind (status headers body)
        (%http (%request "GET" "/"))
      (is (= 200 status))
      (is (search "text/html" (%header headers "content-type")))
      (is (equal "DENY" (%header headers "x-frame-options")))
      (is (search "frame-ancestors 'none'"
                  (or (%header headers "content-security-policy") "")))
      (is (search "<html" (string-downcase body))))))

(test a-host-that-does-not-name-the-console-is-refused
  (with-console ()
    (dolist (host '("evil.example" "evil.example:80" "127.0.0.1:1"))
      (is (= 403 (%http (%request "GET" "/api/status" :host host)))
          "Host ~S was served" host))
    (is (= 403 (%http (%request "GET" "/api/status" :host nil))))))

(test an-origin-that-is-not-the-consoles-own-is-refused
  (with-console ()
    (is (= 403 (%http (%request "GET" "/api/status"
                                :origin "http://evil.example"))))
    (is (= 200 (%http (%request "GET" "/api/status"
                                :origin (format nil "http://127.0.0.1:~D"
                                                *console-port*)))))))

(test a-post-must-declare-json
  (with-console ()
    (is (= 415 (%http (%request "POST" "/api/reset" :body "{}"))))
    (is (= 415 (%http (%request "POST" "/api/reset" :body "{}"
                                :content-type "text/plain"))))
    (is (= 200 (%http (%request "POST" "/api/reset" :body "{}"
                                :content-type "application/json"))))
    (is (= 200 (%http (%request "POST" "/api/reset" :body "{}"
                                :content-type
                                "application/json; charset=utf-8"))))))

(test a-body-over-the-limit-is-refused-before-it-is-read
  (with-console ()
    (let ((too-long (1+ automa-gp/web:*max-request-body-octets*)))
      (is (= 413 (%http (%request "POST" "/api/reset"
                                  :content-type "application/json"
                                  :content-length too-long)))
          "no body is sent, so a server that read it would hang"))))

(test a-chunked-body-without-a-length-is-refused
  (with-console ()
    (is (= 411 (%http (%request "POST" "/api/reset"
                                :content-type "application/json"
                                :content-length nil
                                :headers '("Transfer-Encoding: chunked")))))))

(test a-bad-length-is-refused
  (with-console ()
    (is (= 400 (%http (%request "POST" "/api/reset"
                                :content-type "application/json"
                                :content-length "twelve"))))))

(test a-body-that-is-not-json-is-a-json-refusal
  (with-console ()
    (multiple-value-bind (status headers body)
        (%http (%request "POST" "/api/reset" :body "{not json"
                                             :content-type "application/json"))
      (is (= 400 status))
      (is (search "application/json" (%header headers "content-type")))
      (is (search "\"ok\":false" body)))))

(test a-wrong-method-names-the-right-one-and-an-unknown-path-is-404
  (with-console ()
    (multiple-value-bind (status headers)
        (%http (%request "DELETE" "/api/status"
                         :content-type "application/json"))
      (is (= 405 status))
      (is (search "GET" (or (%header headers "allow") ""))))
    (is (= 404 (%http (%request "GET" "/api/nowhere"))))))

(test a-request-changes-the-one-session
  "What a POST does to the session is what the next GET reports."
  (with-console ()
    (multiple-value-bind (status headers body)
        (%http (%request "POST" "/api/add-fact" :content-type "application/json"
                         :body "{\"fact\":[\"device\",\"interface-01\"]}"))
      (declare (ignore headers body))
      (is (= 200 status)))
    (is (fact-p '(automa-gp::device automa-gp::interface-01) (gp-facts)))
    (multiple-value-bind (status headers body)
        (%http (%request "GET" "/api/facts"))
      (declare (ignore headers))
      (is (= 200 status))
      (is (search "interface-01" (string-downcase body))))))

(test a-second-start-on-the-same-port-keeps-the-console
  (with-console ()
    (let ((again (automa-gp/web:start-web :port *console-port*)))
      (is (eq again automa-gp/web::*web-acceptor*))
      (is (= 200 (%http (%request "GET" "/api/status")))))))

(test a-stopped-console-answers-nothing
  (let (port)
    (with-console ()
      (setf port *console-port*))
    (is (= 0 (handler-case (%http (%request "GET" "/api/status" :host (format nil "127.0.0.1:~D" port))
                                  :port port)
               (error () 0))))))

(defun run-web-tests ()
  "Run the console tests; return T when every check passes, else signal an
error. Prints totals and failures."
  (let* ((*procedure-archive-autosave* nil)
         (*procedure-archive-autoload* nil)
         (results (let ((fiveam:*test-dribble* (make-broadcast-stream)))
                    (run 'console-http-suite))))
    (explain! results)
    (unless (results-status results)
      (error "automa-gp console tests failed"))
    t))
