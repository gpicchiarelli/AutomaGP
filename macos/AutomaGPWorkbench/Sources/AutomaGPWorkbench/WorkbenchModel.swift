import Foundation

struct TraceNode: Identifiable {
    let id: Int
    let text: String
    let tone: String
}

struct ArchiveCard: Identifiable {
    var id: String { name }
    let name: String
    let score: Double
    let successes: Int
    let failures: Int
    let steps: Int
    let operators: String
    /// True when stored steps still rebuild a plan on the current facts.
    let applies: Bool
}

struct FactLine: Identifiable, Equatable {
    let parts: [String]
    var id: String { parts.joined(separator: "\u{1f}") }
    var label: String { parts.joined(separator: " ") }
}

struct GoalChoice: Identifiable, Equatable {
    let kind: String
    let name: String
    let word: String
    let goal: FactLine
    var id: String { "\(kind):\(name):\(word):\(goal.id)" }
    var declaresWord: Bool { !kind.isEmpty && !name.isEmpty && !word.isEmpty }
    var kindLabel: String {
        switch kind {
        case "operator": return "operatore"
        case "reaction": return "reazione"
        case "rule": return "regola"
        default: return kind
        }
    }
}

struct InducedOperator {
    let name: String
    let preconditions: String
    let adds: String
    let deletes: String
    let examples: Int
}

struct ExternalAction: Identifiable, Equatable {
    let id: Int
    let label: String
}

struct AliasTarget: Identifiable, Equatable {
    let kind: String
    let name: String
    let words: [String]
    var id: String { "\(kind):\(name)" }
    var label: String {
        switch kind {
        case "rule": return "regola \(name)"
        case "operator": return "operatore \(name)"
        default: return "reazione \(name)"
        }
    }
}

@MainActor
final class WorkbenchModel: ObservableObject {
    @Published var baseURL = "http://127.0.0.1:47391"
    @Published var connected = false
    @Published var statusLine = "In attesa del server Lisp."
    @Published var repairDepth = 0
    @Published var authority = "simulate"
    @Published var autonomyMaxSteps = 8
    @Published var autonomyLastLine = ""
    @Published var autonomyLastIsError = false
    @Published var nodes: [TraceNode] = []
    @Published var narration = ""
    @Published var cards: [ArchiveCard] = []
    @Published var factLines: [FactLine] = []
    @Published var factDraft = ""
    @Published var pathDraft = ""
    @Published var phraseDraft = ""
    @Published var choices: [GoalChoice] = []
    @Published var wordDraft = ""
    @Published var aliasDraft = ""
    @Published var aliasTarget = ""
    @Published var aliases: [AliasTarget] = []
    @Published var missingLabel = ""
    @Published var notice = ""
    @Published var noticeIsError = false
    @Published var actionName = ""
    @Published var learned: InducedOperator?
    @Published var listening = false
    @Published var watchingDirectory = false
    @Published var watchingProcesses = false
    @Published var watchingTerminals = false
    @Published var watchingTerminalText = false
    @Published var watchingTerminalScreen = false
    @Published var openGoals = 0
    @Published var pendingEvents = 0
    @Published var hasPlan = false
    @Published var planSuccess = false
    @Published var externalActions: [ExternalAction] = []
    @Published var externalWithheld: [ExternalAction] = []
    @Published var externalMatches = true
    @Published var externalSupported = true
    /// True while status says the world may have changed and archive applies
    /// has not been refreshed yet — Use stays idle (HTML console parity).
    @Published var archiveProbePending = false
    /// True from status until this refresh's plan GET returns — Esegui stays
    /// idle so adapters cannot follow a stale cleared external list (HTML Run).
    @Published var planExternalPending = false

    private var archiveGateSnapshot = ""

    var externalSummary: String {
        externalActions.map(\.label).joined(separator: " · ")
    }

    var externalWithheldSummary: String {
        externalWithheld.map(\.label).joined(separator: " · ")
    }

    var executeConfirmsComputer: Bool {
        planReady && !externalActions.isEmpty && externalMatches && externalSupported
    }

    var executeWithholdsComputer: Bool {
        planReady && externalActions.isEmpty && !externalWithheld.isEmpty && externalMatches
    }

    /// Passo and Ciclo only when something remains to observe or achieve.
    var autonomyHasWork: Bool {
        openGoals > 0 || pendingEvents > 0
    }

    /// A plan object exists and Means-Ends Analysis succeeded.
    var planReady: Bool {
        hasPlan && planSuccess
    }

    /// Simula when a successful plan still matches support rules.
    var canSimulate: Bool {
        planReady && externalMatches && externalSupported
    }

    /// Esegui also waits for this refresh's plan GET (live external list).
    var canExecute: Bool { canSimulate && !planExternalPending }

    var executeDialogMessage: String {
        if executeConfirmsComputer {
            return "I fatti del contesto cambiano. Sul computer: \(externalSummary)."
        }
        if planReady && !externalSupported {
            return "I fatti del contesto non sostengono più l'azione sul computer. Pianifica di nuovo."
        }
        if executeWithholdsComputer {
            return "I fatti del contesto cambiano. L'azione sul computer non parte: le precondizioni non ci sono più. \(externalWithheldSummary)."
        }
        if !externalMatches {
            return "I fatti del contesto cambiano. L'azione sul computer non è più quella del piano."
        }
        return "I fatti del contesto cambiano. Non tocca il computer."
    }

    var autonomyDialogMessage: String {
        if authority == "execute" {
            return "Un passo autonomo osserva, pianifica e può eseguire. Sul computer solo se il piano nuovo lo richiede, e solo dopo questa conferma."
        }
        if authority == "read" {
            return "Un passo autonomo riconosce gli eventi in attesa, poi si ferma: non pianifica, non simula e non esegue."
        }
        return "Un passo autonomo osserva, pianifica e simula. I fatti del contesto restano fermi."
    }

    var autonomyLoopDialogMessage: String {
        if authority == "execute" {
            return "Fino a \(autonomyMaxSteps) passi. Ognuno osserva, pianifica e può eseguire. Sul computer solo se un piano lo richiede, e solo dopo questa conferma. Il ciclo si ferma a obiettivo raggiunto o a un rifiuto."
        }
        if authority == "read" {
            return "Fino a \(autonomyMaxSteps) passi. Ognuno può riconoscere gli eventi in attesa, poi si ferma sull'autorità di lettura: non pianifica, non simula e non esegue."
        }
        return "Fino a \(autonomyMaxSteps) passi di osservazione, piano e simulazione. I fatti del contesto restano fermi. Il ciclo si ferma a obiettivo raggiunto o a un rifiuto."
    }

    /// Session autonomy authority for Passo/Ciclo — preserve :read from the API.
    var autonomyAuthority: String {
        switch authority {
        case "execute": return "execute"
        case "read": return "read"
        default: return "simulate"
        }
    }

    init() {
        if let env = ProcessInfo.processInfo.environment["AUTOMA_GP_URL"], !env.isEmpty {
            baseURL = env
        }
    }

    private var timer: Timer?

    func start() {
        timer?.invalidate()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        Task {
            do {
                let wasConnected = connected
                let wasListening = listening
                let status = try await get("/api/status")
                let version = string(status["version"]) ?? "?"
                repairDepth = int(status["repair-depth"])
                listening = (status["listening"] as? Bool) ?? false
                watchingDirectory = status["directory-watch"] is String
                watchingProcesses = (status["process-watch"] as? Bool) ?? false
                watchingTerminals = (status["terminal-watch"] as? Bool) ?? false
                watchingTerminalText = (status["terminal-text-watch"] as? Bool) ?? false
                watchingTerminalScreen = (status["terminal-screen-watch"] as? Bool) ?? false
                openGoals = int(status["open-goals"])
                if openGoals == 0, status["open-goals"] == nil {
                    openGoals = int(status["goals"])
                }
                pendingEvents = int(status["pending-events"])
                hasPlan = (status["plan-p"] as? Bool) ?? false
                planSuccess = (status["plan-success"] as? Bool) ?? false
                // Apply external gates from status before the plan GET so
                // Simula/Esegui stay idle while later requests are in flight.
                externalMatches = (status["external-matches"] as? Bool) ?? true
                externalSupported = (status["external-supported"] as? Bool) ?? true
                // Drop prior plan's external lists until this refresh's plan GET
                // returns, so Esegui cannot confirm adapters from a stale plan.
                externalActions = []
                externalWithheld = []
                planExternalPending = true
                let gateSnap = "\(int(status["facts"]))|\(openGoals)|\(planSuccess)|\(externalMatches)|\(externalSupported)"
                if gateSnap != archiveGateSnapshot {
                    archiveProbePending = true
                }
                let missing = factLines(from: status["listening-missing"])
                missingLabel = missing.map(\.label).joined(separator: " · ")
                if listening && !wasListening && actionName.trimmingCharacters(in: .whitespaces).isEmpty,
                   let predicate = missing.first?.parts.first {
                    actionName = predicate.lowercased()
                }
                let planBody = try await get("/api/plan")
                if let plan = planBody["plan"] as? [String: Any] {
                    externalActions = externalActions(from: plan, key: "external")
                    externalWithheld = externalActions(from: plan, key: "external-withheld")
                    externalMatches = (plan["external-matches"] as? Bool) ?? externalMatches
                    externalSupported = (plan["external-supported"] as? Bool) ?? externalSupported
                    if status["plan-success"] == nil {
                        planSuccess = (plan["success"] as? Bool) ?? false
                    }
                } else {
                    externalActions = []
                    externalWithheld = []
                    externalMatches = true
                    externalSupported = true
                    hasPlan = false
                    planSuccess = false
                }
                planExternalPending = false
                let explain = try await get("/api/explain")
                narration = string(explain["narration"]) ?? ""
                nodes = nodes(from: explain["graph"])
                let archive = try await get("/api/archive?applies=1")
                cards = cards(from: archive["procedures"])
                archiveGateSnapshot = gateSnap
                archiveProbePending = false
                let factsBody = try await get("/api/facts")
                factLines = factLines(from: factsBody["facts"])
                let operators = try await get("/api/operators")
                let reactions = try await get("/api/reactions")
                let rules = try await get("/api/rules")
                let nextAliases = aliasTargets(
                    operators: operators["operators"],
                    reactions: reactions["reactions"],
                    rules: rules["rules"])
                if !nextAliases.contains(where: { $0.id == aliasTarget }) {
                    aliasTarget = nextAliases.first?.id ?? ""
                }
                aliases = nextAliases
                let autonomy = try await get("/api/autonomy")
                if let policy = autonomy["policy"] as? [String: Any] {
                    authority = (string(policy["authority"]) ?? "simulate")
                        .replacingOccurrences(of: ":", with: "")
                        .lowercased()
                    if let steps = policy["max-steps"] as? Int {
                        autonomyMaxSteps = max(1, steps)
                    } else if let steps = policy["max-steps"] as? Double {
                        autonomyMaxSteps = max(1, Int(steps))
                    }
                }
                applyAutonomyLast(autonomy["last"])
                connected = true
                statusLine = "v\(version)"
                if !wasConnected {
                    notice = ""
                    noticeIsError = false
                }
            } catch {
                connected = false
                externalActions = []
                externalWithheld = []
                externalMatches = true
                externalSupported = true
                planExternalPending = false
                openGoals = 0
                pendingEvents = 0
                hasPlan = false
                planSuccess = false
                archiveProbePending = false
                archiveGateSnapshot = ""
                autonomyLastLine = ""
                autonomyLastIsError = false
                statusLine = "Server non raggiungibile su \(baseURL)"
                report(error.localizedDescription, error: true)
            }
        }
    }

    func setAuthority(_ value: String) {
        authority = value
        guard connected else { return }
        Task {
            _ = try? await post("/api/autonomy/policy", ["authority": value])
            refresh()
        }
    }

    func setMaxSteps(_ value: Int) {
        let steps = min(32, max(1, value))
        autonomyMaxSteps = steps
        guard connected else { return }
        Task {
            _ = try? await post("/api/autonomy/policy", ["max-steps": steps])
            refresh()
        }
    }

    func autonomyStep() {
        guard connected, autonomyHasWork else { return }
        Task {
            await postAutonomy(path: "/api/autonomy/step", loop: false)
        }
    }

    func autonomyLoop() {
        guard connected, autonomyHasWork else { return }
        Task {
            await postAutonomy(path: "/api/autonomy/loop", loop: true)
        }
    }

    private func postAutonomy(path: String, loop: Bool) async {
        let auth = autonomyAuthority
        let touchesComputer = auth == "execute"
        do {
            var payload: [String: Any] = ["authority": auth]
            if loop {
                payload["max-steps"] = autonomyMaxSteps
            }
            if touchesComputer {
                payload["adapters"] = true
                payload["auto-confirm"] = true
            }
            let body = try await post(path, payload)
            if let error = string(body["error"]), body["ok"] as? Bool == false {
                report(error, error: true)
            } else {
                applyAutonomyLast(body["autonomy"])
                let (text, isError) = autonomyOutcome(from: body["autonomy"])
                report(text, error: isError)
            }
            refresh()
        } catch {
            report(error.localizedDescription, error: true)
        }
    }

    func planOpenGoals() {
        guard connected, openGoals > 0 else { return }
        Task {
            await run("/api/plan-open-goals", [:],
                      success: "Piano aggiornato. Non è stato eseguito.")
        }
    }

    func simulate() {
        guard connected, canSimulate else { return }
        Task {
            await run("/api/simulate", [:], success: "Simulazione conclusa. I fatti non sono cambiati.")
        }
    }

    func execute() {
        guard connected, canExecute else { return }
        let touchesComputer = executeConfirmsComputer
        Task {
            do {
                let body = try await post("/api/run",
                                          ["confirm": true, "adapters": touchesComputer])
                if let error = string(body["error"]), body["ok"] as? Bool == false {
                    report(error, error: true)
                } else if !executionSucceeded(body) {
                    report("Esecuzione interrotta. Gli obiettivi del piano non sono stati raggiunti.",
                           error: true)
                } else if executionWithheld(body) {
                    report("Esecuzione conclusa. I fatti sono aggiornati. Un'azione sul computer non è partita: le sue precondizioni non ci sono più.",
                           error: false)
                } else if touchesComputer {
                    report("Esecuzione conclusa. I fatti sono aggiornati e l'azione sul computer è partita.",
                           error: false)
                } else {
                    report("Esecuzione conclusa. I fatti del contesto sono aggiornati.",
                           error: false)
                }
                refresh()
            } catch {
                report(error.localizedDescription, error: true)
            }
        }
    }

    func use(name: String) {
        guard connected, !archiveProbePending,
              cards.contains(where: { $0.name == name && $0.applies }) else { return }
        Task {
            await run("/api/archive/use", ["name": name], success: "Piano ricostruito da \(name).")
        }
    }

    func noteState() {
        guard connected, listening else { return }
        Task {
            await run("/api/induce/note", [:], success: "Stato annotato. Modifica i fatti, poi induci la regola.")
        }
    }

    func addFact() {
        guard connected else { return }
        let parts = factDraft.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return }
        factDraft = ""
        Task {
            await run("/api/add-fact", ["fact": parts], success: "Fatto aggiunto.")
        }
    }

    func ask() {
        guard connected else { return }
        let phrase = phraseDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        Task {
            do {
                let body = try await post("/api/ask", ["phrase": phrase])
                if let error = string(body["error"]), body["ok"] as? Bool == false {
                    choices = goalChoices(from: body)
                    report(error, error: true)
                } else {
                    choices = []
                    phraseDraft = ""
                    report("Obiettivo registrato. Il piano è aggiornato.", error: false)
                }
                refresh()
            } catch {
                report(error.localizedDescription, error: true)
            }
        }
    }

    func choose(_ choice: GoalChoice) {
        guard connected else { return }
        let goal = choice.goal
        Task {
            do {
                if choice.declaresWord {
                    let named = try await post("/api/operator/name", [
                        "name": choice.name,
                        "word": choice.word,
                        "kind": choice.kind
                    ])
                    if let error = string(named["error"]), named["ok"] as? Bool == false {
                        report(error, error: true)
                        return
                    }
                }
                let planned = try await post("/api/plan", ["goals": [goal.parts]])
                if let error = string(planned["error"]), planned["ok"] as? Bool == false {
                    report(error, error: true)
                    refresh()
                    return
                }
                let added = try await post("/api/add-goal", ["goal": goal.parts])
                if let error = string(added["error"]), added["ok"] as? Bool == false {
                    report(error, error: true)
                } else {
                    choices = []
                    phraseDraft = ""
                    report("Obiettivo registrato. Il piano è aggiornato.", error: false)
                }
                refresh()
            } catch {
                report(error.localizedDescription, error: true)
            }
        }
    }

    func watchDirectory() {
        guard connected else { return }
        if watchingDirectory {
            Task {
                await run("/api/watch-directory/stop", [:],
                          success: "Osservazione ferma.")
            }
            return
        }
        let path = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        pathDraft = ""
        Task {
            await run("/api/watch-directory", ["path": path, "interval": 1],
                      success: "Cartella sotto osservazione. Il piano non parte.")
        }
    }

    func noticeProcesses() {
        guard connected else { return }
        Task {
            await run("/api/notice-processes", [:],
                      success: "Processi notati. Il piano non parte.")
        }
    }

    func noticeTerminals() {
        guard connected else { return }
        Task {
            await run("/api/notice-terminals", [:],
                      success: "Terminale notato. Il piano non parte.")
        }
    }

    func noticeTerminalText() {
        guard connected else { return }
        Task {
            await run("/api/notice-terminal-text", [:],
                      success: "Testo notato. Il piano non parte.")
        }
    }

    func noticeTerminalScreen() {
        guard connected else { return }
        Task {
            await run("/api/notice-terminal-screen", [:],
                      success: "Schermo notato. Il piano non parte.")
        }
    }

    func watchTerminalScreen() {
        guard connected else { return }
        if watchingTerminalScreen {
            Task {
                await run("/api/watch-terminal-screen/stop", [:],
                          success: "Osservazione dello schermo ferma.")
            }
            return
        }
        Task {
            await run("/api/watch-terminal-screen", ["interval": 1],
                      success: "Schermo sotto osservazione. Il piano non parte.")
        }
    }

    func watchTerminalText() {
        guard connected else { return }
        if watchingTerminalText {
            Task {
                await run("/api/watch-terminal-text/stop", [:],
                          success: "Osservazione del testo ferma.")
            }
            return
        }
        Task {
            await run("/api/watch-terminal-text", ["interval": 1],
                      success: "Testo sotto osservazione. Il piano non parte.")
        }
    }

    func watchTerminals() {
        guard connected else { return }
        if watchingTerminals {
            Task {
                await run("/api/watch-terminals/stop", [:],
                          success: "Osservazione del terminale ferma.")
            }
            return
        }
        Task {
            await run("/api/watch-terminals", ["interval": 1],
                      success: "Terminale sotto osservazione. Il piano non parte.")
        }
    }

    func watchProcesses() {
        guard connected else { return }
        if watchingProcesses {
            Task {
                await run("/api/watch-processes/stop", [:],
                          success: "Osservazione dei processi ferma.")
            }
            return
        }
        Task {
            await run("/api/watch-processes", ["interval": 1],
                      success: "Processi sotto osservazione. Il piano non parte.")
        }
    }

    func noticeDirectory() {
        guard connected else { return }
        let path = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        pathDraft = ""
        Task {
            await run("/api/notice-directory", ["path": path],
                      success: "Cartella notata. I file descritti entrano nel contesto. Il piano non parte.")
        }
    }

    func noticePath() {
        guard connected else { return }
        let path = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        pathDraft = ""
        Task {
            await run("/api/notice-path", ["path": path],
                      success: "File notato. Il fatto entra nel contesto.")
        }
    }

    func removeFact(_ fact: FactLine) {
        guard connected else { return }
        Task {
            await run("/api/remove-fact", ["fact": fact.parts], success: "Fatto tolto.")
        }
    }

    func learnRule() {
        guard connected, listening else { return }
        let name = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            report("Scrivi il nome della regola da indurre.", error: true)
            return
        }
        Task {
            do {
                let body = try await post("/api/induce/rule", ["name": name])
                if let op = body["operator"] as? [String: Any] {
                    learned = InducedOperator(
                        name: string(op["name"]) ?? name,
                        preconditions: pretty(op["preconditions"]),
                        adds: pretty(op["add-list"]),
                        deletes: pretty(op["delete-list"]),
                        examples: exampleCount(op)
                    )
                    let n = exampleCount(op)
                    report(n > 1
                           ? "Altro esempio unito alla regola. \(n) esempi."
                           : "Regola generalizzata registrata.",
                           error: false)
                } else {
                    report(string(body["error"]) ?? "Induzione non riuscita.", error: true)
                }
                refresh()
            } catch {
                report(error.localizedDescription, error: true)
            }
        }
    }

    func nameOperator() {
        guard connected, let learned else { return }
        let word = wordDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        Task {
            do {
                let body = try await post("/api/operator/name", [
                    "name": learned.name,
                    "word": word,
                    "kind": "operator"
                ])
                if let error = string(body["error"]), body["ok"] as? Bool == false {
                    report(error, error: true)
                } else {
                    wordDraft = ""
                    report("Ora risponde a \(word).", error: false)
                }
                refresh()
            } catch {
                report(error.localizedDescription, error: true)
            }
        }
    }

    func nameAlias() {
        guard connected else { return }
        let word = aliasDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty,
              let target = aliases.first(where: { $0.id == aliasTarget }) ?? aliases.first
        else { return }
        Task {
            do {
                let body = try await post("/api/operator/name", [
                    "name": target.name,
                    "word": word,
                    "kind": target.kind
                ])
                if let error = string(body["error"]), body["ok"] as? Bool == false {
                    report(error, error: true)
                } else {
                    aliasDraft = ""
                    report("Ora \(target.label) risponde a \(word).", error: false)
                }
                refresh()
            } catch {
                report(error.localizedDescription, error: true)
            }
        }
    }

    func learn() {
        guard connected, listening else { return }
        let name = actionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            report("Scrivi il nome dell'azione da imparare.", error: true)
            return
        }
        Task {
            do {
                let body = try await post("/api/induce", ["name": name])
                if let op = body["operator"] as? [String: Any] {
                    let n = exampleCount(op)
                    learned = InducedOperator(
                        name: string(op["name"]) ?? name,
                        preconditions: pretty(op["preconditions"]),
                        adds: pretty(op["add-list"]),
                        deletes: pretty(op["delete-list"]),
                        examples: n
                    )
                    report(n > 1
                           ? "Altro esempio unito. \(n) esempi."
                           : "Operatore registrato.",
                           error: false)
                } else {
                    report(string(body["error"]) ?? "Induzione non riuscita.", error: true)
                }
                refresh()
            } catch {
                report(error.localizedDescription, error: true)
            }
        }
    }

    private func applyAutonomyLast(_ value: Any?) {
        if value == nil || value is NSNull {
            autonomyLastLine = ""
            autonomyLastIsError = false
            return
        }
        let (text, isError) = autonomyOutcome(from: value)
        if text.isEmpty {
            autonomyLastLine = ""
            autonomyLastIsError = false
        } else {
            autonomyLastLine = text
            autonomyLastIsError = isError
        }
    }

    private func autonomyOutcome(from value: Any?) -> (String, Bool) {
        guard let autonomy = value as? [String: Any],
              string(autonomy["status"]) != nil else {
            return ("", false)
        }
        let status = (string(autonomy["status"]) ?? "")
            .replacingOccurrences(of: ":", with: "")
            .lowercased()
        let halt = (string(autonomy["halt"]) ?? "")
            .replacingOccurrences(of: ":", with: "")
            .lowercased()
        let iterations: Int? = {
            if let n = autonomy["iterations"] as? Int { return n }
            if let n = autonomy["iterations"] as? Double { return Int(n) }
            return nil
        }()
        let loop = iterations != nil
        let label = loop ? "Ciclo autonomo" : "Passo autonomo"
        let count: String = {
            guard let n = iterations else { return "" }
            return n == 1 ? " (1 passo)" : " (\(n) passi)"
        }()
        switch (status, halt) {
        case ("done", _):
            return ("\(label) concluso\(count).", false)
        case ("continue", _):
            return ("\(label): resta da ripianificare\(count).", false)
        case ("halted", "no-goals"):
            return ("\(label) fermo\(count): non c'è un obiettivo.", true)
        case ("halted", "goals-already-satisfied"):
            return ("\(label): gli obiettivi sono già soddisfatti\(count).", false)
        case ("halted", "authority-read"):
            return ("\(label) fermo\(count): l'autorità è solo lettura.", true)
        case ("halted", "plan-failed"):
            return ("\(label) fermo\(count): il piano non è riuscito.", true)
        case ("halted", "external-mismatch"):
            return ("\(label) fermo\(count): l'azione sul computer non è più quella del piano.", true)
        case ("halted", "external-unsupported"):
            return ("\(label) fermo\(count): i fatti non sostengono più l'azione sul computer.", true)
        case ("halted", "confirmation-required"):
            return ("\(label) fermo\(count): serve una conferma.", true)
        case ("halted", "confirmation-denied"):
            return ("\(label) fermo\(count): conferma rifiutata.", true)
        case ("halted", "execution-failed"):
            return ("\(label) fermo\(count): l'esecuzione non è riuscita.", true)
        case ("halted", "discrepancy"):
            return ("\(label) fermo\(count): resta una differenza.", true)
        case ("halted", "max-steps"):
            return ("\(label) fermo\(count): raggiunto il limite di passi.", true)
        case ("halted", let reason) where !reason.isEmpty:
            return ("\(label) fermo\(count) (\(reason)).", true)
        case ("halted", _):
            return ("\(label) fermo\(count).", true)
        default:
            return ("\(label) concluso\(count).", false)
        }
    }

    private func run(_ path: String, _ payload: [String: Any], success: String? = nil) async {
        do {
            let body = try await post(path, payload)
            if let error = string(body["error"]), body["ok"] as? Bool == false {
                report(error, error: true)
            } else if let success {
                report(success, error: false)
            }
            refresh()
        } catch {
            report(error.localizedDescription, error: true)
        }
    }

    private func report(_ text: String, error: Bool) {
        notice = text
        noticeIsError = error
    }

    private func get(_ path: String) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        let (data, response) = try await URLSession.shared.data(from: url)
        try check(response)
        return try decode(data)
    }

    private func post(_ path: String, _ payload: [String: Any]) async throws -> [String: Any] {
        let url = URL(string: baseURL + path)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400,
           let body = try? decode(data), body["error"] == nil {
            throw URLError(.badServerResponse)
        }
        return try decode(data)
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode >= 400 {
            throw URLError(.badServerResponse)
        }
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: data)
        return object as? [String: Any] ?? [:]
    }

    private func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            return text
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private func exampleCount(_ op: [String: Any]) -> Int {
        guard let meta = op["meta"] as? [String: Any] else { return 1 }
        let n = int(meta["examples"])
        return n == 0 ? 1 : n
    }

    private func executionSucceeded(_ body: [String: Any]) -> Bool {
        guard let execution = body["execution"] as? [String: Any] else { return true }
        return (execution["success"] as? Bool) ?? true
    }

    private func executionWithheld(_ body: [String: Any]) -> Bool {
        guard let execution = body["execution"] as? [String: Any],
              let steps = execution["steps"] as? [Any] else { return false }
        return steps.contains { step in
            guard let item = step as? [String: Any] else { return false }
            return string(item["external"]) == ":WITHHELD"
        }
    }

    private func externalActions(from plan: [String: Any], key: String) -> [ExternalAction] {
        guard let rows = plan[key] as? [Any] else { return [] }
        return rows.enumerated().compactMap { index, row in
            guard let item = row as? [String: Any] else { return nil }
            let name = string(item["operator"]) ?? ""
            let adapter = plainSymbol(string(item["adapter"]))
            let op = plainSymbol(string(item["op"]))
            let args = argsLabel(item["args"])
            let action = args.isEmpty ? "\(adapter) \(op)" : "\(adapter) \(op) · \(args)"
            let label = name.isEmpty ? action : "\(name) · \(action)"
            return ExternalAction(id: index, label: label)
        }
    }

    private func plainSymbol(_ value: String?) -> String {
        guard let text = value else { return "" }
        guard text.hasPrefix(":") else { return text }
        return String(text.dropFirst()).lowercased()
    }

    private func argsLabel(_ value: Any?) -> String {
        guard let args = value as? [String: Any], !args.isEmpty else { return "" }
        return args.keys.sorted().map { key in
            "\(key) \(argumentText(args[key]))"
        }.joined(separator: " · ")
    }

    private func argumentText(_ value: Any?) -> String {
        switch value {
        case let text as String:
            return plainSymbol(text)
        case let items as [Any]:
            return items.map { argumentText($0) }.joined(separator: " ")
        case let number as NSNumber:
            return number.stringValue
        default:
            return ""
        }
    }

    private func int(_ value: Any?) -> Int {
        switch value {
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text) ?? 0
        default:
            return 0
        }
    }

    private func goalChoices(from body: [String: Any]) -> [GoalChoice] {
        if let rows = body["choices"] as? [Any], !rows.isEmpty {
            let word = string(body["word"]) ?? ""
            return rows.compactMap { row in
                guard let item = row as? [String: Any],
                      let goal = factLines(from: [item["goal"] as Any]).first
                else { return nil }
                return GoalChoice(
                    kind: string(item["kind"]) ?? "",
                    name: string(item["name"]) ?? "",
                    word: word,
                    goal: goal)
            }
        }
        return factLines(from: body["goals"]).map {
            GoalChoice(kind: "", name: "", word: "", goal: $0)
        }
    }

    private func aliasTargets(operators: Any?, reactions: Any?, rules: Any?) -> [AliasTarget] {
        let learnedName = learned?.name
        let operatorsInContext = namedAliases("operator", operators).filter { target in
            guard let learnedName else { return true }
            return target.name.caseInsensitiveCompare(learnedName) != .orderedSame
        }
        return operatorsInContext
            + namedAliases("reaction", reactions)
            + namedAliases("rule", rules)
    }

    private func namedAliases(_ kind: String, _ value: Any?) -> [AliasTarget] {
        guard let rows = value as? [Any] else { return [] }
        return rows.compactMap { row in
            guard let item = row as? [String: Any],
                  let name = string(item["name"]), !name.isEmpty else { return nil }
            let words = (item["ask"] as? [Any])?.compactMap { string($0) } ?? []
            return AliasTarget(kind: kind, name: name, words: words)
        }
    }

    private func factLines(from value: Any?) -> [FactLine] {
        guard let rows = value as? [Any] else { return [] }
        return rows.compactMap { row in
            let parts: [String]
            if let items = row as? [Any] {
                parts = items.compactMap { string($0) }
            } else if let text = string(row) {
                parts = [text]
            } else {
                return nil
            }
            return parts.isEmpty ? nil : FactLine(parts: parts)
        }
    }

    private func nodes(from value: Any?) -> [TraceNode] {
        guard let rows = value as? [Any] else { return [] }
        return rows.enumerated().compactMap { index, row in
            guard let item = row as? [String: Any] else { return nil }
            let tone = (string(item["tone"]) ?? "note")
                .replacingOccurrences(of: ":", with: "")
                .lowercased()
            return TraceNode(id: index, text: string(item["text"]) ?? "", tone: tone)
        }
    }

    private func cards(from value: Any?) -> [ArchiveCard] {
        guard let rows = value as? [Any] else { return [] }
        return rows.compactMap { row in
            guard let item = row as? [String: Any] else { return nil }
            let ops = (item["operators-used"] as? [Any])?.map { pretty($0) } ?? []
            return ArchiveCard(
                name: string(item["name"]) ?? "?",
                score: (item["score"] as? NSNumber)?.doubleValue ?? 0,
                successes: int(item["success-count"]),
                failures: int(item["failure-count"]),
                steps: int(item["step-count"]),
                operators: ops.joined(separator: " · "),
                applies: (item["applies"] as? Bool) ?? false
            )
        }
    }

    private func pretty(_ value: Any?) -> String {
        guard let value else { return "" }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return String(describing: value)
    }
}
