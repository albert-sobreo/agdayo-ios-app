import SwiftUI
import UIKit

/// Connects the person's own Claude to their Agdayo account. They add Agdayo as
/// a custom connector in Claude, and on its sign-in page enter a one-time code
/// from here. Works for every kind of account (Apple, Google, email), and
/// Claude can then only reach the trips this account owns or has joined.
struct ConnectClaudeView: View {
    private enum CodeState {
        case idle
        case loading
        case ready(code: String, expiresAt: Date)
        case failed(String)
    }

    @State private var codeState: CodeState = .idle
    @State private var copiedURL = false
    @State private var copiedCode = false

    var body: some View {
        Form {
            Section {
                Text("Plan a trip by chatting with Claude, then have it write the plan straight into Agdayo: activities, stays, transport and notes. Works on Claude's free plan.")
                    .font(AppFont.outfit(14, relativeTo: .body))
            }

            Section("1. Add Agdayo to Claude") {
                Text("In the Claude phone app, open Settings › Connectors. On claude.ai or the desktop app, open Settings › Plugins (just below Artifacts). Add a custom connector named Agdayo with this address:")
                    .font(AppFont.outfit(14, relativeTo: .body))
                Button {
                    UIPasteboard.general.string = AgdayoServer.connectorURL.absoluteString
                    copiedURL = true
                } label: {
                    HStack {
                        Text(AgdayoServer.connectorURL.absoluteString)
                            .font(.system(.footnote, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: copiedURL ? "checkmark" : "doc.on.doc")
                    }
                }
            }

            Section {
                Text("Tap Connect in Claude. On the Agdayo page that opens, enter this code:")
                    .font(AppFont.outfit(14, relativeTo: .body))
                codeRow
            } header: {
                Text("2. Sign in with a code")
            } footer: {
                Text("A code works once and lasts 10 minutes. If you sign in to Agdayo with Google, you can choose Continue with Google there instead.")
            }

            Section {
                Text("Claude only sees and changes trips you own or have joined, and asks before each change. To disconnect, remove Agdayo in Claude: Settings › Connectors on the phone, or Settings › Plugins on claude.ai and desktop.")
                    .font(AppFont.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(.secondary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(BrandPalette.canvas.ignoresSafeArea())
        .navigationTitle("Connect Claude")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var codeRow: some View {
        switch codeState {
        case .idle:
            Button("Get Code") { Task { await loadCode() } }
        case .loading:
            HStack {
                ProgressView()
                Text("Getting a code…").foregroundStyle(.secondary)
            }
        case .ready(let code, let expiresAt):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if context.date < expiresAt {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(code)
                                .font(.system(.title, design: .monospaced, weight: .semibold))
                                .textSelection(.enabled)
                            Spacer()
                            Button {
                                UIPasteboard.general.string = code
                                copiedCode = true
                            } label: {
                                Image(systemName: copiedCode ? "checkmark" : "doc.on.doc")
                            }
                            .accessibilityLabel("Copy code")
                        }
                        Text("Expires in \(Self.remaining(until: expiresAt, now: context.date))")
                            .font(AppFont.outfit(12, relativeTo: .caption))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Code expired. Get a New Code") { Task { await loadCode() } }
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(AppFont.outfit(13, relativeTo: .footnote))
                    .foregroundStyle(.red)
                Button("Try Again") { Task { await loadCode() } }
            }
        }
    }

    private func loadCode() async {
        codeState = .loading
        copiedCode = false
        do {
            let result = try await AgdayoServer.connectCode()
            codeState = .ready(code: result.code, expiresAt: .now.addingTimeInterval(TimeInterval(result.expiresInSeconds)))
        } catch {
            codeState = .failed(error.localizedDescription)
        }
    }

    private static func remaining(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
