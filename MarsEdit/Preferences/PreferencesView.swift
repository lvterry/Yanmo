import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView {
            EditorTab()
                .tabItem { Label("Editor", systemImage: "pencil") }

            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            ExportTab()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }

            CommandLineTab()
                .tabItem { Label("Command Line", systemImage: "terminal") }
        }
        .environmentObject(settings)
        .frame(width: 480, height: 340)
    }
}

// MARK: - Editor Tab

private struct EditorTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            LabeledContent("Font:") {
                HStack {
                    FontPickerButton(
                        fontName: $settings.editorFontName,
                        fontSize: $settings.editorFontSize
                    )
                    Text("\(Int(settings.editorFontSize)) pt")
                        .monospacedDigit()
                    Stepper("", value: $settings.editorFontSize, in: 8...72)
                        .labelsHidden()
                }
            }

            Toggle("Word wrap", isOn: $settings.wordWrap)

            LabeledContent("Reading speed:") {
                HStack {
                    TextField("WPM", value: $settings.readingSpeedWPM, format: .number)
                        .labelsHidden()
                        .frame(width: 70)
                    Text("wpm")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Appearance Tab

private struct AppearanceTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("Theme:", selection: $settings.selectedThemeId) {
                Text("Follow System").tag("")
                ForEach(Theme.builtIn, id: \.id) { theme in
                    Text("\(theme.name) (\(theme.mode.rawValue.capitalized))").tag(theme.id)
                }
            }

            Picker("Appearance:", selection: $settings.appearanceMode) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }

            Picker("PDF export theme:", selection: $settings.pdfExportThemeId) {
                Text("Same as editor").tag("")
                ForEach(Theme.builtIn, id: \.id) { theme in
                    Text(theme.name).tag(theme.id)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Export Tab

private struct ExportTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("Default PDF page size:", selection: $settings.defaultPageSize) {
                ForEach(DefaultPageSize.allCases, id: \.self) { size in
                    Text(size.label).tag(size)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Command Line Tab

private struct CommandLineTab: View {
    @StateObject private var installer = CommandLineToolInstaller()
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("Install the `mars` command to open files in Yanmo from Terminal.")
                    .fixedSize(horizontal: false, vertical: true)

                LabeledContent("Status:") {
                    statusView
                }

                HStack {
                    Spacer()
                    actionButton
                }

                LabeledContent("Usage:") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("mars notes.md").font(.system(.body, design: .monospaced))
                        Text("mars a.md b.md").font(.system(.body, design: .monospaced))
                        Text("mars").font(.system(.body, design: .monospaced))
                    }
                    .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { installer.refresh() }
    }

    @ViewBuilder
    private var statusView: some View {
        switch installer.status {
        case .notInstalled:
            Text("Not installed").foregroundStyle(.secondary)
        case .installed:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Installed at \(installer.installPath.path)")
            }
        case .installedElsewhere:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("Another `mars` exists at \(installer.installPath.path)")
            }
        case .unavailable(let reason):
            Text(reason).italic().foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch installer.status {
        case .notInstalled:
            Button("Install…") { perform(.install) }
        case .installed:
            Button("Uninstall") { perform(.uninstall) }
        case .installedElsewhere:
            Button("Replace…") { perform(.install) }
        case .unavailable:
            Button("Install…") { perform(.install) }.disabled(true)
        }
    }

    private enum Action { case install, uninstall }

    private func perform(_ action: Action) {
        errorMessage = nil
        let result: CommandLineToolInstaller.ActionResult
        switch action {
        case .install: result = installer.install()
        case .uninstall: result = installer.uninstall()
        }
        switch result {
        case .success, .cancelled:
            break
        case .failure(let message):
            errorMessage = message
        }
    }
}
