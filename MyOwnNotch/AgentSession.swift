//
//  AgentSession.swift
//  MyOwnNotch
//
//  Conexão com o Claude usando o CLI `claude` (Claude Code) já instalado e logado na
//  máquina: nenhuma chave de API é necessária. Cada pergunta roda `claude -p` com saída
//  em stream-json; o `session_id` é reaproveitado (--resume) para manter o contexto.
//

import SwiftUI
import Combine

@MainActor
final class AgentSession: ObservableObject {

    enum Role { case user, assistant, error }

    struct Message: Identifiable {
        let id = UUID()
        var role: Role
        var text: String
    }

    enum Model: String, CaseIterable, Identifiable {
        case haiku, sonnet, opus
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    @Published var messages: [Message] = []
    @Published var isRunning = false
    @Published var status = ""
    @Published var model: Model = .sonnet
    /// Modo agente: pode editar arquivos e rodar comandos (desligado = somente leitura/web)
    @Published var agentMode = false
    @Published private(set) var cliPath: String?

    private var sessionId: String?
    private var process: Process?
    private var lineBuffer = Data()
    private var errorOutput = ""

    init() { cliPath = Self.findCLI() }

    var isAvailable: Bool { cliPath != nil }

    // MARK: - Localizar o CLI

    private static func findCLI() -> String? {
        let home = NSHomeDirectory()
        let candidates = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                          "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude"]
        if let hit = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return hit }
        // Último recurso: pergunta ao shell de login
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    // MARK: - Ações

    func newChat() {
        cancel()
        messages.removeAll()
        sessionId = nil
        status = ""
    }

    func cancel() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        isRunning = false
        status = ""
    }

    func send(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isRunning, let cli = cliPath else { return }

        messages.append(Message(role: .user, text: text))
        messages.append(Message(role: .assistant, text: ""))
        isRunning = true
        status = "Pensando…"
        lineBuffer = Data()
        errorOutput = ""

        var args = ["-p", "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                    "--model", model.rawValue]
        if let sessionId { args += ["--resume", sessionId] }
        if agentMode {
            args += ["--permission-mode", "acceptEdits",
                     "--allowedTools=Read,Write,Edit,Bash,Glob,Grep,WebSearch,WebFetch"]
        } else {
            args += ["--allowedTools=Read,Glob,Grep,WebSearch,WebFetch"]
        }
        args += ["--", text]

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: cli)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        var env = ProcessInfo.processInfo.environment
        let extra = "\(NSHomeDirectory())/.local/bin:/opt/homebrew/bin:/usr/local/bin"
        env["PATH"] = extra + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env
        proc.standardInput = FileHandle.nullDevice

        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err

        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let s = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async { self?.errorOutput += s }
        }
        proc.terminationHandler = { [weak self] p in
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async { self?.finished(exitCode: p.terminationStatus) }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            fail("Não foi possível iniciar o Claude: \(error.localizedDescription)")
        }
    }

    // MARK: - Stream

    private func consume(_ data: Data) {
        lineBuffer.append(data)
        while let nl = lineBuffer.firstIndex(of: 0x0A) {
            let line = lineBuffer.subdata(in: lineBuffer.startIndex..<nl)
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            handle(line: line)
        }
    }

    private func handle(line: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = obj["type"] as? String else { return }

        if let sid = obj["session_id"] as? String { sessionId = sid }

        switch type {
        case "stream_event":
            guard let event = obj["event"] as? [String: Any], let et = event["type"] as? String else { return }
            if et == "content_block_delta", let delta = event["delta"] as? [String: Any] {
                if delta["type"] as? String == "text_delta", let t = delta["text"] as? String {
                    appendToAssistant(t); status = "Escrevendo…"
                } else if delta["type"] as? String == "thinking_delta" {
                    status = "Pensando…"
                }
            }
        case "assistant":
            // Blocos tool_use indicam o agente trabalhando
            if let msg = obj["message"] as? [String: Any], let content = msg["content"] as? [[String: Any]] {
                for block in content where block["type"] as? String == "tool_use" {
                    status = "Usando \(block["name"] as? String ?? "ferramenta")…"
                }
            }
        case "result":
            if obj["is_error"] as? Bool == true {
                fail((obj["result"] as? String) ?? "Erro desconhecido")
            } else if let r = obj["result"] as? String, lastAssistantText.isEmpty {
                appendToAssistant(r)   // caso nenhum delta tenha chegado
            }
        default: break
        }
    }

    private var lastAssistantText: String {
        messages.last(where: { $0.role == .assistant })?.text ?? ""
    }

    private func appendToAssistant(_ text: String) {
        guard let i = messages.lastIndex(where: { $0.role == .assistant }) else { return }
        messages[i].text += text
    }

    private func finished(exitCode: Int32) {
        process = nil
        isRunning = false
        status = ""
        if exitCode != 0 && lastAssistantText.isEmpty {
            let tail = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).suffix(300)
            fail(tail.isEmpty ? "O Claude encerrou com código \(exitCode). Verifique o login com `claude` no terminal." : String(tail))
        } else if let i = messages.lastIndex(where: { $0.role == .assistant }), messages[i].text.isEmpty {
            messages.remove(at: i)
        }
    }

    private func fail(_ message: String) {
        if let i = messages.lastIndex(where: { $0.role == .assistant }), messages[i].text.isEmpty {
            messages.remove(at: i)
        }
        messages.append(Message(role: .error, text: message))
        isRunning = false
        status = ""
    }
}
