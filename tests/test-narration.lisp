;;;; tests/test-narration.lisp — Italian narration reads only the recorded trace

(in-package #:automa-gp/tests)

(def-suite narration-suite :in automa-gp-suite)
(in-suite narration-suite)

(test narrate-trace-uses-recorded-operators-only
  (clear-trace-session)
  (let* ((facts '((device interface-01) (power-state interface-01 off)))
         (goals '((connection interface-01 computer)))
         (ops (list (make-operator :name 'power-on
                                   :preconditions '((device ?d) (power-state ?d off))
                                   :add-list '((power-state ?d on))
                                   :delete-list '((power-state ?d off)))
                    (make-operator :name 'connect
                                   :preconditions '((device ?d) (power-state ?d on))
                                   :add-list '((connection ?d computer)))))
         (plan (plan-for facts goals ops :context-name 'studio-audio)))
    (multiple-value-bind (text nodes) (narrate-trace (trace-of plan))
      (is (search "POWER-ON" text))
      (is (search "CONNECT" text))
      (is (search "Manca" text))
      (is (search "Scelgo" text))
      (is (not (search "QUICKLIME" text)))
      (is (find :missing nodes :key (lambda (n) (getf n :tone))))
      (is (find :action nodes :key (lambda (n) (getf n :tone)))))))

(test narrate-without-trace-does-not-invent
  (clear-trace-session)
  (multiple-value-bind (text nodes) (gp-narrate :last)
    (is (null nodes))
    (is (search "Non c'è ancora un ragionamento registrato" text))
    (is (not (search "POWER-ON" text)))))

;;; %RECORDED-TRACE is defined in tests/test-explanation.lisp, loaded before
;;; this file.

(defun %spoken (entry)
  "The sentence NARRATE-TRACE gives ENTRY, recorded alone after :BEGIN."
  (getf (second (nth-value 1 (narrate-trace (%recorded-trace entry)))) :text))

(test narration-reads-any-term
  "A dotted goal entered at the REPL must not take the narration down."
  (loop for (term expected) in '(((a . b) "A . B")
                                 ((a b . c) "A B . C")
                                 ((a (b . c)) "A B . C")
                                 ((a b) "A B")
                                 (42 "42")
                                 ("x y" "x y")
                                 (nil "NIL"))
        do (is (equal (format nil "L'obiettivo è ~A." expected)
                      (%spoken (list :goal :goal term)))
               "term ~S" term)))

(test narration-agrees-in-number-and-says-when-a-list-is-empty
  (loop for (entry expected)
          in '(((:goals :goals nil) "Non ci sono obiettivi.")
               ((:goals :goals ((a 1))) "L'obiettivo è A 1.")
               ((:goals :goals ((a 1) (b 2))) "Gli obiettivi sono A 1, B 2.")
               ((:state :facts nil) "Osservo 0 fatti.")
               ((:state :facts ((a 1))) "Osservo 1 fatto.")
               ((:state :facts ((a 1) (b 2))) "Osservo 2 fatti.")
               ((:differences :goals nil) "Non manca nulla.")
               ((:differences :goals ((a 1))) "Manca A 1.")
               ((:differences :goals ((a 1) (b 2))) "Mancano A 1, B 2.")
               ((:missing-precondition :operator op :goals nil)
                "Manca una precondizione per OP.")
               ((:missing-precondition :operator op :goals ((a 1)))
                "Manca A 1 per OP.")
               ((:missing-precondition :operator op :goals ((a 1) (b 2))
                 :from-procedure fill)
                "Mancano A 1, B 2 per OP. Riuso la procedura FILL.")
               ((:plan-complete :success t :steps 1) "Il piano è pronto: 1 passo.")
               ((:plan-complete :success t :steps 2) "Il piano è pronto: 2 passi."))
        do (is (equal expected (%spoken entry)) "entry ~S" entry)))

(test narration-names-what-failed
  "The goal, the reason and the missing facts are recorded: say them."
  (loop for (entry expected)
          in '(((:result :status :no-operator :goal (q 1))
                "Il risultato per Q 1 è NO-OPERATOR.")
               ((:result :status :ok) "Il risultato è OK.")
               ((:operator-failed :operator op :reason :preconditions-unmet
                 :missing ((q 1) (r 2)))
                "L'operatore OP non riesce (PRECONDITIONS-UNMET). Mancano Q 1, R 2.")
               ((:operator-failed :operator op :missing ((q 1)))
                "L'operatore OP non riesce. Manca Q 1.")
               ((:operator-failed :operator op) "L'operatore OP non riesce.")
               ((:plan-complete :success nil :steps 0 :remaining ((q 1) (r 2)))
                "Il piano si interrompe. Mancano Q 1, R 2.")
               ((:plan-complete :success nil :steps 0) "Il piano si interrompe."))
        do (is (equal expected (%spoken entry)) "entry ~S" entry))
  (let ((text (narrate-trace (trace-of (plan-for '((p 1)) '((q 1)) nil)))))
    (is (search "Il risultato per Q 1 è NO-OPERATOR." text))
    (is (search "Il piano si interrompe. Manca Q 1." text))))

(test narration-does-not-invent-what-was-not-recorded
  (loop for (entry expected)
          in '(((:reused-procedure :name fill) "Riuso FILL.")
               ((:reused-procedure :name fill :score 0.5)
                "Riuso FILL, con punteggio 0.500.")
               ((:plan-complete :success t) "Il piano è pronto."))
        do (is (equal expected (%spoken entry)) "entry ~S" entry)))

(test narration-speaks-events-and-unknown-kinds
  (loop for (entry expected)
          in '(((:event :action :emit :type file-created :data ("a.pdf") :id evt-1)
                "Arriva l'evento FILE-CREATED a.pdf.")
               ((:event :action :react :type ping :id evt-1
                 :matched (r1) :facts ((a 1)) :goals ((g 1)))
                "All'evento PING reagisce R1. Aggiungo il fatto A 1. Aggiungo l'obiettivo G 1.")
               ((:event :action :react :type ping :id evt-1
                 :matched (r1 r2) :facts ((a 1) (b 2)) :goals nil)
                "All'evento PING reagiscono R1, R2. Aggiungo i fatti A 1, B 2.")
               ((:event :action :react :type ping :id evt-1
                 :matched (r1) :facts nil :goals ((g 1) (h 2)))
                "All'evento PING reagisce R1. Aggiungo gli obiettivi G 1, H 2.")
               ((:event :action :react :type disk-full :id evt-2 :matched nil)
                "Nessuna reazione corrisponde all'evento DISK-FULL.")
               ((:custom-note :about (a 1))
                "Trovo una voce CUSTOM-NOTE che non so raccontare."))
        do (is (equal expected (%spoken entry)) "entry ~S" entry)))
