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

/// A way the server's answer can be unusable that URLSession does not report:
/// an HTTP error status without the façade's envelope, or a body that is not
/// a JSON object. The text is what the notice shows, so it names the status
/// and keeps the server's own reason.
enum APIError: LocalizedError {
    case invalidURL(String)
    case bodyTooLarge
    case status(Int, String?)
    case notJSONObject(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let text):
            return "L'indirizzo del server non è valido: \(text)"
        case .bodyTooLarge:
            return "La richiesta supera il limite di \(WorkbenchModel.maxRequestBodyOctets) byte del server."
        case .status(let code, let message):
            return message.map { "HTTP \(code): \($0)" } ?? "Il server ha risposto HTTP \(code)."
        case .notJSONObject(let code):
            return "Il server ha risposto HTTP \(code) con un corpo che non è un oggetto JSON."
        }
    }
}

@MainActor
final class WorkbenchModel: ObservableObject {
    /// Where the Lisp server listens (interface/web.lisp, *default-web-port*)
    /// unless the environment names another address.
    nonisolated static let defaultBaseURL = "http://127.0.0.1:47391"
    nonisolated static let baseURLVariable = "AUTOMA_GP_URL"
    /// Seconds between two automatic refreshes.
    nonisolated static let pollInterval: TimeInterval = 2
    /// Seconds a read may wait for the server before it counts as unreachable.
    nonisolated static let readTimeout: TimeInterval = 10
    /// Seconds an action may wait: a run with adapters or an autonomous loop
    /// answers only when it ends.
    nonisolated static let actionTimeout: TimeInterval = 300
    /// The longest request body the server reads
    /// (interface/web.lisp, *max-request-body-octets*).
    nonisolated static let maxRequestBodyOctets = 1024 * 1024
    /// The loop limits the workbench offers for Ciclo.
    nonisolated static let maxStepsRange = 1...32
    /// Seconds between two looks of a watch the workbench starts.
    nonisolated static let watchInterval = 1

    @Published var baseURL = WorkbenchModel.defaultBaseURL
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
        let configured = Self.normalizedBaseURL(
            ProcessInfo.processInfo.environment[Self.baseURLVariable] ?? "")
        if !configured.isEmpty {
            baseURL = configured
        }
    }

    /// The address without surrounding blanks or a trailing slash. The server
    /// prints its address with that slash, and a path joined to it would start
    /// with two, which the server answers 404.
    nonisolated static func normalizedBaseURL(_ text: String) -> String {
        var address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while address.hasSuffix("/") {
            address.removeLast()
        }
        return address
    }

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var refreshAgain = false
    /// Counts the stops, so a refresh that was given up cannot end the one a
    /// later start began.
    private var refreshEpoch = 0
    /// The archive fault the last poll reported, so a standing fault is shown
    /// once and not again every poll.
    private var reportedArchiveFault: String?

    func start() {
        timer?.invalidate()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] timer in
            // The model goes with its window, and a timer outlives it.
            guard let self else {
                timer.invalidate()
                return
            }
            Task { @MainActor in self.poll() }
        }
    }

    /// Ends the polling and gives up the refresh in flight. The window calls
    /// it when it goes away; `start` begins again.
    func stop() {
        timer?.invalidate()
        timer = nil
        refreshEpoch += 1
        refreshTask?.cancel()
        refreshTask = nil
        refreshAgain = false
    }

    /// A tick of the timer: refreshes unless a refresh is already running, so
    /// a slow server is not asked again before it has answered.
    private func poll() {
        if refreshTask == nil {
            refresh()
        }
    }

    /// Refreshes now. One refresh runs at a time: overlapping ones let an old
    /// answer land after a newer one, and let one clear the external actions
    /// while another has already ended the wait for them. A call made while a
    /// refresh runs, such as the one an action makes after it changed the
    /// session, asks for another when this one ends, because what this one
    /// read may be older than the change.
    func refresh() {
        guard refreshTask == nil else {
            refreshAgain = true
            return
        }
        let epoch = refreshEpoch
        refreshTask = Task { [weak self] in
            await self?.refreshWhileWanted(epoch)
        }
    }

    private func refreshWhileWanted(_ epoch: Int) async {
        repeat {
            refreshAgain = false
            await refreshOnce()
        } while refreshAgain && epoch == refreshEpoch
        if epoch == refreshEpoch {
            refreshTask = nil
        }
    }

    private func refreshOnce() async {
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
                // Any client may set a limit the stepper does not offer, or
                // one that is not an Int at all (the server rounds a
                // bignum), and Int(Double) traps on a value out of range.
                if let steps = integer(policy["max-steps"]) {
                    autonomyMaxSteps = clampedSteps(steps)
                }
            }
            applyAutonomyLast(autonomy["last"])
            connected = true
            statusLine = "v\(version)"
            if !wasConnected {
                notice = ""
                noticeIsError = false
            }
            // After the notice of a reconnection is cleared, so it is not lost.
            noteArchiveFault(archive)
        } catch {
            // Given up by `stop`: nobody is waiting for the answer.
            if Task.isCancelled { return }
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
            reportedArchiveFault = nil
            autonomyLastLine = ""
            autonomyLastIsError = false
            // A server that answered is reachable: say what it answered.
            statusLine = error is URLError
                ? "Server non raggiungibile su \(baseURL)"
                : error.localizedDescription
            report(error.localizedDescription, error: true)
        }
    }

    /// Reports an archive fault when a poll first sees it, and again only if
    /// it changes or comes back. A fault that stands is not repeated every
    /// two seconds over the notice of whatever the user just did.
    private func noteArchiveFault(_ body: [String: Any]) {
        let fault = archiveFault(body)
        guard fault != reportedArchiveFault else { return }
        reportedArchiveFault = fault
        if let fault {
            report("Archivio: \(fault)", error: true)
        }
    }

    func setAuthority(_ value: String) {
        authority = value
        guard connected else { return }
        Task {
            await run("/api/autonomy/policy", ["authority": value])
        }
    }

    private func clampedSteps(_ value: Int) -> Int {
        min(Self.maxStepsRange.upperBound, max(Self.maxStepsRange.lowerBound, value))
    }

    func setMaxSteps(_ value: Int) {
        let steps = clampedSteps(value)
        autonomyMaxSteps = steps
        guard connected else { return }
        Task {
            await run("/api/autonomy/policy", ["max-steps": steps])
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
            if let error = refusal(body) {
                report(error, error: true, answer: body)
            } else {
                applyAutonomyLast(body["autonomy"])
                let (text, isError) = autonomyOutcome(from: body["autonomy"])
                report(text, error: isError, answer: body)
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
                if let error = refusal(body) {
                    report(error, error: true, answer: body)
                } else if !executionSucceeded(body) {
                    report("Esecuzione interrotta. Gli obiettivi del piano non sono stati raggiunti.",
                           error: true, answer: body)
                } else if executionWithheld(body) {
                    report("Esecuzione conclusa. I fatti sono aggiornati. Un'azione sul computer non è partita: le sue precondizioni non ci sono più.",
                           error: false, answer: body)
                } else if touchesComputer {
                    report("Esecuzione conclusa. I fatti sono aggiornati e l'azione sul computer è partita.",
                           error: false, answer: body)
                } else {
                    report("Esecuzione conclusa. I fatti del contesto sono aggiornati.",
                           error: false, answer: body)
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
                if let error = refusal(body) {
                    choices = goalChoices(from: body)
                    report(error, error: true, answer: body)
                } else {
                    choices = []
                    phraseDraft = ""
                    report("Obiettivo registrato. Il piano è aggiornato.", error: false, answer: body)
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
                    if let error = refusal(named) {
                        report(error, error: true, answer: named)
                        return
                    }
                }
                let planned = try await post("/api/plan", ["goals": [goal.parts]])
                if let error = refusal(planned) {
                    report(error, error: true, answer: planned)
                    refresh()
                    return
                }
                let added = try await post("/api/add-goal", ["goal": goal.parts])
                if let error = refusal(added) {
                    report(error, error: true, answer: added)
                } else {
                    choices = []
                    phraseDraft = ""
                    report("Obiettivo registrato. Il piano è aggiornato.", error: false, answer: added)
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
            await run("/api/watch-directory", ["path": path, "interval": Self.watchInterval],
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

    /// Starts the watch that ROUTE names, or stops it when it is running.
    private func toggleWatch(_ route: String, running: Bool, started: String, stopped: String) {
        guard connected else { return }
        Task {
            if running {
                await run("\(route)/stop", [:], success: stopped)
            } else {
                await run(route, ["interval": Self.watchInterval], success: started)
            }
        }
    }

    func watchTerminalScreen() {
        toggleWatch("/api/watch-terminal-screen", running: watchingTerminalScreen,
                    started: "Schermo sotto osservazione. Il piano non parte.",
                    stopped: "Osservazione dello schermo ferma.")
    }

    func watchTerminalText() {
        toggleWatch("/api/watch-terminal-text", running: watchingTerminalText,
                    started: "Testo sotto osservazione. Il piano non parte.",
                    stopped: "Osservazione del testo ferma.")
    }

    func watchTerminals() {
        toggleWatch("/api/watch-terminals", running: watchingTerminals,
                    started: "Terminale sotto osservazione. Il piano non parte.",
                    stopped: "Osservazione del terminale ferma.")
    }

    func watchProcesses() {
        toggleWatch("/api/watch-processes", running: watchingProcesses,
                    started: "Processi sotto osservazione. Il piano non parte.",
                    stopped: "Osservazione dei processi ferma.")
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
            await induce("/api/induce/rule", name: name,
                         merged: { "Altro esempio unito alla regola. \($0) esempi." },
                         registered: "Regola generalizzata registrata.")
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
                if let error = refusal(body) {
                    report(error, error: true, answer: body)
                } else {
                    wordDraft = ""
                    report("Ora risponde a \(word).", error: false, answer: body)
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
                if let error = refusal(body) {
                    report(error, error: true, answer: body)
                } else {
                    aliasDraft = ""
                    report("Ora \(target.label) risponde a \(word).", error: false, answer: body)
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
            await induce("/api/induce", name: name,
                         merged: { "Altro esempio unito. \($0) esempi." },
                         registered: "Operatore registrato.")
        }
    }

    /// Asks the server to induce the operator NAME from the observed change.
    /// MERGED says what happened when the example joined an operator that
    /// already had one or more, given the number of examples it now has.
    private func induce(_ path: String, name: String,
                        merged: (Int) -> String, registered: String) async {
        do {
            let body = try await post(path, ["name": name])
            if let op = body["operator"] as? [String: Any] {
                let n = exampleCount(op)
                learned = InducedOperator(
                    name: string(op["name"]) ?? name,
                    preconditions: pretty(op["preconditions"]),
                    adds: pretty(op["add-list"]),
                    deletes: pretty(op["delete-list"]),
                    examples: n
                )
                report(n > 1 ? merged(n) : registered, error: false, answer: body)
            } else {
                report(string(body["error"]) ?? "Induzione non riuscita.", error: true, answer: body)
            }
            refresh()
        } catch {
            report(error.localizedDescription, error: true)
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
        // Only a loop has :iterations. A step writes it as false, which `as? Int`
        // would read as 0 and so label every step "Ciclo autonomo (0 passi)".
        let iterations = integer(autonomy["iterations"])
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
            if let error = refusal(body) {
                report(error, error: true, answer: body)
            } else if let success {
                report(success, error: false, answer: body)
            } else if let fault = archiveFault(body) {
                report("Archivio: \(fault)", error: true)
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

    /// Why the server refused a request, or nil when it accepted it. Every
    /// refusal of a gate is {"ok": false, "error": text}.
    private func refusal(_ body: [String: Any]) -> String? {
        guard body["ok"] as? Bool == false else { return nil }
        return string(body["error"])
    }

    /// What the server says about the procedure archive file when it could not
    /// be read or written. The request itself went on without the file.
    private func archiveFault(_ body: [String: Any]) -> String? {
        guard let text = body["archive-error"] as? String, !text.isEmpty else { return nil }
        return text
    }

    /// Reports TEXT as the outcome of the request that BODY answered, with the
    /// archive fault the answer carries: a run that happened but could not be
    /// remembered is not reported as a clean one.
    private func report(_ text: String, error: Bool, answer body: [String: Any]) {
        if let fault = archiveFault(body) {
            report("\(text) Archivio: \(fault)", error: true)
        } else {
            report(text, error: error)
        }
    }

    /// Not the shared session: it caches, keeps cookies and waits a minute for
    /// every request. Each request sets its own timeout; these are the ceiling.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = WorkbenchModel.actionTimeout
        configuration.timeoutIntervalForResource = WorkbenchModel.actionTimeout
        return URLSession(configuration: configuration)
    }()

    private func get(_ path: String) async throws -> [String: Any] {
        try await send(path, payload: nil)
    }

    private func post(_ path: String, _ payload: [String: Any]) async throws -> [String: Any] {
        try await send(path, payload: payload)
    }

    /// One request, GET without a payload and POST with one, answered by the
    /// JSON object the façade writes. The server refuses a POST that is not
    /// application/json (415), a foreign Host or Origin (403), a body over
    /// 1 MiB (413) and a wrong method (405), always in the envelope
    /// {"ok": false, "error": text}. A POST that is refused that way returns
    /// the envelope, which the caller reads as every other refusal of a gate.
    /// Any other status of 400 or more, and any body that is not an object,
    /// throws, so a failure is never taken for an answer.
    private func send(_ path: String, payload: [String: Any]?) async throws -> [String: Any] {
        guard let url = URL(string: baseURL + path) else {
            throw APIError.invalidURL(baseURL)
        }
        var request = URLRequest(url: url, timeoutInterval: Self.readTimeout)
        if let payload {
            let body = try JSONSerialization.data(withJSONObject: payload)
            // The server answers 413 without reading the body and closes the
            // connection, which the client would report as a lost connection.
            guard body.count <= Self.maxRequestBodyOctets else { throw APIError.bodyTooLarge }
            request.httpMethod = "POST"
            request.timeoutInterval = Self.actionTimeout
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        // A refresh that was cancelled must not go on to publish what it read.
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if status >= 400 {
            let reason = object.flatMap { string($0["error"]) }
            if payload != nil, let object, reason != nil, object["ok"] as? Bool == false {
                return object
            }
            throw APIError.status(status, reason)
        }
        guard let object else { throw APIError.notJSONObject(status) }
        return object
    }

    /// JSON true and false arrive as NSNumber, and Swift bridges them to Int
    /// and to text ("0", "1") like any other number. The server writes NIL as
    /// false (a step has no :iterations, a halt has no reason), so a boolean
    /// is never read as a number or as text.
    private func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private func string(_ value: Any?) -> String? {
        switch value {
        case let text as String:
            return text
        case let number as NSNumber:
            return isBoolean(number) ? nil : number.stringValue
        default:
            return nil
        }
    }

    /// The whole number VALUE states, or nil when it states none: absent,
    /// null, false, text that is not digits. A number out of range saturates.
    private func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            return isBoolean(number) ? nil : number.intValue
        case let text as String:
            return Int(text)
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
        integer(value) ?? 0
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
