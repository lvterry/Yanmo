import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label("General", systemImage: "gear") }

            EditorTab()
                .tabItem { Label("Editor", systemImage: "pencil") }

            AppearanceTab()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }

            ExportTab()
                .tabItem { Label("Export", systemImage: "square.and.arrow.up") }
        }
        .environmentObject(settings)
        .frame(width: 480, height: 340)
    }
}

// MARK: - General Tab

private struct GeneralTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            Picker("On launch:", selection: $settings.launchBehavior) {
                ForEach(LaunchBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.label).tag(behavior)
                }
            }

            Toggle("Auto-save", isOn: $settings.autoSaveEnabled)
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Editor Tab

private struct EditorTab: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        Form {
            HStack {
                Text("Font:")
                TextField("Font name", text: $settings.editorFontName)
                    .frame(width: 160)
                Text("\(Int(settings.editorFontSize)) pt")
                Stepper("", value: $settings.editorFontSize, in: 8...72)
                    .labelsHidden()
            }

            HStack {
                Text("Line height:")
                Slider(value: $settings.editorLineHeight, in: 1.0...3.0, step: 0.1)
                Text(String(format: "%.1f", settings.editorLineHeight))
                    .frame(width: 30)
            }

            Toggle("Show line numbers", isOn: $settings.showLineNumbers)
            Toggle("Highlight current line", isOn: $settings.highlightCurrentLine)
            Toggle("Word wrap", isOn: $settings.wordWrap)

            HStack {
                Text("Reading speed:")
                TextField("WPM", value: $settings.readingSpeedWPM, format: .number)
                    .frame(width: 60)
                Text("wpm")
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
