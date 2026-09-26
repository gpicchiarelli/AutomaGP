;;;; domains/hardware/package.lisp

(defpackage #:automa-gp/domain/hardware
  (:use #:cl #:automa-gp)
  (:export #:install-hardware-domain
           #:*hardware-domain-name*
           #:hardware-demo-plan))
