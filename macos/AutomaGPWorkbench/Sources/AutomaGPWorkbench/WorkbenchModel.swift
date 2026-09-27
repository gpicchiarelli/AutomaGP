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
                let missing = factLines(from: status["listening-missing"])
                missingLabel = missing.map(\.label).joined(separator: " · ")
                if listening && !wasListening && actionName.trimmingCharacters(in: .whitespaces).isEmpty,
                   let predicate = missing.first?.parts.first {
                    actionName = predicate.lowercased()
                }
                let explain = try await get("/api/explain")
                narration = string(explain["narration"]) ?? ""
                nodes = nodes(from: explain["graph"])
                let archive = try await get("/api/archive")
                cards = cards(from: archive["procedures"])
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
                }
                connected = true
                statusLine = "v\(version)"
                if !wasConnected {
                    notice = ""
                    noticeIsError = false
                }
            } catch {
                connected = false
                statusLine = "Server non raggiungibile su \(baseURL)"
                report(error.localizedDescription, error: true)
            }
        }
    }

    func setAuthority(_ value: String) {
        authority = value
        Task {
            _ = try? await post("/api/autonomy/policy", ["authority": value])
            refresh()
        }
    }

    func simulate() {
        Task {
            await run("/api/simulate", [:], success: "Simulazione conclusa. I fatti non sono cambiati.")
        }
    }

    func execute() {
        Task {
            await run("/api/run", ["confirm": true, "adapters": false], success: "Esecuzione conclusa. I fatti del contesto sono aggiornati.")
        }
    }

    func use(name: String) {
        Task {
            await run("/api/archive/use", ["name": name], success: "Piano ricostruito da \(name).")
        }
    }

    func noteState() {
        Task {
            await run("/api/induce/note", [:], success: "Stato annotato. Modifica i fatti, poi induci la regola.")
        }
    }

    func addFact() {
        let parts = factDraft.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return }
        factDraft = ""
        Task {
            await run("/api/add-fact", ["fact": parts], success: "Fatto aggiunto.")
        }
    }

    func ask() {
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
                let added = try await post("/api/add-goal", ["goal": goal.parts])
                if let error = string(added["error"]), added["ok"] as? Bool == false {
                    report(error, error: true)
                    return
                }
                let planned = try await post("/api/plan", ["goals": [goal.parts]])
                if let error = string(planned["error"]), planned["ok"] as? Bool == false {
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

    func noticeDirectory() {
        let path = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        pathDraft = ""
        Task {
            await run("/api/notice-directory", ["path": path],
                      success: "Cartella notata. I file descritti entrano nel contesto. Il piano non parte.")
        }
    }

    func noticePath() {
        let path = pathDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        pathDraft = ""
        Task {
            await run("/api/notice-path", ["path": path],
                      success: "File notato. Il fatto entra nel contesto.")
        }
    }

    func removeFact(_ fact: FactLine) {
        Task {
            await run("/api/remove-fact", ["fact": fact.parts], success: "Fatto tolto.")
        }
    }

    func learnRule() {
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
        guard let learned else { return }
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
                operators: ops.joined(separator: " · ")
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
