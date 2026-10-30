//
//  AgentViews.swift
//  MyOwnNotch
//
//  Aba "Claude": chat com o Claude direto do notch.
//

import SwiftUI

private let claudeOrange = Color(red: 0.85, green: 0.47, blue: 0.34)

// MARK: - Compact

struct AgentCompactView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View {
        HStack(spacing: NotchTheme.Spacing.s) {
            Image(systemName: "sparkle").font(NotchFont.body.weight(.semibold)).foregroundStyle(claudeOrange)
            Text(vm.agent.isRunning ? vm.agent.status : "Claude")
                .font(NotchFont.body.weight(.semibold)).foregroundStyle(NotchTheme.textPrimary)
            if vm.agent.agentMode {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
                    .accessibilityLabel("Modo agente ativo")
            }
        }
    }
}

// MARK: - Expanded

struct AgentExpandedView: View {
    @EnvironmentObject var vm: NotchViewModel
    var body: some View { AgentChatView(session: vm.agent) }
}

struct AgentChatView: View {
    @ObservedObject var session: AgentSession
    @AppStorage(SettingsKey.agentModeAcknowledged) private var agentAcknowledged = false
    @State private var input = ""
    @State private var confirmingAgentMode = false
    @FocusState private var focused: Bool

    private static let installURL = URL(string: "https://docs.claude.com/en/docs/claude-code/overview")

    var body: some View {
        if session.cliStatus == .loading {
            loadingState
        } else if !session.isAvailable {
            missingCLIState
        } else if confirmingAgentMode {
            agentConfirmation
        } else {
            VStack(spacing: NotchTheme.Spacing.m) {
                header
                workingDirectoryRow
                directoryMessages
                messagesList
                inputBar
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true } }
        }
    }

    // MARK: Estados do CLI

    private var loadingState: some View {
        VStack(spacing: NotchTheme.Spacing.m) {
            VStack(alignment: .leading, spacing: NotchTheme.Spacing.s) {
                Text("Procurando o Claude Code no seu Mac…").font(NotchFont.body.weight(.semibold))
                Text("Verificando a instalação e o login").font(NotchFont.label)
            }
            .shimmer()
            StateView(kind: .loading, message: "Procurando Claude Code…")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var missingCLIState: some View {
        VStack(spacing: NotchTheme.Spacing.l) {
            StateView(kind: .failed("CLI do Claude não encontrado"),
                      actionTitle: "Procurar de novo") { session.refreshCLI() }
            Text("Instale o Claude Code e faça login (`claude` no terminal).")
                .font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary)
            if let url = Self.installURL {
                Link(destination: url) {
                    Label("Como instalar o Claude Code", systemImage: "arrow.up.right.square")
                        .font(NotchFont.label.weight(.medium))
                        .foregroundStyle(claudeOrange)
                }
                .accessibilityHint("Abre a documentação no navegador")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Confirmação do modo agente

    private var agentConfirmation: some View {
        VStack(spacing: NotchTheme.Spacing.l) {
            Image(systemName: "terminal.fill").font(.system(size: 20)).foregroundStyle(Color.orange)
                .accessibilityHidden(true)
            Text("Ativar o modo agente?").font(NotchFont.title).foregroundStyle(NotchTheme.textPrimary)
            Text("O Claude poderá criar e editar arquivos em \"\(session.workingDirectory.lastPathComponent)\" (exceto .git, .claude e .mcp.json), ler arquivos e listar pastas com ls. Não executa git, outros comandos nem acessa a web. Configurações do projeto são ignoradas.")
                .font(NotchFont.label).foregroundStyle(NotchTheme.textSecondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .help(session.workingDirectory.path)
            HStack(spacing: NotchTheme.Spacing.m) {
                Button { withAnimation(Motion.micro) { confirmingAgentMode = false } } label: {
                    Text("Cancelar").font(NotchFont.label.weight(.semibold)).foregroundStyle(NotchTheme.textSecondary)
                        .padding(.horizontal, NotchTheme.Spacing.l).padding(.vertical, 5)
                        .background(Capsule().fill(NotchTheme.fillSubtle))
                }
                .buttonStyle(HoverPressStyle(pressedScale: 0.95))
                Button {
                    agentAcknowledged = true
                    session.agentMode = true
                    withAnimation(Motion.micro) { confirmingAgentMode = false }
                } label: {
                    Text("Ativar modo agente").font(NotchFont.label.weight(.bold)).foregroundStyle(Color.black)
                        .padding(.horizontal, NotchTheme.Spacing.l).padding(.vertical, 5)
                        .background(Capsule().fill(Color.orange))
                }
                .buttonStyle(HoverPressStyle(pressedScale: 0.95))
            }
        }
        .padding(.horizontal, NotchTheme.Spacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Cabeçalho

    private var header: some View {
        HStack(spacing: NotchTheme.Spacing.m) {
            Image(systemName: "sparkle").font(NotchFont.label.weight(.bold)).foregroundStyle(claudeOrange)
                .accessibilityHidden(true)
            Text("Claude").font(NotchFont.body.weight(.semibold)).foregroundStyle(NotchTheme.textPrimary)

            Menu {
                ForEach(AgentSession.Model.allCases) { m in
                    Button(m.label) { session.model = m }
                }
            } label: {
                Text(session.model.label).font(NotchFont.caption.weight(.semibold))
                    .foregroundStyle(NotchTheme.textSecondary)
                    .padding(.horizontal, NotchTheme.Spacing.m).padding(.vertical, 3)
                    .background(Capsule().fill(NotchTheme.fillSelected))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Modelo")
            .accessibilityValue(session.model.label)

            Button { toggleAgentMode() } label: {
                HStack(spacing: 3) {
                    Image(systemName: session.agentMode ? "terminal.fill" : "eye").font(NotchFont.caption.weight(.bold))
                    Text(session.agentMode ? "Agente ativo" : "Leitura").font(NotchFont.caption.weight(.semibold))
                }
                .foregroundStyle(session.agentMode ? Color.orange : NotchTheme.textSecondary)
                .padding(.horizontal, NotchTheme.Spacing.m).padding(.vertical, 3)
                .background(Capsule().fill(session.agentMode ? Color.orange.opacity(0.22) : NotchTheme.fillSubtle))
                .overlay(Capsule().strokeBorder(session.agentMode ? Color.orange.opacity(0.7) : Color.clear, lineWidth: 1))
            }
            .buttonStyle(HoverPressStyle(pressedScale: 0.95))
            .accessibilityLabel(session.agentMode ? "Modo agente ativo" : "Modo leitura")
            .accessibilityHint("Alterna entre leitura e agente")
            .help(session.agentMode
                  ? "Modo agente: o Claude pode criar e editar arquivos no diretório de trabalho"
                  : "Somente leitura: o Claude lê arquivos do diretório de trabalho, sem alterar nada")

            Spacer()

            if session.isRunning {
                HStack(spacing: NotchTheme.Spacing.xs) {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                    Text(session.status).font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary)
                }
            }
            Button { session.newChat() } label: {
                Image(systemName: "square.and.pencil").font(NotchFont.label).foregroundStyle(NotchTheme.textSecondary)
                    .frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(HoverPressStyle())
            .accessibilityLabel("Nova conversa")
            .help("Nova conversa")
        }
    }

    private func toggleAgentMode() {
        if session.agentMode {
            session.agentMode = false
        } else if agentAcknowledged {
            session.agentMode = true
        } else {
            withAnimation(Motion.micro) { confirmingAgentMode = true }
        }
    }

    // MARK: Diretório de trabalho

    private var isDefaultDirectory: Bool {
        session.workingDirectory.standardizedFileURL == AgentSession.defaultWorkspace().standardizedFileURL
    }

    private var workingDirectoryRow: some View {
        HStack(spacing: NotchTheme.Spacing.s) {
            Image(systemName: "folder").font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary)
                .accessibilityHidden(true)
            Text(session.workingDirectory.lastPathComponent)
                .font(NotchFont.caption.weight(.medium)).foregroundStyle(NotchTheme.textSecondary)
                .lineLimit(1).truncationMode(.middle)
                .help(session.workingDirectory.path)
                .accessibilityLabel("Diretório de trabalho: \(session.workingDirectory.lastPathComponent)")
            textButton("Trocar…", hint: "Escolher outro diretório de trabalho") { chooseDirectory() }
            if !isDefaultDirectory {
                textButton("Restaurar padrão", hint: "Voltar ao diretório dedicado do app") { session.resetWorkingDirectory() }
            }
            Spacer(minLength: 0)
        }
        .disabled(session.isRunning)
    }

    @ViewBuilder private var directoryMessages: some View {
        if let e = session.directoryError {
            Label(e, systemImage: "exclamationmark.triangle.fill")
                .font(NotchFont.caption).foregroundStyle(Color.red.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        } else if let n = session.directoryNotice {
            Label(n, systemImage: "info.circle")
                .font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func textButton(_ title: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(NotchFont.caption.weight(.semibold)).foregroundStyle(claudeOrange)
        }
        .buttonStyle(HoverPressStyle(pressedScale: 0.95))
        .accessibilityHint(hint)
        .help(hint)
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Escolher"
        panel.message = "Escolha o diretório de trabalho do Claude"
        panel.directoryURL = session.workingDirectory
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            session.setWorkingDirectory(url)
        }
    }

    // MARK: Mensagens

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: NotchTheme.Spacing.m) {
                    if session.messages.isEmpty {
                        emptyState
                    }
                    ForEach(session.messages) { msg in
                        bubble(msg).id(msg.id)
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, NotchTheme.Spacing.xs)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.messages.last?.text) {
                if let last = session.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: session.messages.count) {
                if let last = session.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(NotchTheme.Spacing.m)
        .background(RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous).fill(NotchTheme.fillSubtle))
    }

    private var emptyState: some View {
        VStack(spacing: NotchTheme.Spacing.s) {
            Image(systemName: "sparkles").font(.system(size: 22, weight: .light)).foregroundStyle(claudeOrange)
                .accessibilityHidden(true)
            Text("Pergunte qualquer coisa ao Claude").font(NotchFont.body.weight(.medium)).foregroundStyle(NotchTheme.textSecondary)
            Text(session.agentMode ? "Modo agente: pode criar e editar arquivos no diretório de trabalho."
                                   : "Modo leitura: lê arquivos do diretório de trabalho, sem alterar nada.")
                .font(NotchFont.caption).foregroundStyle(NotchTheme.textTertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 16)
    }

    @ViewBuilder
    private func bubble(_ msg: AgentSession.Message) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(msg.text)
                    .font(NotchFont.body).foregroundStyle(NotchTheme.textPrimary)
                    .padding(.horizontal, 10).padding(.vertical, NotchTheme.Spacing.s)
                    .background(RoundedRectangle(cornerRadius: NotchTheme.Radius.large, style: .continuous).fill(NotchTheme.fillSelected))
                    .textSelection(.enabled)
            }
        case .assistant:
            HStack(alignment: .top, spacing: NotchTheme.Spacing.s) {
                Image(systemName: "sparkle").font(NotchFont.caption.weight(.bold)).foregroundStyle(claudeOrange).padding(.top, 3)
                    .accessibilityHidden(true)
                Group {
                    if msg.text.isEmpty {
                        Text("…").foregroundStyle(NotchTheme.textTertiary)
                    } else if let attr = try? AttributedString(markdown: msg.text,
                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attr)
                    } else {
                        Text(msg.text)
                    }
                }
                .font(NotchFont.body).foregroundStyle(NotchTheme.textPrimary)
                .textSelection(.enabled)
                Spacer(minLength: 20)
            }
        case .error:
            HStack(alignment: .top, spacing: NotchTheme.Spacing.s) {
                Image(systemName: "exclamationmark.triangle.fill").font(NotchFont.caption).foregroundStyle(Color.orange)
                    .accessibilityLabel("Erro")
                Text(msg.text).font(NotchFont.label).foregroundStyle(Color.orange).textSelection(.enabled)
            }
        }
    }

    // MARK: Entrada

    private var inputBar: some View {
        HStack(spacing: NotchTheme.Spacing.m) {
            TextField("Pergunte ao Claude…", text: $input)
                .textFieldStyle(.plain)
                .font(NotchFont.body)
                .foregroundStyle(NotchTheme.textPrimary)
                .focused($focused)
                .onSubmit(submit)
            Button {
                session.isRunning ? session.cancel() : submit()
            } label: {
                Image(systemName: session.isRunning ? "stop.fill" : "arrow.up")
                    .font(NotchFont.caption.weight(.bold)).foregroundStyle(Color.black)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(session.isRunning ? NotchTheme.textPrimary.opacity(0.85) : claudeOrange))
            }
            .buttonStyle(HoverPressStyle())
            .accessibilityLabel(session.isRunning ? "Parar" : "Enviar")
            .help(session.isRunning ? "Parar" : "Enviar")
            .disabled(!session.isRunning && input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.leading, NotchTheme.Spacing.l).padding(.trailing, 5).padding(.vertical, 5)
        .background(Capsule().fill(NotchTheme.fillSubtle))
    }

    private func submit() {
        let text = input
        guard !session.isRunning, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        input = ""
        session.send(text)
    }
}
