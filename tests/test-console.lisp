;;;; tests/test-console.lisp — the request policy of the operator console
;;;;
;;;; interface/web.lisp belongs to the optional automa-gp/web system and does
;;;; not load without Hunchentoot. Its request policy is written as functions
;;;; of the request line and headers alone, in a section of its own. This file
;;;; reads that section as text and runs it: no socket, no Hunchentoot. What
;;;; the acceptor does with the policy needs a live server and is checked
;;;; here only as text.

(in-package #:automa-gp/tests)

(def-suite console-suite :in automa-gp-suite)
(in-suite console-suite)

(defun %console-source ()
  "The text of interface/web.lisp."
  (uiop:read-file-string
   (asdf:system-relative-pathname :automa-gp "interface/web.lisp")))

(defun %console-policy ()
  "A fresh package holding the request policy of interface/web.lisp: the
forms between its two marker lines, read and evaluated there."
  (let* ((source (%console-source))
         (start (search ";;;; Request policy" source))
         (end (search ";;;; End of the request policy" source))
         (name "AUTOMA-GP/TESTS/CONSOLE-POLICY"))
    (assert (and start end (< start end)) ()
            "interface/web.lisp has no request policy section.")
    (when (find-package name)
      (delete-package name))
    (let ((package (make-package name :use '(#:cl))))
      (with-input-from-string (in source :start start :end end)
        (let ((*package* package)
              (*read-eval* nil))
          (loop for form = (read in nil in)
                until (eq form in)
                do (eval form))))
      package)))

(defun %policy (package name &rest arguments)
  "Call the function NAME of the policy PACKAGE on ARGUMENTS."
  (apply (find-symbol name package) arguments))

(test console-serves-only-its-own-page-and-json-clients
  "A request is served when its Host names the console, its Origin, if any,
is the console's own, and anything but GET and HEAD declares JSON."
  (let ((policy (%console-policy))
        (own "127.0.0.1:47391"))
    (dolist (row `(;; the console page, the workbench, a script on this machine
                   (nil :get ,own nil nil)
                   (nil :head ,own nil nil)
                   (nil :get "localhost:47391" nil nil)
                   (nil :get "LocalHost:47391" nil nil)
                   (nil :get "[::1]:47391" nil nil "::1")
                   (nil :post ,own nil "application/json")
                   (nil :post ,own nil "application/json; charset=utf-8")
                   (nil :post ,own nil "Application/JSON ;charset=utf-8")
                   (nil :post ,own "http://127.0.0.1:47391" "application/json")
                   (nil :post "localhost:47391" "http://localhost:47391"
                        "application/json")
                   (nil :get "127.0.0.1" nil nil "127.0.0.1" 80)
                   (nil :get "127.0.0.1:80" nil nil "127.0.0.1" 80)
                   ;; a foreign name pointed at this machine, or no name
                   (403 :get "evil.example:47391" nil nil)
                   (403 :get "evil.example" nil nil)
                   (403 :get "127.0.0.1.evil.example:47391" nil nil)
                   (403 :get "127.0.0.1:8080" nil nil)
                   (403 :get "127.0.0.1" nil nil)
                   (403 :get "" nil nil)
                   (403 :get nil nil nil)
                   (403 :post "evil.example:47391" "http://evil.example:47391"
                        "application/json")
                   ;; a page of another origin
                   (403 :post ,own "http://evil.example" "application/json")
                   (403 :post ,own "http://evil.example" "text/plain")
                   (403 :post ,own "null" "application/json")
                   (403 :post ,own "https://127.0.0.1:47391" "application/json")
                   (403 :post ,own "http://localhost:47391" "application/json")
                   (403 :post ,own "http://127.0.0.1:47391.evil.example"
                        "application/json")
                   (403 :get ,own "http://evil.example" nil)
                   ;; the bodies a page can send without asking first
                   (415 :post ,own nil nil)
                   (415 :post ,own nil "")
                   (415 :post ,own nil "text/plain")
                   (415 :post ,own nil "text/plain; application/json")
                   (415 :post ,own nil "application/x-www-form-urlencoded")
                   (415 :post ,own nil "multipart/form-data; boundary=x")
                   (415 :post ,own nil "application/jsonp")
                   (415 :post ,own "http://127.0.0.1:47391" "text/plain")
                   (415 :put ,own nil "text/plain")
                   (415 :delete ,own nil nil)
                   ;; bound to one other address: that address, by its number
                   (nil :get "192.168.1.5:47391" nil nil "192.168.1.5")
                   (403 :get "evil.example:47391" nil nil "192.168.1.5")
                   ;; bound to every interface: any name, still one origin
                   (nil :get "console.lan:47391" nil nil "0.0.0.0")
                   (nil :get "console.lan:47391" nil nil nil)
                   (nil :get nil nil nil "::")
                   (nil :post "console.lan:47391" "http://console.lan:47391"
                        "application/json" "0.0.0.0")
                   (403 :post "console.lan:47391" "http://evil.example"
                        "application/json" "0.0.0.0")
                   (403 :post nil "http://evil.example" "application/json"
                        "0.0.0.0")
                   (415 :post "console.lan:47391" nil "text/plain" "0.0.0.0")))
      (destructuring-bind (expected method host origin content-type
                           &optional (address "127.0.0.1") (port 47391))
          row
        (multiple-value-bind (status message)
            (%policy policy "%REQUEST-REFUSAL"
                     method host origin content-type address port)
          (is (eql expected status)
              "~S to ~S from ~S as ~S on ~S:~S: ~S, expected ~S"
              method host origin content-type address port status expected)
          (is (eq (null expected) (null message))
              "A refusal says why, and only a refusal: ~S" row))))))

(test console-bounds-the-request-body
  "A body is read only when it declares a length within the limit."
  (let* ((policy (%console-policy))
         (limit-name (find-symbol "*MAX-REQUEST-BODY-OCTETS*" policy))
         (limit (symbol-value limit-name)))
    (flet ((refusal (content-length transfer-encoding)
             (%policy policy "%BODY-REFUSAL" content-length transfer-encoding)))
      (is (<= 1 limit (* 16 1024 1024))
          "The body limit is ~S octets" limit)
      (dolist (row `((nil nil nil)
                     (nil "0" nil)
                     (nil "2" nil)
                     (nil "2" "chunked")
                     (nil ,(princ-to-string limit) nil)
                     (413 ,(princ-to-string (1+ limit)) nil)
                     (413 "2000000000" nil)
                     (413 "2000000000" "chunked")
                     (413 "99999999999999999999999999999999" nil)
                     (411 nil "chunked")
                     (411 nil "gzip, chunked")
                     (400 "" nil)
                     (400 "abc" nil)
                     (400 "12abc" nil)
                     (400 " 12" nil)
                     (400 "-1" nil)
                     (400 "+5" nil)
                     (400 "1e3" nil)
                     (400 "#x10" nil)))
        (destructuring-bind (expected content-length transfer-encoding) row
          (multiple-value-bind (status message)
              (refusal content-length transfer-encoding)
            (is (eql expected status)
                "Content-Length ~S, Transfer-Encoding ~S: ~S, expected ~S"
                content-length transfer-encoding status expected)
            (is (eq (null expected) (null message))
                "A refusal says why, and only a refusal: ~S" row))))
      ;; The limit is read at each request.
      (progv (list limit-name) (list 10)
        (is (null (refusal "10" nil)))
        (is (eql 413 (refusal "11" nil)))))))

(test console-knows-a-loopback-address
  "Only a loopback address binds without the warning of START-WEB."
  (let ((policy (%console-policy)))
    (loop for (address loopback) in '(("127.0.0.1" t) ("::1" t) ("localhost" t)
                                      ("LOCALHOST" t) ("0.0.0.0" nil) ("::" nil)
                                      ("192.168.1.5" nil) (nil nil))
          do (is (eq loopback (%policy policy "%LOOPBACK-ADDRESS-P" address))
                 "~S" address))))

(test console-acceptor-keeps-its-guards
  "The acceptor binds loopback, takes one request per connection, leaves a
refused body unread, answers under the session lock and survives a request
that exhausts the stack; the page never writes server data as markup."
  (let ((source (%console-source)))
    (dolist (literal '(":address \"127.0.0.1\""
                       "(address \"127.0.0.1\")"
                       ":persistent-connections-p nil"
                       ":want-stream t"
                       "(sb-thread:with-mutex (*session-lock*)"
                       "(storage-condition (condition)"))
      (is (search literal source) "interface/web.lisp lost ~S" literal))
    (dolist (sink '("innerHTML" "outerHTML" "insertAdjacentHTML"
                    "document.write"))
      (is (null (search sink source)) "The console page uses ~A" sink))))
