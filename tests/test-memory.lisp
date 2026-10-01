;;;; tests/test-memory.lisp — Phase 7 multilevel memory & persistence

(in-package #:automa-gp/tests)

(def-suite memory-suite :in automa-gp-suite)
(in-suite memory-suite)

(defun %mem-studio ()
  (gp-clear-memory)
  (gp-reset)
  (gp-context :name 'studio-audio)
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
  (gp-context))

(test working-and-knowledge-memory
  (gp-clear-memory)
  (gp-reset)
  (gp-context :name 'lab)
  (gp-add-fact '(a 1))
  (gp-add-rule (make-rule :name 'r1 :if '((a ?x)) :then '(b ?x)))
  (let ((wm (gp-working)))
    (is (working-memory-p wm))
    (is (fact-p '(a 1) (working-memory-facts wm)))
    (is (eq 'lab (working-memory-context-name wm))))
  (gp-knowledge-add '(c 3))
  (gp-knowledge-add (make-rule :name 'kc :if '((c ?x)) :then '(d ?x)))
  (is (plusp (length (gp-knowledge-query '(c ?x)))))
  (setf *knowledge-memory* (knowledge-from-context (gp-context)))
  (gp-knowledge-merge)
  (is (fact-p '(a 1) (gp-facts))))

(test episodic-and-remember-procedure
  (%mem-studio)
  (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
    (is-true (plan-success plan))
    (is (plusp (length (gp-episodes :kind :plan))))
    (is (episode-p (gp-last-episode)))
    (let ((proc (gp-remember-procedure :name 'connect-interface)))
      (is (procedure-p proc))
      (is (eq 'connect-interface (procedure-name proc)))
      (is (= 2 (length (procedure-steps proc)))))
    (gp-simulate)
    (gp-run)
    (is (plusp (length (gp-episodes :kind :execute :success t))))
    (let* ((found (gp-find-procedure 'connect-interface))
           (reused (procedure->plan found)))
      (is (procedure-p found))
      (is (plan-p reused))
      (is (equal '(connection interface-01 computer)
                 (first (plan-goals reused))))
      (is (= 2 (plan-length reused)))))
  (gp-reset)
  (signals error (gp-remember-procedure))
  (%mem-studio)
  (let ((failed (gp-plan :goals '((ready interface-01)) :archive nil)))
    (is (not (plan-success failed)))
    (signals error (gp-remember-procedure :name 'nope))
    (is (null (gp-find-procedure 'nope)))))

(test persistence-snapshot-roundtrip
  (let* ((path (merge-pathnames
                (format nil "automa-gp-snap-~A.agp" (get-universal-time))
                (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (%mem-studio)
           (gp-add-rule (make-rule :name 'powered
                                   :if '((power-state ?d on))
                                   :then '(powered ?d)))
           (gp-plan :goals '((connection interface-01 computer)))
           (gp-remember-procedure :name 'connect-interface)
           (gp-knowledge-add '(studio ready))
           (gp-save path)
           (gp-clear-memory)
           (gp-reset)
           (is (null (gp-facts)))
           (is (null (gp-procedures)))
           (let ((bundle (gp-load path)))
             (is (consp bundle))
             (is (fact-p '(device interface-01) (gp-facts)))
             (is (gp-find-procedure 'connect-interface))
             (is (plusp (length (gp-episodes))))
             (is (plusp (length (gp-knowledge-query '(studio ?x)))))
             (let ((plan (gp-plan :goals '((connection interface-01 computer)))))
               (is-true (plan-success plan)))))
      (ignore-errors (delete-file path)))))

(test persistence-isolated-from-planner
  "plan-for does not write snapshot files."
  (let* ((dir (uiop:ensure-directory-pathname
               (merge-pathnames "automa-gp-plan-isolated/"
                                (uiop:temporary-directory))))
         (*default-snapshot-directory* dir))
    (unwind-protect
         (progn
           (ensure-directories-exist dir)
           (plan-for '((a 1)) '((a 1)) nil)
           (is (null (uiop:directory-files dir "*.agp"))))
      (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore))))

(test context-only-persist
  (let ((path (merge-pathnames "automa-gp-ctx-only.agp"
                               (uiop:temporary-directory))))
    (unwind-protect
         (progn
           (gp-clear-memory)
           (gp-reset)
           (gp-context :name 'solo)
           (gp-add-fact '(x 1))
           (gp-save-context path)
           (gp-reset)
           (gp-load-context path)
           (is (eq 'solo (context-name (gp-context))))
           (is (fact-p '(x 1) (gp-facts))))
      (ignore-errors (delete-file path)))))

;;; ---------------------------------------------------------------------------
;;; Episodic memory
;;; ---------------------------------------------------------------------------

(test episode-ids-are-integers-whatever-the-current-package
  "Recording an episode interns nothing, so a long session leaks no symbol."
  (let ((package (make-package "AUTOMA-GP-EPISODE-SCRATCH" :use nil))
        (memory (make-episodic-memory)))
    (unwind-protect
         (let ((ids (loop for current in (list package
                                               (find-package :cl-user)
                                               (find-package :keyword)
                                               *package*)
                          collect (let ((*package* current))
                                    (episode-id
                                     (record-episode! :memory memory))))))
           (is (every #'integerp ids))
           (is (apply #'< ids))
           (is (zerop (let ((count 0))
                        (do-symbols (symbol package count)
                          (incf count))))))
      (delete-package package))))

(test episodes-recorded-after-a-restore-get-fresh-ids
  "A restored episode keeps its id, integer or symbol, and no later episode
is given an integer already in use."
  (let* ((*episode-counter* 0)
         (memory (deserialize-episodic-memory
                  '(:episodic :limit 10
                    :episodes ((:episode :id 7 :kind :plan)
                               (:episode :id legacy-id :kind :plan)
                               (:episode :kind :plan)))))
         (restored (mapcar #'episode-id (episodic-memory-episodes memory)))
         (fresh (episode-id (record-episode! :memory memory))))
    (is (eql 7 (first restored)))
    (is (eq 'legacy-id (second restored)))
    (is (integerp (third restored)))
    (is (integerp fresh))
    (is (not (member fresh restored)))
    (is (equal (cons fresh restored)
               (mapcar #'episode-id (episodic-memory-episodes memory))))))

(test find-episodes-filters
  ":SUCCESS T selects what succeeded, :FAILED what did not, NIL everything."
  (let ((memory (make-episodic-memory)))
    (loop for (kind success context) in '((:plan t studio) (:plan nil studio)
                                          (:execute t studio) (:execute nil lab)
                                          (:simulate :partly lab))
          do (record-episode! :kind kind :success success
                              :context-name context :memory memory))
    (loop for (filters expected)
            in '((() 5)
                 ((:success nil) 5)
                 ((:success t) 3)
                 ((:success :failed) 2)
                 ((:kind :plan) 2)
                 ((:kind :plan :success :failed) 1)
                 ((:kind :event) 0)
                 ((:context-name lab) 2)
                 ((:context-name lab :success t) 1)
                 ((:kind :execute :success :failed :context-name lab) 1)
                 ((:kind :execute :success :failed :context-name studio) 0))
          do (is (= expected
                    (length (apply #'find-episodes :memory memory filters)))
                 "Filters ~S" filters))
    (is (equal '(:simulate :execute :execute :plan :plan)
               (mapcar #'episode-kind (find-episodes :memory memory))))
    (let ((*episodic-memory* memory))
      (is (= 2 (length (gp-episodes :success :failed))))
      (is (= 1 (length (gp-episodes :kind :plan :success :failed)))))))

(test episodic-memory-keeps-its-newest-within-the-limit
  "The limit holds for a memory that is made, restored or recorded into, and
a limit of NIL keeps everything, also across a save."
  (flet ((episodes (count)
           (loop for id from count downto 1
                 collect (make-instance 'episode :id id)))
         (ids (memory)
           (mapcar #'episode-id (episodic-memory-episodes memory))))
    (loop for (limit count kept) in '((3 5 3) (5 3 3) (0 4 0) (nil 300 300))
          do (let* ((*episode-counter* count)
                    (memory (make-episodic-memory :limit limit
                                                  :episodes (episodes count)))
                    (newest (loop for id from count above (- count kept)
                                  collect id)))
               (is (equal newest (ids memory)) "Limit ~S of ~D" limit count)
               (let ((back (deserialize-episodic-memory
                            (serialize-episodic-memory memory))))
                 (is (eql limit (episodic-memory-limit back)))
                 (is (equal newest (ids back))))
               (record-episode! :memory memory)
               (is (equal (let ((grown (cons (1+ count) newest)))
                            (if limit
                                (subseq grown 0 (min limit (length grown)))
                                grown))
                          (ids memory)))))
    ;; A file that holds more episodes than its limit is cut on the way in.
    (is (equal '(3) (ids (deserialize-episodic-memory
                          '(:episodic :limit 1
                            :episodes ((:episode :id 3) (:episode :id 2)))))))
    (is (eql *episodic-memory-limit*
             (episodic-memory-limit
              (deserialize-episodic-memory '(:episodic :episodes nil)))))
    (dolist (limit '(-1 1.5 "3" :all))
      (signals type-error (make-episodic-memory :limit limit)))))

(test an-episode-shares-no-list-with-its-caller
  (let* ((summary (list :goals (list (list 'a 1))))
         (payload (list :steps (list (list :operator 'x))))
         (episode (record-episode! :summary summary :payload payload
                                   :memory (make-episodic-memory))))
    (setf (second (first (getf summary :goals))) 99
          (getf (first (getf payload :steps)) :operator) 'y)
    (is (equal '(:goals ((a 1))) (episode-summary episode)))
    (is (equal '(:steps ((:operator x))) (episode-payload episode)))
    (is (eq :event (episode-kind episode)))))

;;; ---------------------------------------------------------------------------
;;; Working memory
;;; ---------------------------------------------------------------------------

(test working-memory-copies-what-the-context-shows
  "The snapshot holds the facts visible in the context, inherited ones
included, with its own goals and mode, and shares no list with it."
  (let* ((parent (make-context :name 'parent :facts '((shared 1))
                               :goals '((parent-goal))))
         (child (create-context :name 'child :parent parent
                                :facts '((own 2)) :goals '((child-goal))
                                :mode :plan))
         (*working-memory* nil)
         (wm (refresh-working-memory child)))
    (is (eq wm *working-memory*))
    (is (eq 'child (working-memory-context-name wm)))
    (is (equal '((shared 1) (own 2)) (working-memory-facts wm)))
    (is (equal '((child-goal)) (working-memory-goals wm)))
    (is (eq :plan (working-memory-mode wm)))
    (is (integerp (working-memory-captured-at wm)))
    ;; The context moves on; the snapshot does not.
    (context-add-fact! child '(later 3))
    (add-goal! child '(later-goal))
    (is (equal '((shared 1) (own 2)) (working-memory-facts wm)))
    (is (equal '((child-goal)) (working-memory-goals wm)))
    (let ((state (working-memory-state wm)))
      (is (equal '((shared 1) (own 2)) (state-facts state)))
      (is (eq 'child (state-source state)))
      (is (eq :current (state-kind state))))
    ;; What is not a context, or not a snapshot, gives NIL and changes nothing.
    (dolist (not-a-context '(nil 42 "child"))
      (is (null (refresh-working-memory not-a-context)))
      (is (eq wm *working-memory*))
      (is (null (working-memory-state not-a-context))))
    (is (eq t (clear-working-memory)))
    (is (null *working-memory*))
    (is (null (working-memory-state)))))

;;; ---------------------------------------------------------------------------
;;; Knowledge memory
;;; ---------------------------------------------------------------------------

(test knowledge-rules-are-newest-first-whether-named-or-not
  "KNOWLEDGE-ADD-RULE! orders rules as REGISTER-RULE! does. A merge puts the
knowledge rules first, in their order, and merging again adds no rule twice,
named or not."
  (flet ((rule (name tag)
           (make-rule :name name :if '((a ?x)) :then `(,tag ?x)))
         (tags (rules)
           (mapcar (lambda (rule) (first (first (rule-then rule)))) rules)))
    (let ((km (make-knowledge-memory))
          (registered (make-context :name 'registered)))
      (loop for (name tag) in '((r1 one) (nil two) (r3 three) (nil four)
                                (r1 five))
            do (is (rule-p (knowledge-add-rule! (rule name tag) km)))
               (register-rule! registered (rule name tag)))
      (is (equal '(five four three two) (tags (knowledge-memory-rules km))))
      (is (equal (tags (context-rules registered))
                 (tags (knowledge-memory-rules km))))
      (let ((target (make-context :name 'target
                                  :rules (list (rule 'r3 'replaced)
                                               (rule nil 'own)))))
        (dotimes (i 3)
          (knowledge-merge-into-context! target km)
          (is (equal '(five four three two own) (tags (context-rules target)))))
        ;; A context copied to knowledge and merged back is unchanged.
        (knowledge-merge-into-context! target (knowledge-from-context target))
        (is (equal '(five four three two own) (tags (context-rules target)))))
      (is (equal '(five four two)
                 (tags (knowledge-remove-rule! 'r3 km)))))))

(test knowledge-facts-are-asserted-once
  (let ((km (make-knowledge-memory))
        (ctx (make-context :name 'target :facts '((b 2)))))
    (dolist (fact '((a 1) (b 2) (a 1)))
      (is (equal fact (knowledge-add-fact! fact km))))
    (is (equal '((a 1) (b 2)) (knowledge-memory-facts km)))
    (dotimes (i 2)
      (knowledge-merge-into-context! ctx km)
      (is (equal '((b 2) (a 1)) (context-facts ctx))))
    (is (equal '((b 2)) (knowledge-remove-fact! '(a 1) km)))
    ;; The copy the context took stays in the context.
    (is (equal '((b 2) (a 1)) (context-facts ctx)))))

(test knowledge-merge-keeps-rule-order
  "Merging knowledge into a context any number of times leaves the rules in
the order knowledge memory has them, ahead of the rules only the context has."
  (flet ((rule (name)
           (make-rule :name name :if '((a ?x)) :then `(,name ?x)))
         (names (rules)
           (mapcar #'rule-name rules)))
    (let ((km (make-knowledge-memory
               :facts '((a 1))
               :rules (mapcar #'rule '(r1 r2 r3))))
          (ctx (make-context :name 'target
                             :rules (list (rule 'r2) (rule 'own)))))
      (dotimes (i 3)
        (knowledge-merge-into-context! ctx km)
        (is (equal '(r1 r2 r3 own) (names (context-rules ctx)))))
      (is (eq (second (knowledge-memory-rules km)) (second (context-rules ctx))))
      (is (fact-p '(a 1) (context-facts ctx)))
      ;; A context copied to knowledge and merged back is unchanged.
      (knowledge-merge-into-context! ctx (knowledge-from-context ctx))
      (is (equal '(r1 r2 r3 own) (names (context-rules ctx))))
      ;; A query sees derived facts only when asked to infer.
      (is (null (knowledge-query '(r1 ?x) :memory km)))
      (is (equal '((r1 1))
                 (mapcar (lambda (hit) (getf hit :fact))
                         (knowledge-query '(r1 ?x) :memory km :infer t)))))))
