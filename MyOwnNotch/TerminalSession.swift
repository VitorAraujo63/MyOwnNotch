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
import Darwin

final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {

    let view: LocalProcessTerminalView
    private var started = false
    private var shellPid: pid_t = 0
    private var terminating = false

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
        terminating = false
        started = true

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("LANG=\(ProcessInfo.processInfo.environment["LANG"] ?? "en_US.UTF-8")")

        // Login shell iniciado na home SEM alterar o cwd do app: um /bin/zsh -c faz `cd` com o
        // diretório passado como argumento posicional (nunca interpolado) e substitui-se pelo
        // shell real com argv[0] = "-zsh" (login shell: carrega .zprofile/.zshrc, PATH, aliases).
        let name = "-" + (shell as NSString).lastPathComponent
        view.startProcess(executable: "/bin/zsh",
                          args: ["-c", "cd -- \"$1\" 2>/dev/null; exec -a \"$2\" \"$0\"", shell, NSHomeDirectory(), name],
                          environment: env,
                          execName: "zsh")
        shellPid = localProcess?.shellPid ?? 0
    }

    /// Encerra o shell/PTY (chamar ao sair do app). Não reinicia.
    func terminate() {
        terminating = true
        signalShell(SIGHUP)
        signalShell(SIGTERM)
        shellPid = 0
        started = false
    }

    deinit { signalShell(SIGHUP) }

    /// `LocalProcessTerminalView.process` é internal no SwiftTerm 1.5.1; lê via reflexão o
    /// `LocalProcess` (API pública: shellPid), sem varrer filhos por diferença de PIDs.
    private var localProcess: LocalProcess? {
        Mirror(reflecting: view).children.first(where: { $0.label == "process" })?.value as? LocalProcess
    }

    /// Só sinaliza o PID se ele ainda for filho direto deste processo (evita PID reciclado).
    private func signalShell(_ sig: Int32) {
        let pid = shellPid
        guard pid > 0 else { return }
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              pid_t(info.pbi_ppid) == getpid() else { return }
        kill(pid, sig)
    }

    // MARK: LocalProcessTerminalViewDelegate

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        // Shell encerrado (ex.: `exit`): reinicia na próxima abertura
        started = false
        shellPid = 0
        guard !terminating else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.terminating else { return }
            self.view.feed(text: "\r\n\u{1B}[2m[processo encerrado — reiniciando]\u{1B}[0m\r\n")
            self.startIfNeeded()
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
