;;;; interface/narration.lisp — Italian sentences from a deliberative trace
;;;;
;;;; Templates only. Every sentence names a recorded entry. Nothing is
;;;; added about causes that the trace did not record.

(in-package #:automa-gp)

(defun %narrate-term (value)
  "Readable name for a symbol, number, or fact. Package prefixes are omitted."
  (cond
    ((symbolp value) (symbol-name value))
    ((consp value)
     (format nil "~{~A~^ ~}" (mapcar #'%narrate-term value)))
    (t (princ-to-string value))))

(defun %narrate-list (items)
  (format nil "~{~A~^, ~}" (mapcar #'%narrate-term items)))

(defun %narrate-entry (entry)
  "Return (TEXT . TONE) for ENTRY, or NIL when the entry has nothing to say.
TONE is :MISSING :MET :ACTION :REPAIR :ASIDE :GOAL :RESULT or :NOTE."
  (let ((kind (getf entry :kind)))
    (case kind
      (:begin
       (cons (format nil "Inizio la fase ~A."
                     (%narrate-term (getf entry :phase)))
             :note))
      (:context
       (cons (format nil "Il contesto è ~A."
                     (%narrate-term (getf entry :name)))
             :note))
      (:goal
       (cons (format nil "L'obiettivo è ~A."
                     (%narrate-term (getf entry :goal)))
             :goal))
      (:goals
       (cons (format nil "Gli obiettivi sono ~A."
                     (%narrate-list (getf entry :goals)))
             :goal))
      (:state
       (cons (format nil "Osservo ~A fatti."
                     (length (getf entry :facts)))
             :note))
      (:difference
       (cons (format nil "Manca ~A."
                     (%narrate-term (getf entry :goal)))
             :missing))
      (:differences
       (let ((goals (getf entry :goals)))
         (if (and (listp goals) (= (length goals) 1))
             (cons (format nil "Manca ~A." (%narrate-term (first goals)))
                   :missing)
             (cons (format nil "Mancano ~A."
                           (%narrate-list goals))
                   :missing))))
      (:missing-precondition
       (cons (format nil "Manca ~A per ~A.~@[ Riuso la procedura ~A.~]"
                     (%narrate-list (getf entry :goals))
                     (%narrate-term (getf entry :operator))
                     (and (getf entry :from-procedure)
                          (%narrate-term (getf entry :from-procedure))))
             :missing))
      (:repair-step
       (cons (format nil "Riparo con ~A per ~A."
                     (%narrate-term (getf entry :operator))
                     (%narrate-term (getf entry :goal)))
             :repair))
      (:step-set-aside
       (cons (format nil "Lascio da parte ~A per ~A."
                     (%narrate-term (getf entry :operator))
                     (%narrate-term (getf entry :goal)))
             :aside))
      (:selected-operator
       (cons (format nil "Scelgo ~A~A."
                     (%narrate-term (getf entry :operator))
                     (%fmt-bindings (getf entry :bindings)))
             :action))
      (:subgoal
       (cons (format nil "Prima serve ~A."
                     (%narrate-term (getf entry :goal)))
             :goal))
      (:precondition
       (let ((met (eq (getf entry :status) :satisfied)))
         (cons (format nil "~A ~A per ~A."
                       (%narrate-term (getf entry :goal))
                       (if met "è soddisfatto" "manca ancora")
                       (%narrate-term (getf entry :operator)))
               (if met :met :missing))))
      (:action
       (cons (format nil "Eseguo ~A~A."
                     (%narrate-term (getf entry :operator))
                     (%fmt-bindings (getf entry :bindings)))
             :action))
      (:result
       (cons (format nil "Il risultato è ~A."
                     (%narrate-term (getf entry :status)))
             :result))
      (:goal-already-satisfied
       (cons (format nil "~A è già vero."
                     (%narrate-term (getf entry :goal)))
             :met))
      (:projected-effects
       (cons (format nil "Proietto gli effetti di ~A per ~A."
                     (%narrate-term (getf entry :operator))
                     (%narrate-term (getf entry :goal)))
             :action))
      (:recorded-effects
       (cons (format nil "Applico gli effetti registrati di ~A per ~A."
                     (%narrate-term (getf entry :operator))
                     (%narrate-term (getf entry :goal)))
             :action))
      (:operator-failed
       (cons (format nil "L'operatore ~A non riesce."
                     (%narrate-term (getf entry :operator)))
             :missing))
      (:execution-step
       (cons (format nil "In modalità ~A, ~A risulta ~A."
                     (%narrate-term (getf entry :mode))
                     (%narrate-term (getf entry :operator))
                     (%narrate-term (getf entry :status)))
             :action))
      (:reused-procedure
       (cons (format nil "Riuso ~A, con punteggio ~,3F."
                     (%narrate-term (getf entry :name))
                     (or (getf entry :score) 0))
             :note))
      (:plan-complete
       (let ((steps (or (getf entry :steps) 0)))
         (if (getf entry :success)
             (cons (format nil "Il piano è pronto: ~A ~A."
                           steps
                           (if (eql steps 1) "passo" "passi"))
                   :result)
             (cons "Il piano si interrompe." :missing))))
      (:execution-complete
       (cons (format nil "L'esecuzione in ~A ~A."
                     (%narrate-term (getf entry :mode))
                     (if (getf entry :success) "riesce" "non riesce"))
             :result))
      (otherwise nil))))

(defun narrate-trace (trace)
  "Italian text and a node list derived only from TRACE.
Returns (VALUES TEXT NODES). NODES are plists (:text :tone).
Without a trace, TEXT says so and NODES is NIL."
  (unless (deliberative-trace-p trace)
    (return-from narrate-trace
      (values "Non c'è ancora un ragionamento registrato." nil)))
  (let ((nodes (loop for entry in (trace-entries trace)
                     for spoken = (%narrate-entry entry)
                     when spoken
                       collect (list :text (car spoken) :tone (cdr spoken)))))
    (values (if nodes
                (format nil "~{~A~%~}" (mapcar (lambda (n) (getf n :text)) nodes))
                "Il ragionamento registrato non ha passi da raccontare.")
            nodes)))

(defun gp-narrate (&optional (topic :last))
  "Narrate TOPIC (:LAST :PLAN :EXECUTION, a plan, or a trace).
Returns (VALUES TEXT NODES). Sentences come from recorded entries only."
  (narrate-trace (resolve-explain-topic topic)))
