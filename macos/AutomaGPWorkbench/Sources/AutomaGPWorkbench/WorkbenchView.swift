import SwiftUI

@main
struct AutomaGPWorkbenchApp: App {
    var body: some Scene {
        WindowGroup("AUTOMA GP") {
            WorkbenchView()
        }
        .defaultSize(width: 1180, height: 760)
    }
}

struct WorkbenchView: View {
    @StateObject private var model = WorkbenchModel()
    @State private var confirmExecute = false
    @State private var confirmAutonomy = false
    @State private var confirmAutonomyLoop = false
    @FocusState private var nameFocused: Bool

    private var repairCount: Int {
        model.nodes.filter { $0.tone == "repair" }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !model.connected {
                disconnected
            }
            Divider()
            HSplitView {
                reasoning
                archive
                action
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.start() }
        .onChange(of: model.listening) { listening in
            if listening { nameFocused = true }
        }
        .confirmationDialog(
            "Eseguire il piano sul contesto?",
            isPresented: $confirmExecute,
            titleVisibility: .visible
        ) {
            Button("Esegui", role: .destructive) { model.execute() }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(model.executeDialogMessage)
        }
        .confirmationDialog(
            model.authority == "execute"
                ? "Lanciare un passo autonomo con esecuzione?"
                : "Lanciare un passo autonomo?",
            isPresented: $confirmAutonomy,
            titleVisibility: .visible
        ) {
            Button(model.authority == "execute" ? "Passo con esecuzione" : "Passo",
                   role: model.authority == "execute" ? .destructive : nil) {
                model.autonomyStep()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(model.autonomyDialogMessage)
        }
        .confirmationDialog(
            model.authority == "execute"
                ? "Lanciare un ciclo autonomo con esecuzione?"
                : "Lanciare un ciclo autonomo?",
            isPresented: $confirmAutonomyLoop,
            titleVisibility: .visible
        ) {
            Button(model.authority == "execute" ? "Ciclo con esecuzione" : "Ciclo",
                   role: model.authority == "execute" ? .destructive : nil) {
                model.autonomyLoop()
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text(model.autonomyLoopDialogMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("AUTOMA GP")
                    .font(.title2.weight(.semibold))
                Text(model.connected ? model.statusLine : "Tavolo di lavoro")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if model.listening {
                Label("In ascolto", systemImage: "ear")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .help("Un piano è incompleto. Il passo successivo è indurre la regola.")
            }
            Button("Aggiorna") { model.refresh() }
                .keyboardShortcut("r", modifiers: .command)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var disconnected: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "circle.fill")
                .foregroundStyle(.orange)
                .font(.caption2)
            Text("Il server non risponde. Nel Terminale: ./scripts/run-web.sh")
                .font(.callout)
            Spacer()
            Text(model.baseURL)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private var reasoning: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ragionamento", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            Text(model.nodes.isEmpty
                 ? "Quando pianifichi, ogni passo compare qui. Il rosso è ciò che manca."
                 : "In questa traccia: \(repairCount) riparazioni. Il limite d'archivio è \(model.repairDepth).")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(model.nodes) { node in
                        HStack(alignment: .top, spacing: 10) {
                            Circle()
                                .fill(toneColor(node.tone))
                                .frame(width: 10, height: 10)
                                .padding(.top, 5)
                            Text(node.text)
                                .font(.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .padding(10)
                        .background(toneColor(node.tone).opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.vertical, 4)
            }
            if !model.narration.isEmpty {
                DisclosureGroup("Leggi il racconto") {
                    Text(model.narration)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.callout)
            }
        }
        .padding(14)
        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var archive: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Archivio", systemImage: "archivebox")
                .font(.headline)
            Text(model.cards.isEmpty
                 ? "Una procedura compare dopo un piano riuscito."
                 : "Scegli una scheda per ricostruire quel piano.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.cards) { card in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(card.name)
                                    .font(.headline)
                                Spacer()
                                Text(scoreLabel(card))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(card.successes) successi · \(card.failures) fallimenti · \(card.steps) passi")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !card.operators.isEmpty {
                                Text(card.operators)
                                    .font(.caption.monospaced())
                                    .lineLimit(2)
                            }
                            Button("Usa questo piano") { model.use(name: card.name) }
                                .controlSize(.small)
                                .help("Ricostruisce il piano da \(card.name)")
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .padding(14)
        .frame(minWidth: 260, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var action: some View {
        VStack(alignment: .leading, spacing: 12) {
            nextStep
            facts
            if !model.notice.isEmpty {
                Text(model.notice)
                    .font(.callout)
                    .foregroundStyle(model.noticeIsError ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var nextStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(model.listening ? "Prossimo passo" : "Piano", systemImage: "arrow.right.circle")
                .font(.headline)
            if model.listening {
                Text(model.missingLabel.isEmpty
                     ? "Il piano è incompleto."
                     : "Manca \(model.missingLabel).")
                    .font(.callout)
                Text("Modifica i fatti qui sotto, controlla il nome, poi registra la regola.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Nome della regola", text: $model.actionName)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                Button("Induci regola") { model.learnRule() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.actionName.trimmingCharacters(in: .whitespaces).isEmpty)
                HStack {
                    Button("Annota lo stato") { model.noteState() }
                        .controlSize(.small)
                    Button("Senza variabili") { model.learn() }
                        .controlSize(.small)
                        .help("Unisce un secondo esempio solo se i termini restano gli stessi. Non introduce variabili.")
                }
            } else {
                Text("Scrivi l'obiettivo o il nome dell'operatore. Poi simula, oppure conferma l'esecuzione.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    TextField("predicato termini", text: $model.phraseDraft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.ask() }
                    Button("Chiedi") { model.ask() }
                        .disabled(model.phraseDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Il nome dell'operatore, di una reazione o di una regola vale come predicato. Una parola dichiarata, come accendi, vale anche per accendere. Una parola da sola vale se è un termine di un solo obiettivo senza variabili, anche in un'altra forma come pronti, prontissimo, prontamente o prontezza per pronto, o accensione e accendimento per accendi, o un pezzo esatto del suo nome. Una parola che è la radice di un nome, come power-one per power-on, non viene proposta. Se le altre parole descrivono l'obiettivo e la prima non ne fa parte, l'obiettivo viene nominato e la parola non viene dichiarata. Se è in più di un obiettivo, li nomina e non ne registra nessuno. Non esegue comandi.")
                }
                if !model.choices.isEmpty {
                    Text(model.choices.contains(where: \.declaresWord)
                         ? "La prima parola non è dichiarata. Scegli chi la riceve."
                         : model.choices.count > 1
                           ? "Più di un obiettivo. Scegline uno."
                           : "Le altre parole descrivono questo obiettivo. La parola non viene dichiarata.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(model.choices) { choice in
                        HStack {
                            Text(choice.declaresWord
                                 ? "\(choice.kindLabel) \(choice.name) · \(choice.goal.label)"
                                 : choice.goal.label)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Button(choice.declaresWord ? "Chiama così" : "Usa questo") {
                                model.choose(choice)
                            }
                            .help(choice.declaresWord
                                  ? "Dichiara la parola su questo nome, registra l'obiettivo e aggiorna il piano. Non esegue."
                                  : "Registra solo questo obiettivo e aggiorna il piano. Non esegue.")
                        }
                    }
                }
                HStack {
                    Button("Pianifica") { model.planOpenGoals() }
                        .disabled(model.openGoals == 0)
                        .help("Pianifica gli obiettivi già nel contesto. Non simula e non esegue.")
                    Button("Simula") { model.simulate() }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(!model.externalMatches || model.executeLacksSupport)
                        .keyboardShortcut(.return, modifiers: .command)
                        .help(!model.externalMatches
                              ? "L'azione sul computer non è più quella del piano. Pianifica di nuovo."
                              : model.executeLacksSupport
                                ? "I fatti non sostengono più l'azione sul computer. Pianifica di nuovo."
                                : "Applica il piano su una copia. I fatti del contesto restano fermi.")
                    Button("Esegui…") { confirmExecute = true }
                        .disabled(model.executeLacksSupport || !model.externalMatches)
                        .tint(.red)
                        .help(model.executeConfirmsComputer
                              ? "Chiede conferma, poi aggiorna i fatti e compie l'azione sul computer."
                              : model.executeLacksSupport
                                ? "I fatti non sostengono più l'azione sul computer. Pianifica di nuovo."
                                : !model.externalMatches
                                  ? "L'azione sul computer non è più quella del piano. Pianifica di nuovo."
                                  : model.executeWithholdsComputer
                                    ? "Chiede conferma, poi aggiorna i fatti. L'azione sul computer non parte: le precondizioni non ci sono più."
                                    : "Chiede conferma, poi aggiorna i fatti. Non tocca il computer.")
                }
                if model.executeConfirmsComputer {
                    Text("Sul computer, solo dopo conferma: \(model.externalSummary)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.executeLacksSupport {
                    Text("L'azione sul computer non parte: i fatti non la sostengono più. Pianifica di nuovo.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.executeWithholdsComputer {
                    Text("L'azione sul computer non parte: le precondizioni non ci sono più. \(model.externalWithheldSummary)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !model.externalMatches {
                    Text("L'azione sul computer non è più quella del piano. Pianifica di nuovo.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Picker("Autonomia", selection: Binding(
                        get: { model.authority == "execute" ? "execute" : "simulate" },
                        set: { model.setAuthority($0) }
                    )) {
                        Text("Simula").tag("simulate")
                        Text("Esegui").tag("execute")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Tetto di passo e ciclo autonomi. Non li lancia.")
                    Button(model.authority == "execute" ? "Passo…" : "Passo") {
                        if model.authority == "execute" {
                            confirmAutonomy = true
                        } else {
                            model.autonomyStep()
                        }
                    }
                    .disabled(!model.connected)
                    .tint(model.authority == "execute" ? .red : .accentColor)
                    .help(model.authority == "execute"
                          ? "Chiede conferma, poi un ciclo: osserva, pianifica ed esegue. Sul computer solo se il piano nuovo lo richiede."
                          : "Un ciclo: osserva, pianifica e simula. I fatti del contesto restano fermi.")
                    Button(model.authority == "execute" ? "Ciclo…" : "Ciclo") {
                        if model.authority == "execute" {
                            confirmAutonomyLoop = true
                        } else {
                            model.autonomyLoop()
                        }
                    }
                    .disabled(!model.connected)
                    .tint(model.authority == "execute" ? .red : .accentColor)
                    .help(model.authority == "execute"
                          ? "Chiede conferma, poi fino a \(model.autonomyMaxSteps) passi con esecuzione. Si ferma a obiettivo o a un rifiuto."
                          : "Fino a \(model.autonomyMaxSteps) passi di simulazione. I fatti restano fermi. Si ferma a obiettivo o a un rifiuto.")
                }
                HStack {
                    Text("Limite ciclo")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(value: Binding(
                        get: { model.autonomyMaxSteps },
                        set: { model.setMaxSteps($0) }
                    ), in: 1...32) {
                        Text("\(model.autonomyMaxSteps)")
                            .font(.caption.monospacedDigit())
                            .frame(minWidth: 24, alignment: .trailing)
                    }
                    .disabled(!model.connected)
                    .help("Quanti passi al massimo fa Ciclo. Resta nella policy di sessione.")
                    Spacer(minLength: 0)
                }
                Text(model.authority == "execute"
                     ? "L'autonomia può eseguire. Passo… e Ciclo… chiedono conferma."
                     : "L'autonomia si ferma alla simulazione. Fino a \(model.autonomyMaxSteps) passi per ciclo.")
                    .font(.caption)
                    .foregroundStyle(model.authority == "execute" ? Color.red : Color.secondary)
                if !model.autonomyLastLine.isEmpty {
                    Text(model.autonomyLastLine)
                        .font(.caption)
                        .foregroundStyle(model.autonomyLastIsError ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .help("Ultimo esito di Passo o Ciclo, anche dopo un aggiornamento.")
                }
            }
            if let learned = model.learned {
                VStack(alignment: .leading, spacing: 2) {
                    Text(learned.examples > 1
                         ? "\(learned.name) · \(learned.examples) esempi"
                         : learned.name)
                        .font(.headline)
                    Text("Prima \(learned.preconditions)")
                    Text("Aggiunge \(learned.adds)")
                    Text("Toglie \(learned.deletes)")
                    HStack {
                        TextField("parola, come spegni", text: $model.wordDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.nameOperator() }
                        Button("Chiama così") { model.nameOperator() }
                            .disabled(model.wordDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("Dichiara una parola per questo operatore. Chiedi la riconosce, anche con la stessa radice.")
                    }
                }
                .font(.caption.monospaced())
                .textSelection(.enabled)
            }
            aliasNaming
        }
    }

    private var aliasNaming: some View {
        Group {
            if !model.aliases.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Già nel contesto")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.aliases.count > 1 {
                        Picker("Già nel contesto", selection: $model.aliasTarget) {
                            ForEach(model.aliases) { item in
                                Text(item.label).tag(item.id)
                            }
                        }
                        .labelsHidden()
                    } else if let only = model.aliases.first {
                        Text(only.label)
                            .font(.callout.monospaced())
                    }
                    if let current = model.aliases.first(where: { $0.id == model.aliasTarget }),
                       !current.words.isEmpty {
                        Text("Risponde a \(current.words.joined(separator: ", ")).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        TextField("parola, come spegni", text: $model.aliasDraft)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { model.nameAlias() }
                        Button("Chiama così") { model.nameAlias() }
                            .disabled(model.aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .help("Dichiara una parola per l'operatore, la reazione o la regola scelta, anche se un altro ha lo stesso nome. L'operatore appena imparato resta nel suo campo. Chiedi la riconosce, anche con la stessa radice. Il nome proprio resta esatto.")
                    }
                }
            }
        }
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Fatti", systemImage: "list.bullet")
                .font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if model.factLines.isEmpty {
                        Text("Nessun fatto nel contesto.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.factLines) { fact in
                        HStack(alignment: .firstTextBaseline) {
                            Text(fact.label)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                            Spacer(minLength: 8)
                            Button {
                                model.removeFact(fact)
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Togli questo fatto")
                        }
                    }
                }
            }
            HStack {
                TextField("predicato oggetto valore", text: $model.factDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.addFact() }
                Button("Aggiungi") { model.addFact() }
                    .disabled(model.factDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            HStack {
                TextField("Percorso di un file", text: $model.pathDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.noticePath() }
                Button("Nota il file") { model.noticePath() }
                    .disabled(model.pathDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Solo se una reazione descrive già un file creato. Non scorre una cartella.")
                Button("Nota la cartella") { model.noticeDirectory() }
                    .disabled(model.pathDraft.trimmingCharacters(in: .whitespaces).isEmpty || model.watchingDirectory)
                    .help("Guarda una volta i file in questa cartella e nelle sottocartelle. Non segue un collegamento a un'altra cartella, non osserva i processi e non esegue il piano.")
                Button(model.watchingDirectory ? "Ferma" : "Osserva") { model.watchDirectory() }
                    .disabled(!model.watchingDirectory && model.pathDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Ripete lo sguardo sulla cartella e sulle sottocartelle finché non lo fermi. Non segue un collegamento a un'altra cartella, non osserva i processi e non esegue il piano.")
                Button("Nota i processi") { model.noticeProcesses() }
                    .disabled(model.watchingProcesses)
                    .help("Guarda una volta i processi che una reazione nomina già. Non elenca tutti i processi, non guarda il terminale e non esegue il piano.")
                Button(model.watchingProcesses ? "Ferma i processi" : "Osserva i processi") {
                    model.watchProcesses()
                }
                .help("Ripete lo sguardo sui processi che una reazione nomina già, finché non lo fermi. Non elenca tutti i processi, non guarda il terminale e non esegue il piano.")
                Button("Nota il terminale") { model.noticeTerminals() }
                    .disabled(model.watchingTerminals)
                    .help("Guarda una volta i terminali che una reazione nomina già. Non legge ciò che ci è scritto, non elenca tutti i terminali e non esegue il piano.")
                Button(model.watchingTerminals ? "Ferma il terminale" : "Osserva il terminale") {
                    model.watchTerminals()
                }
                .help("Ripete lo sguardo sui terminali che una reazione nomina già, finché non lo fermi. Non legge ciò che ci è scritto, non elenca tutti i terminali e non esegue il piano.")
                Button("Nota il testo") { model.noticeTerminalText() }
                    .disabled(model.watchingTerminalText)
                    .help("Legge una volta il testo che una reazione nomina già, nel trascritto che quella reazione nomina. Non segue un collegamento, non apre un dispositivo, non resta in ascolto e non esegue il piano.")
                Button(model.watchingTerminalText ? "Ferma il testo" : "Osserva il testo") {
                    model.watchTerminalText()
                }
                .help("Ripete la lettura del testo che una reazione nomina già, finché non la fermi. Non segue un collegamento, non apre un dispositivo, non legge lo schermo aperto di Terminale e non esegue il piano.")
                Button("Nota lo schermo") { model.noticeTerminalScreen() }
                    .disabled(model.watchingTerminalScreen)
                    .help("Legge una volta il testo che una reazione nomina già, nella scheda di Terminale che quella reazione nomina. Non scrive nella scheda, non lancia un comando e non resta in ascolto. Se Terminale non risponde, non aggiunge nulla.")
                Button(model.watchingTerminalScreen ? "Ferma lo schermo" : "Osserva lo schermo") {
                    model.watchTerminalScreen()
                }
                .help("Ripete la lettura della scheda che una reazione nomina già, finché non la fermi. Non scrive nella scheda e non lancia un comando. Se Terminale non risponde, non aggiunge nulla.")
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func scoreLabel(_ card: ArchiveCard) -> String {
        if card.successes == 0 && card.failures == 0 {
            return "nuova"
        }
        return "\(card.successes) su \(card.successes + card.failures)"
    }

    private func toneColor(_ tone: String) -> Color {
        switch tone {
        case "missing": return .red
        case "met": return .green
        case "repair": return .orange
        case "action": return .accentColor
        case "goal": return .blue
        case "result": return .primary
        case "aside": return .secondary
        default: return .secondary
        }
    }
}
