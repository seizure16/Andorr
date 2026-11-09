import SwiftUI
import AppKit

enum PreferenceKeys {
    static let appearance = "appearance"
    static let showStatuses = "showStatuses"
    static let showTags = "showTags"
    static let editorZoom = "editorZoom"
    static let openingMode = "noteOpeningMode"
    static let reopenFolder = "reopenLastFolder"
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: "Système"; case .light: "Clair"; case .dark: "Sombre" }
    }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }

    func resolvedColorScheme(system: ColorScheme) -> ColorScheme { colorScheme ?? system }
}

/// NSApplication keeps following macOS because only the windows have a theme
/// preference. Observe it outside the overridden SwiftUI view environment.
@MainActor
final class SystemAppearanceObserver: ObservableObject {
    @Published private(set) var colorScheme: ColorScheme
    private var observation: NSKeyValueObservation?

    init() {
        let application = NSApplication.shared
        colorScheme = Self.scheme(for: application.effectiveAppearance)
        observation = application.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] application, _ in
            Task { @MainActor [weak self] in
                self?.colorScheme = Self.scheme(for: application.effectiveAppearance)
            }
        }
    }

    static func scheme(for appearance: NSAppearance) -> ColorScheme {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

enum NoteOpeningMode: String, CaseIterable, Identifiable {
    case edit, preview
    var id: String { rawValue }
    var title: String { self == .edit ? "Édition" : "Aperçu" }

    static func preferred(in preferences: UserDefaults) -> Self {
        Self(rawValue: preferences.string(forKey: PreferenceKeys.openingMode) ?? "") ?? .edit
    }
}

struct SettingsView: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { Palette(colorScheme: colorScheme) }
    @Bindable var store: WorkspaceStore
    let systemColorScheme: ColorScheme
    @AppStorage(PreferenceKeys.appearance) private var appearance = AppAppearance.system
    @AppStorage(PreferenceKeys.showStatuses) private var showStatuses = true
    @AppStorage(PreferenceKeys.showTags) private var showTags = true
    @AppStorage(PreferenceKeys.editorZoom) private var editorZoom = EditorZoom.defaultScale
    @AppStorage(PreferenceKeys.openingMode) private var openingMode = NoteOpeningMode.edit
    @AppStorage(PreferenceKeys.reopenFolder) private var reopenFolder = true

    private var zoom: Double { EditorZoom.normalized(editorZoom) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .light)).foregroundStyle(Palette.accent)
                    .frame(width: 46, height: 46)
                    .background(Palette.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Réglages").font(.system(size: 25, weight: .semibold))
                    Text("Personnalisez l’affichage et l’écriture.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 16) {
                    appearanceCard
                    editorCard
                    folderCard
                }
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
        .frame(width: 600, height: 740)
        .background(palette.sidebar)
        .tint(Palette.accent)
    }

    private var appearanceCard: some View {
        SettingsCard("Apparence", icon: "circle.lefthalf.filled") {
            HStack(spacing: 10) {
                ForEach(AppAppearance.allCases) { theme in
                    SettingsThemeOption(theme: theme, systemColorScheme: systemColorScheme, selection: $appearance)
                }
            }
            Divider().opacity(0.5).padding(.vertical, 2)
            settingsToggle("Statuts des notes", detail: "Afficher l’avancement sous chaque titre.", value: $showStatuses)
            settingsToggle("Tags des notes", detail: "Afficher les étiquettes dans la barre latérale.", value: $showTags)
        }
    }

    private var editorCard: some View {
        SettingsCard("Éditeur", icon: "square.and.pencil") {
            HStack(spacing: 10) {
                Text("Taille du texte").font(.system(size: 13, weight: .medium))
                Spacer()
                Text("\(Int((zoom * 100).rounded())) %")
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(palette.sidebar, in: RoundedRectangle(cornerRadius: 5))
                Button { editorZoom = EditorZoom.defaultScale } label: {
                    Image(systemName: "arrow.counterclockwise").frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .disabled(zoom == EditorZoom.defaultScale)
                .help("Revenir à 100 %")
                .accessibilityLabel("Réinitialiser la taille du texte")
            }
            HStack(spacing: 12) {
                Text("A").font(.system(size: 11)).foregroundStyle(.secondary).accessibilityHidden(true)
                Slider(value: Binding(get: { zoom }, set: { editorZoom = $0 }),
                       in: EditorZoom.minimum...EditorZoom.maximum, step: 0.1)
                    .accessibilityLabel("Taille du texte")
                    .accessibilityValue("\(Int((zoom * 100).rounded())) pour cent")
                Text("A").font(.system(size: 18)).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Aperçu").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Text("Votre texte Markdown")
                    .font(.system(size: 14 * CGFloat(zoom), design: .monospaced))
                    .lineLimit(1).frame(minHeight: 25, alignment: .leading)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.sidebar, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityElement(children: .combine)
            Divider().opacity(0.5).padding(.vertical, 2)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("À l’ouverture d’une note").font(.system(size: 13, weight: .medium))
                    Text("Les nouvelles notes restent en édition.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Picker("Mode d’ouverture", selection: $openingMode) {
                    ForEach(NoteOpeningMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu).labelsHidden().frame(width: 115)
            }
        }
    }

    private var folderCard: some View {
        SettingsCard("Dossier de cours", icon: "folder") {
            settingsToggle("Rouvrir le dernier dossier", detail: "Au prochain lancement d’Andorr.", value: $reopenFolder)
            Divider().opacity(0.5).padding(.vertical, 2)
            HStack(spacing: 12) {
                Image(systemName: "folder").font(.system(size: 21, weight: .light))
                    .foregroundStyle(Palette.accent).frame(width: 32)
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.root?.lastPathComponent ?? "Aucun dossier ouvert")
                        .font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text(store.root?.path ?? "Choisissez le dossier de vos cours.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Button(store.root == nil ? "Choisir…" : "Changer…", action: store.chooseFolder)
                    .buttonStyle(.bordered).controlSize(.small).disabled(store.isBusy)
            }
            .padding(12)
            .background(palette.sidebar, in: RoundedRectangle(cornerRadius: 7))
            if store.saveError != nil {
                Label("Enregistrez la note ouverte avant de changer de dossier.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func settingsToggle(_ title: String, detail: String, value: Binding<Bool>) -> some View {
        Toggle(isOn: value) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.switch).controlSize(.small)
        .padding(.vertical, 2)
    }
}

private struct SettingsCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { Palette(colorScheme: colorScheme) }
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    init(_ title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.icon = icon; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.paper, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.055), lineWidth: 1) }
    }
}

private struct SettingsThemeOption: View {
    let theme: AppAppearance
    let systemColorScheme: ColorScheme
    @Binding var selection: AppAppearance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selected: Bool { selection == theme }
    private var dark: Bool { theme.resolvedColorScheme(system: systemColorScheme) == .dark }

    var body: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { selection = theme }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    VStack(spacing: 5) {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 1).fill(dark ? Color.white.opacity(0.18) : Color.black.opacity(0.13)).frame(height: 3)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6).frame(width: 27)
                    .background(dark ? Color(white: 0.19) : Color(red: 0.91, green: 0.91, blue: 0.89))
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 1).fill(Palette.accent.opacity(0.65)).frame(height: 4).padding(.trailing, 18)
                        RoundedRectangle(cornerRadius: 1).fill(dark ? Color.white.opacity(0.22) : Color.black.opacity(0.14)).frame(height: 3)
                        RoundedRectangle(cornerRadius: 1).fill(dark ? Color.white.opacity(0.15) : Color.black.opacity(0.10)).frame(height: 3).padding(.trailing, 10)
                        Spacer(minLength: 0)
                    }.padding(.vertical, 10).padding(.trailing, 10)
                }
                .frame(height: 56)
                .background(dark ? Color(white: 0.12) : .white, in: RoundedRectangle(cornerRadius: 5))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay { RoundedRectangle(cornerRadius: 5).strokeBorder(.primary.opacity(0.08), lineWidth: 0.5) }
                .accessibilityHidden(true)
                HStack {
                    Text(theme.title).font(.system(size: 12, weight: .medium)).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: selected ? "checkmark.circle" : "circle")
                        .font(.system(size: 13)).foregroundStyle(selected ? Palette.accent : Color.secondary.opacity(0.4))
                }
            }
            .padding(10)
            .background(selected ? Palette.accent.opacity(0.05) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .overlay { RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Palette.accent.opacity(0.6) : .primary.opacity(0.08), lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).frame(maxWidth: .infinity)
        .accessibilityLabel("Thème \(theme.title)")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
