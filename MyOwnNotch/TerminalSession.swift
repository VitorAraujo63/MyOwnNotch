//
//  TerminalSession.swift
//  MyOwnNotch
//
//  Terminal real: um shell de login rodando num PTY (via SwiftTerm), com
//  emulação xterm completa (cores, vim, htop, Ctrl-C, histórico, etc.).
//  A sessão vive no ViewModel, então continua rodando ao trocar de aba.
//

import AppKit
import SwiftUI
import SwiftTerm

final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {

    let view: LocalProcessTerminalView
    private var started = false

    override init() {
        view = LocalProcessTerminalView(frame: NSRect(x: 0, y: 0, width: 420, height: 120))
        super.init()
        view.processDelegate = self
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.nativeBackgroundColor = .clear
        view.nativeForegroundColor = NSColor(white: 0.92, alpha: 1)
        view.caretColor = NSColor.systemGreen
        view.optionAsMetaKey = true
    }

    func startIfNeeded() {
        guard !started else { return }
        started = true

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("LANG=\(ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8")")

        // execName com "-" na frente = shell de login (carrega .zprofile/.zshrc, PATH, aliases)
        let name = "-" + (shell as NSString).lastPathComponent
        FileManager.default.changeCurrentDirectoryPath(NSHomeDirectory())
        view.startProcess(executable: shell,
                          args: [],
                          environment: env,
                          execName: name)
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Shell encerrado (ex.: `exit`): reinicia na próxima abertura
        started = false
        DispatchQueue.main.async { [weak self] in
            self?.view.feed(text: "\r\n\u{1B}[2m[processo encerrado — reiniciando]\u{1B}[0m\r\n")
            self?.startIfNeeded()
        }
    }
}

// MARK: - SwiftUI

struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> NSView {
        session.startIfNeeded()
        let container = NSView()
        let tv = session.view
        tv.removeFromSuperview()
        tv.frame = container.bounds
        tv.autoresizingMask = [.width, .height]
        container.addSubview(tv)
        // Dá foco ao terminal para o teclado funcionar sem clique extra
        DispatchQueue.main.async {
            tv.window?.makeKeyAndOrderFront(nil)
            tv.window?.makeFirstResponder(tv)
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
