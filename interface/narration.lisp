;;;; interface/narration.lisp — Italian sentences from a deliberative trace
;;;;
;;;; Templates only. Every sentence names a recorded entry, and every
;;;; recorded entry gets a sentence. Nothing is added about causes that the
;;;; trace did not record.

(in-package #:automa-gp)

(defun %narrate-term (value)
  "Readable name for a symbol, number, or fact. Package prefixes are omitted.
A fact reads as its elements separated by spaces; a dotted tail keeps its dot."
  (cond
    ((symbolp value) (symbol-name value))
    ((consp value)
     (format nil "~{~A~^ ~}"
             (loop for cell = value then (cdr cell)
                   while (consp cell)
                   collect (%narrate-term (car cell))
                   when (and (cdr cell) (atom (cdr cell)))
                     collect "." and collect (%narrate-term (cdr cell)))))
    (t (princ-to-string value))))

(defun %narrate-list (items)
  "The readable names of ITEMS, separated by commas."
  (format nil "~{~A~^, ~}" (mapcar #'%narrate-term items)))

(defun %narrate-counted (items singular plural)
  "SINGULAR and the one item, or PLURAL and the ITEMS; NIL when there are none."
  (when items
    (format nil "~A ~A" (if (rest items) plural singular) (%narrate-list items))))

(defun %narrate-missing (goals)
  "\"Manca A\" or \"Mancano A, B\"; NIL when no goal is missing."
  (%narrate-counted goals "Manca" "Mancano"))

(defun %narrate-event (entry)
  "(TEXT . TONE) for an :EVENT ENTRY: an event posted, or the reactions to
one. NIL when its :ACTION is not one that EMIT-EVENT! or REACT-TO-EVENT!
records."
  (let ((type (%narrate-term (getf entry :type)))
        (matched (getf entry :matched)))
    (case (getf entry :action)
      (:emit
       (cons (format nil "Arriva l'evento ~A."
                     (%narrate-term (cons (getf entry :type) (getf entry :data))))
             :note))
      (:react
       (cons (if matched
                 (format nil "All'evento ~A ~A.~@[ ~A.~]~@[ ~A.~]"
                         type
                         (%narrate-counted matched "reagisce" "reagiscono")
                         (%narrate-counted (getf entry :facts)
                                           "Aggiungo il fatto" "Aggiungo i fatti")
                         (%narrate-counted (getf entry :goals)
                                           "Aggiungo l'obiettivo"
                                           "Aggiungo gli obiettivi"))
                 (format nil "Nessuna reazione corrisponde all'evento ~A." type))
             :note)))))

(defun %narrate-entry (entry)
  "Return (TEXT . TONE) for ENTRY.
TONE is :MISSING :MET :ACTION :REPAIR :ASIDE :GOAL :RESULT or :NOTE.
An entry of a kind with no template is named as such, never skipped."
  (flet ((as-recorded ()
           (cons (format nil "Trovo una voce ~A che non so raccontare."
                         (%narrate-term (getf entry :kind)))
                 :note)))
    (case (getf entry :kind)
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
       (cons (format nil "~A."
                     (or (%narrate-counted (getf entry :goals)
                                           "L'obiettivo è" "Gli obiettivi sono")
                         "Non ci sono obiettivi"))
             :goal))
      (:state
       (let ((count (length (getf entry :facts))))
         (cons (format nil "Osservo ~D ~:[fatti~;fatto~]." count (= count 1))
               :note)))
      (:difference
       (cons (format nil "Manca ~A."
                     (%narrate-term (getf entry :goal)))
             :missing))
      (:differences
       (let ((missing (%narrate-missing (getf entry :goals))))
         (if missing
             (cons (format nil "~A." missing) :missing)
             (cons "Non manca nulla." :met))))
      (:missing-precondition
       (cons (format nil "~A per ~A.~@[ Riuso la procedura ~A.~]"
                     (or (%narrate-missing (getf entry :goals))
                         "Manca una precondizione")
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
       (cons (format nil "Il risultato~@[ per ~A~] è ~A."
                     (and (getf entry :goal)
                          (%narrate-term (getf entry :goal)))
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
       (cons (format nil "L'operatore ~A non riesce~@[ (~A)~].~@[ ~A.~]"
                     (%narrate-term (getf entry :operator))
                     (and (getf entry :reason)
                          (%narrate-term (getf entry :reason)))
                     (%narrate-missing (getf entry :missing)))
             :missing))
      (:execution-step
       (cons (format nil "In modalità ~A, ~A risulta ~A."
                     (%narrate-term (getf entry :mode))
                     (%narrate-term (getf entry :operator))
                     (%narrate-term (getf entry :status)))
             :action))
      (:reused-procedure
       (cons (format nil "Riuso ~A~@[, con punteggio ~,3F~]."
                     (%narrate-term (getf entry :name))
                     (getf entry :score))
             :note))
      (:plan-complete
       (let ((steps (getf entry :steps)))
         (if (getf entry :success)
             (cons (format nil "Il piano è pronto~@[: ~A~]."
                           (and steps
                                (format nil "~D ~:[passi~;passo~]"
                                        steps (eql steps 1))))
                   :result)
             (cons (format nil "Il piano si interrompe.~@[ ~A.~]"
                           (%narrate-missing (getf entry :remaining)))
                   :missing))))
      (:execution-complete
       (cons (format nil "L'esecuzione in ~A ~A."
                     (%narrate-term (getf entry :mode))
                     (if (getf entry :success) "riesce" "non riesce"))
             :result))
      (:event
       (or (%narrate-event entry) (as-recorded)))
      (otherwise
       (as-recorded)))))

(defun narrate-trace (trace)
  "Italian text and a node list derived only from TRACE.
Returns (VALUES TEXT NODES). NODES are plists (:text :tone), one per
recorded entry, oldest first. Neither depends on the caller's *PACKAGE* or
printer settings. Without a trace, TEXT says so and NODES is NIL."
  (unless (deliberative-trace-p trace)
    (return-from narrate-trace
      (values "Non c'è ancora un ragionamento registrato." nil)))
  (let ((nodes (%with-standard-printing
                 (loop for entry in (%chronological-entries trace)
                       for (text . tone) = (%narrate-entry entry)
                       collect (list :text text :tone tone)))))
    (values (if nodes
                (format nil "~{~A~%~}" (mapcar (lambda (n) (getf n :text)) nodes))
                "Il ragionamento registrato non ha passi da raccontare.")
            nodes)))

(defun gp-narrate (&optional (topic :last))
  "Narrate TOPIC: :LAST :PLAN :EXECUTION :HISTORY, a plan, an execution
result, or a trace (see RESOLVE-EXPLAIN-TOPIC).
Returns (VALUES TEXT NODES). Sentences come from recorded entries only."
  (narrate-trace (resolve-explain-topic topic)))
