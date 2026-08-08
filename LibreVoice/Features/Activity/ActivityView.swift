//
//  ActivityView.swift
//  LibreVoice
//

import AppKit
import SwiftUI

/// Shows everything LibreVoice has recorded about itself this session.
///
/// This screen exists because "no telemetry, no analytics" is a claim, and a claim the
/// user has no way to check. Here is the entire log, in the app, with a button to copy
/// it and a button to erase it. Nothing is written to disk, and nothing leaves the Mac
/// unless the user pastes it somewhere themselves.
struct ActivityView: View {
    @Environment(\.services) private var services
    @State private var viewModel: ActivityViewModel?
    @State private var didCopy = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.clear
            }
        }
        .task {
            let viewModel = viewModel ?? ActivityViewModel(container: services)
            self.viewModel = viewModel
            await viewModel.observe()
        }
        .navigationTitle("Activity")
    }

    @ViewBuilder
    private func content(_ viewModel: ActivityViewModel) -> some View {
        VStack(spacing: 0) {
            filters(viewModel)
            Divider()

            if viewModel.entries.isEmpty {
                ContentUnavailableView(
                    "Nothing recorded",
                    systemImage: "text.append",
                    description: Text("Log records from this session appear here.")
                )
            } else {
                List(viewModel.entries) { entry in
                    LogEntryRow(entry: entry)
                        .listRowSeparator(.visible)
                }
                .listStyle(.inset)
            }
        }
        .toolbar {
            ToolbarItem {
                Button {
                    copy(viewModel.exportText())
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                }
                .disabled(viewModel.entries.isEmpty)
                .help("Copy these records to the clipboard")
            }

            ToolbarItem {
                Button {
                    viewModel.clear()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(viewModel.entries.isEmpty)
                .help("Erase every recorded log entry")
            }
        }
    }

    @ViewBuilder
    private func filters(_ viewModel: ActivityViewModel) -> some View {
        HStack(spacing: 12) {
            Picker("Level", selection: Bindable(viewModel).minimumLevel) {
                ForEach(LogLevel.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .frame(maxWidth: 160)

            Picker("Category", selection: Bindable(viewModel).category) {
                Text("All").tag(LogCategory?.none)
                ForEach(LogCategory.allCases) { category in
                    Text(category.displayName).tag(LogCategory?.some(category))
                }
            }
            .frame(maxWidth: 200)

            Spacer()

            Text("\(viewModel.entries.count) records")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }
}

/// One log record.
private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(tint)
                .font(.caption)
                .frame(width: 14)
                .accessibilityHidden(true)

            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.tertiary)

            Text(entry.category.displayName)
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: .capsule)

            Text(entry.message)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(entry.source.fileName):\(entry.source.line)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.level.displayName), \(entry.category.displayName)")
        .accessibilityValue(entry.message)
    }

    private var symbolName: String {
        switch entry.level {
        case .debug: "ladybug"
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private var tint: Color {
        switch entry.level {
        case .debug: .secondary
        case .info: .blue
        case .warning: .orange
        case .error: .red
        }
    }
}

#Preview {
    ActivityView()
        .environment(\.services, PreviewServiceContainer())
        .frame(width: 760, height: 420)
}
