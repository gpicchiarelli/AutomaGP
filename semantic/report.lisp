;;;; semantic/report.lisp — what the registry says about itself

(in-package #:automa-gp/semantic)

(defun %level-text (level)
  (if level (string-downcase (symbol-name level)) "none"))

(defun %column-widths (header rows)
  (loop for column from 0 below (length header)
        collect (reduce #'max (cons (length (nth column header))
                                    (mapcar (lambda (row)
                                              (length (nth column row)))
                                            rows)))))

(defun %print-table (header rows stream)
  (let ((widths (%column-widths header rows)))
    (flet ((line (cells)
             ;; The last column is not padded: no trailing blanks.
             (format stream "~{~A~^  ~}~%"
                     (loop for (cell . more) on cells
                           for width in widths
                           collect (if more (format nil "~VA" width cell) cell)))))
      (line header)
      (line (mapcar (lambda (width) (make-string width :initial-element #\-))
                    widths))
      (dolist (row rows) (line row)))))

(defun standards-report (&optional (stream *standard-output*))
  "Print one line per registered standard: its designator, maturity, the
lowest level of support among its cataloged constructs, whether its catalog
is complete and its constructs counted, how many requirements it has, and
the verdict of its conformance evidence. Then say how many standards have
any support at all, which on a platform that implements nothing is none.
Returns the number of standards with a claimable level of support."
  (let* ((standards (list-standards))
         (claimable 0)
         (any 0)
         (rows (mapcar
                (lambda (definition)
                  (let ((support (standard-support definition)))
                    (when (getf support :claimable) (incf claimable))
                    (when (getf support :level) (incf any))
                    (list (standard-designator definition)
                          (string-downcase (symbol-name (standard-maturity definition)))
                          (%level-text (getf support :level))
                          (string-downcase (symbol-name (getf support :catalog)))
                          (princ-to-string (getf support :constructs))
                          (princ-to-string
                           (length (requirements-of (standard-designator definition))))
                          (string-downcase
                           (symbol-name (standard-conformance-status definition))))))
                standards)))
    (%print-table '("STANDARD" "MATURITY" "LEVEL" "CATALOG" "CONSTRUCTS"
                    "REQUIREMENTS" "CONFORMANCE")
                  rows stream)
    (format stream "~%~D standard~:P registered, ~D with some support, ~D with a ~
                    claimable level.~%Levels, lowest first: ~{~(~A~)~^ < ~}.~%~
                    A level is claimed only on evidence for it and every level below it.~%"
            (length standards) any claimable *support-levels*)
    claimable))
