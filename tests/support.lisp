;;;; tests/support.lisp — fixtures shared by more than one test file

(in-package #:automa-gp/tests)

(defun %build-repair-chain (depth &key (package *package*))
  "Archive DEPTH procedures that each restore the precondition of the next,
put CHARGE-THEN-USE on top of them, then remove every fact those procedures
produced. Using CHARGE-THEN-USE afterwards must repair DEPTH levels deep.

Link K needs the fact of link K-1 and asserts its own; the innermost link
asserts (CHARGE-STATE device EMPTY) and deletes the fact it needed. Each
link's operator is removed once its procedure is archived, so only the
archive can restore the chain.

Symbols are interned in PACKAGE: the REPL tests name things in the test
package, the JSON façade reads names into AUTOMA-GP.

Returns a plist:
  :root         the fact link 1 needs; it is never removed
  :links        operator names, outermost link first
  :procedures   archive names of those links, outermost first
  :removed      every fact removed before the repair, outermost first
  :consumed     the fact the innermost link deletes when it runs
  :restored     the removed facts that hold again after a live run
  :charge-empty (CHARGE-STATE device EMPTY), which CHARGE deletes
  :in-use       the goal CHARGE-THEN-USE achieves"
  (flet ((sym (control &rest args)
           (intern (apply #'format nil control args) package)))
    (let* ((device (sym "INTERFACE-01"))
           (device-p (list (sym "DEVICE") '?d))
           (charge-empty (list (sym "CHARGE-STATE") device (sym "EMPTY")))
           (in-use (list (sym "IN-USE") device))
           (stages (append (loop for k from 0 below depth
                                 collect (list (sym "STAGE-~D" k) device (sym "SET")))
                           (list charge-empty)))
           (links (loop for k from 1 to depth collect (sym "LINK-~D" k)))
           (procedures (loop for k from 1 to depth collect (sym "RESTORE-~D" k))))
      (flet ((pattern (fact)
               (list (first fact) '?d (third fact))))
        (gp-reset)
        (gp-add-fact (list (sym "DEVICE") device))
        (gp-add-fact (first stages))
        (loop for link in links
              for procedure in procedures
              for (before after) on stages
              for innermost = (eq after charge-empty)
              do (gp-add-operator
                  (make-operator
                   :name link
                   :preconditions (list device-p (pattern before))
                   :add-list (list (pattern after))
                   :delete-list (when innermost (list (pattern before)))))
                 (gp-plan :goals (list after) :archive nil)
                 (gp-remember-procedure :name procedure)
                 (gp-remove-operator link)
                 (gp-add-fact after))
        (gp-add-operator
         (make-operator
          :name (sym "CHARGE")
          :preconditions (list device-p (pattern charge-empty))
          :add-list (list (list (sym "CHARGE-STATE") '?d (sym "FULL"))
                          (list (sym "READY") '?d))
          :delete-list (list (pattern charge-empty))))
        (gp-add-operator
         (make-operator
          :name (sym "USE-DEVICE")
          :preconditions (list device-p (list (sym "READY") '?d))
          :add-list (list (list (sym "IN-USE") '?d))))
        (gp-plan :goals (list in-use) :archive nil)
        (gp-remember-procedure :name (sym "CHARGE-THEN-USE"))
        (dolist (fact (reverse (rest stages)))
          (gp-remove-fact fact)))
      (list :root (first stages)
            :links links
            :procedures procedures
            :removed (rest stages)
            :consumed (nth (1- depth) stages)
            :restored (butlast (rest stages) 2)
            :charge-empty charge-empty
            :in-use in-use))))
