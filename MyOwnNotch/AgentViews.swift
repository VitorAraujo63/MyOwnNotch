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
        HStack(spacing: 6) {
            Image(systemName: "sparkle").font(.system(size: 12, weight: .semibold)).foregroundColor(claudeOrange)
            Text(vm.agent.isRunning ? vm.agent.status : "Claude")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
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
    @State private var input = ""
    @FocusState private var focused: Bool

    var body: some View {
        if !session.isAvailable {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle").font(.system(size: 24, weight: .light)).foregroundColor(.orange)
                Text("CLI do Claude não encontrado").font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
                Text("Instale o Claude Code e faça login (`claude` no terminal).")
                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                header
                messagesList
                inputBar
            }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { focused = true } }
        }
    }

    // MARK: Cabeçalho

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle").font(.system(size: 11, weight: .bold)).foregroundColor(claudeOrange)
            Text("Claude").font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.9))

            Menu {
                ForEach(AgentSession.Model.allCases) { m in
                    Button(m.label) { session.model = m }
                }
            } label: {
                Text(session.model.label).font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(0.1)))
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()

            Button { session.agentMode.toggle() } label: {
                HStack(spacing: 3) {
                    Image(systemName: session.agentMode ? "terminal.fill" : "eye").font(.system(size: 9, weight: .bold))
                    Text(session.agentMode ? "Agente" : "Leitura").font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(session.agentMode ? .orange : .white.opacity(0.6))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(session.agentMode ? Color.orange.opacity(0.18) : Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help(session.agentMode ? "Modo agente: o Claude pode editar arquivos e rodar comandos" : "Somente leitura: o Claude lê arquivos e pesquisa na web")

            Spacer()

            if session.isRunning {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                    Text(session.status).font(.system(size: 10)).foregroundColor(.white.opacity(0.5))
                }
            }
            Button { session.newChat() } label: {
                Image(systemName: "square.and.pencil").font(.system(size: 11)).foregroundColor(.white.opacity(0.5))
                    .frame(width: 24, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain).help("Nova conversa")
        }
    }

    // MARK: Mensagens

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if session.messages.isEmpty {
                        emptyState
                    }
                    ForEach(session.messages) { msg in
                        bubble(msg).id(msg.id)
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: session.messages.last?.text) { _ in
                if let last = session.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
            .onChange(of: session.messages.count) { _ in
                if let last = session.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.05)))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 22, weight: .light)).foregroundColor(claudeOrange.opacity(0.8))
            Text("Pergunte qualquer coisa ao Claude").font(.system(size: 12, weight: .medium)).foregroundColor(.white.opacity(0.65))
            Text(session.agentMode ? "Modo agente: pode editar arquivos e executar comandos na sua pasta pessoal."
                                   : "Modo leitura: lê arquivos e pesquisa na web, sem alterar nada.")
                .font(.system(size: 9)).foregroundColor(.white.opacity(0.35)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 24)
    }

    @ViewBuilder
    private func bubble(_ msg: AgentSession.Message) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 60)
                Text(msg.text)
                    .font(.system(size: 12)).foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.14)))
                    .textSelection(.enabled)
            }
        case .assistant:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "sparkle").font(.system(size: 9, weight: .bold)).foregroundColor(claudeOrange).padding(.top, 3)
                Group {
                    if msg.text.isEmpty {
                        Text("…").foregroundColor(.white.opacity(0.4))
                    } else if let attr = try? AttributedString(markdown: msg.text,
                                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                        Text(attr)
                    } else {
                        Text(msg.text)
                    }
                }
                .font(.system(size: 12)).foregroundColor(.white.opacity(0.92))
                .textSelection(.enabled)
                Spacer(minLength: 20)
            }
        case .error:
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundColor(.orange)
                Text(msg.text).font(.system(size: 11)).foregroundColor(.orange.opacity(0.9)).textSelection(.enabled)
            }
        }
    }

    // MARK: Entrada

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Pergunte ao Claude…", text: $input)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white)
                .focused($focused)
                .onSubmit(submit)
            Button {
                session.isRunning ? session.cancel() : submit()
            } label: {
                Image(systemName: session.isRunning ? "stop.fill" : "arrow.up")
                    .font(.system(size: 10, weight: .bold)).foregroundColor(.black)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(session.isRunning ? Color.white.opacity(0.85) : claudeOrange))
            }
            .buttonStyle(.plain)
            .disabled(!session.isRunning && input.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.leading, 12).padding(.trailing, 5).padding(.vertical, 5)
        .background(Capsule().fill(Color.white.opacity(0.09)))
    }

    private func submit() {
        let text = input
        guard !session.isRunning, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        input = ""
        session.send(text)
    }
}
