;;;; tests/test-workbench.lisp — the Swift workbench keeps the gates the façade enforces

(in-package #:automa-gp/tests)

(def-suite workbench-suite :in automa-gp-suite)
(in-suite workbench-suite)

(test workbench-archive-use-waits-for-applies-probe
  "Swift workbench keeps Use idle while archive applies is refreshing."
  (let* ((root (asdf:system-relative-pathname :automa-gp
                                              "macos/AutomaGPWorkbench/Sources/AutomaGPWorkbench/"))
         (model (uiop:read-file-string
                 (merge-pathnames "WorkbenchModel.swift" root)))
         (view (uiop:read-file-string
                (merge-pathnames "WorkbenchView.swift" root))))
    (is (search "archiveProbePending" model))
    (is (search "archiveGateSnapshot" model))
    (is (search "!archiveProbePending" model))
    (is (search "externalActions = []" model))
    (is (search "externalMatches && externalSupported" model))
    (is (search "planReady && !externalSupported" model))
    (is (search "canSimulate && !planExternalPending" model))
    (is (search "planExternalPending = true" model))
    (is (search "autonomyAuthority" model))
    (is (search "case \"read\": return \"read\"" model))
    (is (search "archiveProbePending" view))
    (is (search "!card.applies" view))
    (is (search "model.archiveProbePending" view))
    (is (search "!model.connected" view))
    (is (search "guard connected else { return }" model))
    (is (search "!model.externalSupported" view))
    (is (search "model.planReady && !model.externalSupported" view))
    (is (search "model.planExternalPending" view))
    (is (search "Text(\"Leggi\").tag(\"read\")" view))
    (is (search "model.autonomyAuthority" view))
    (is (search "riconosce gli eventi in attesa" model))
    (is (search "Un passo: osserva, pianifica e simula" view))
    (is (search "Un passo: riconosce gli eventi" view))
    (is (search "Non tocca il computer." model))
    (is (null (search "La simulazione li lascia fermi" model)))))
