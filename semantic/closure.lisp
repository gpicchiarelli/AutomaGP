;;;; semantic/closure.lisp — the closure of a dependency graph
;;;;
;;;; PROMPT-SEMANTICA §5 and §27: from one root, every thing it depends on,
;;;; in an order that loads dependencies before what needs them, the same
;;;; order every time, with a cycle reported as what it is. Standards use it
;;;; now; ontology imports (owl:imports) will use it.

(in-package #:automa-gp/semantic)

(defun dependency-closure (root neighbours &key (key #'identity) (test 'equal))
  "The closure of ROOT under NEIGHBOURS.
NEIGHBOURS is a function of a node that returns the nodes it depends on, in
a fixed order. KEY maps a node to what identifies it, compared by TEST,
which must be a hash-table test.
Returns (VALUES ORDER EDGES). ORDER is every node reachable from ROOT, each
once, dependencies before the nodes that depend on them and ROOT last: a
depth-first post-order that follows NEIGHBOURS in the order it gives, so
the same graph gives the same order. EDGES is an alist (NODE . DEPENDENCIES)
in the same order.
A cycle signals DEPENDENCY-CYCLE, whose path runs from the first node of the
cycle round to it again; a node that depends on itself is a cycle of one."
  (let ((done (make-hash-table :test test))
        (on-path (make-hash-table :test test))
        (path nil)
        (order nil)
        (edges nil))
    (labels ((visit (node)
               (let ((id (funcall key node)))
                 (cond
                   ((gethash id done))
                   ((gethash id on-path)
                    ;; PATH holds the nodes being visited, the newest first.
                    (let* ((ids (reverse (mapcar key path)))
                           (start (position id ids :test test)))
                      (error 'dependency-cycle
                             :path (append (subseq ids start) (list id))
                             :message "the dependencies loop back on themselves"
                             :suggestion "remove one dependency of the cycle")))
                   (t
                    (setf (gethash id on-path) t)
                    (push node path)
                    (let ((dependencies (funcall neighbours node)))
                      (dolist (dependency dependencies)
                        (visit dependency))
                      (push (cons node dependencies) edges))
                    (pop path)
                    (remhash id on-path)
                    (setf (gethash id done) t)
                    (push node order))))))
      (visit root))
    (values (nreverse order) (nreverse edges))))
