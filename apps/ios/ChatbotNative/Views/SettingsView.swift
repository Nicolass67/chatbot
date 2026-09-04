import SwiftUI
import UIKit

struct SettingsView: View {
    /// Quand true, pas de NavigationStack (poussé depuis MoreHub).
    var embedded: Bool = false

    @EnvironmentObject private var session: AppSessionStore
    @EnvironmentObject private var appearance: AppearanceStore
    @State private var webSearchEnabled = false
    @State private var statusNote: String?
    @State private var runtimeStatus: String = "…"
    @State private var selectedModel: String = ""
    @State private var models: [ModelOptionDTO] = []
    @State private var modelSwitching = false
    @State private var oauthEmails: [String] = []
    @State private var oauthConfigured = false
    @State private var fileRoots: [FileRootDTO] = []

    private var client: APIClient {
        APIClient(baseURL: session.baseURL, token: session.token)
    }

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    private var appearanceHint: String {
        switch appearance.mode {
        case .system:
            return "Suit Réglages iOS → Affichage. Soft Graphite s’adapte automatiquement."
        case .light:
            return "Thème clair forcé (indépendant du mode système)."
        case .dark:
            return "Thème sombre Ink Indigo forcé (indépendant du mode système)."
        }
    }

    /// Banner Fast QA (Info.plist `QAGitSHA` injecté par ios-native-qa.yml).
    private var qaBuildLabel: String? {
        #if QA_BUILD
        let sha = Bundle.main.infoDictionary?["QAGitSHA"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        if let sha, !sha.isEmpty { return "QA \(build) · \(sha)" }
        return "QA \(build)"
        #else
        if let sha = Bundle.main.infoDictionary?["QAGitSHA"] as? String, !sha.isEmpty {
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
            return "QA \(build) · \(sha)"
        }
        return nil
        #endif
    }

    var body: some View {
        Group {
            if embedded {
                settingsContent
            } else {
                NavigationStack { settingsContent }
            }
        }
        .preferredColorScheme(appearance.mode.preferredColorScheme)
        .animation(.easeInOut(duration: AppTheme.motionQuick), value: appearance.mode)
        .id(appearance.mode)
    }

    private var settingsContent: some View {
        ZStack {
            AmbientBackground()
            List {
                Section {
                    LabeledContent("Utilisateur", value: session.userId ?? "—")
                    LabeledContent("Client", value: "ios · Mobile 3.0")
                    LabeledContent("Origin", value: session.baseURL.host ?? "")
                    LabeledContent("Version", value: appVersion)
                    if let qa = qaBuildLabel {
                        LabeledContent("Fast QA", value: qa)
                            .accessibilityIdentifier("settings.qa.build")
                    }
                    if let expires = session.expiresAt {
                        LabeledContent("Expire", value: AppDates.short(expires))
                    }
                    if session.sessionExpiringSoon {
                        Text("La session expire bientôt — reconnecte-toi pour la renouveler.")
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.warning)
                    }
                } header: {
                    Text("Session")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    Picker("Thème", selection: $appearance.mode) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(A11yID.Settings.appearance)
                    .accessibilityLabel("Thème de l’app")
                    Text(appearanceHint)
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                } header: {
                    Text("Apparence")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    Toggle("Verrouillage Face ID", isOn: Binding(
                        get: { session.biometricLockEnabled },
                        set: { session.setBiometricLockEnabled($0) }
                    ))
                    .tint(AppTheme.accent)
                    .accessibilityHint("Demande Face ID à chaque ouverture de l’app")
                    Text("Les souvenirs et fichiers restent sur ton PC. Cette app ne stocke que la session.")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                } header: {
                    Text("Confidentialité & sécurité")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    Toggle("Recherche web", isOn: $webSearchEnabled)
                        .tint(AppTheme.accent)
                        .onChange(of: webSearchEnabled) { _, newValue in
                            Task { await saveWebSearch(newValue) }
                        }
                    if modelSwitching {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Changement de modèle…")
                                .font(CNFont.caption)
                                .foregroundStyle(AppTheme.muted)
                        }
                    }
                    Picker("Modèle", selection: Binding(
                        get: { selectedModel },
                        set: { id in Task { await applyModel(id) } }
                    )) {
                        ForEach(models) { model in
                            Text(model.name).tag(model.id)
                        }
                    }
                    .disabled(modelSwitching || models.isEmpty)
                    if let statusNote {
                        Text(statusNote)
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.muted)
                    }
                    LabeledContent("Runtime", value: runtimeStatus)
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                } header: {
                    Text("Assistant")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    if !oauthConfigured {
                        Text("OAuth Google non configuré.")
                            .foregroundStyle(AppTheme.muted)
                    } else if oauthEmails.isEmpty {
                        Text("Aucun compte Gmail connecté.")
                            .foregroundStyle(AppTheme.warning)
                        Button("Connecter Gmail") {
                            Task { await connectGmail() }
                        }
                        .foregroundStyle(AppTheme.accent)
                    } else {
                        ForEach(oauthEmails, id: \.self) { email in
                            Label(email, systemImage: "envelope.fill")
                                .foregroundStyle(AppTheme.foreground)
                        }
                        Button("Déconnecter Gmail", role: .destructive) {
                            Task { await disconnectGmail() }
                        }
                    }
                } header: {
                    Text("Mail / OAuth")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    if fileRoots.isEmpty {
                        Text("Aucune racine Files.")
                            .foregroundStyle(AppTheme.muted)
                    } else {
                        ForEach(fileRoots.filter { $0.enabled != false }) { root in
                            VStack(alignment: .leading, spacing: AppTheme.space4) {
                                Text(root.label ?? root.id)
                                    .foregroundStyle(AppTheme.foreground)
                                if let path = root.absolutePath {
                                    Text(path)
                                        .font(CNFont.caption2)
                                        .foregroundStyle(AppTheme.mutedForeground)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Files roots")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    NavigationLink {
                        MemoryListView()
                    } label: {
                        Label("Souvenirs", systemImage: "brain.head.profile")
                    }
                    Text("Les souvenirs restent sur ton PC. Modifie ou oublie à tout moment.")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                } header: {
                    Text("Mémoire")
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    Button("Se déconnecter", role: .destructive) {
                        AppHaptics.warning()
                        Task { await session.logout() }
                    }
                    .frame(minHeight: AppTheme.touchMin)
                }
                .listRowBackground(AppTheme.surface)

                Section {
                    Text("Mobile 3.0 — Chat · Mail · Files. Réglages via compte.")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                } header: {
                    Text("À propos")
                }
                .listRowBackground(AppTheme.surface)
            }
            .scrollContentBackground(.hidden)
        }
        .accessibilityIdentifier(A11yID.Settings.root)
        .navigationTitle("Réglages")
        .tabRootNavigationChrome()
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            webSearchEnabled = try await client.getWebSearchEnabled()
        } catch {
            statusNote = error.localizedDescription
        }
        runtimeStatus = (try? await client.runtimeStatus()) ?? "UNKNOWN"
        models = (try? await client.listModels()) ?? []
        if let s = try? await client.getSettings() {
            selectedModel = (s["selectedModel"] as? String) ?? ""
        }
        if let oauth = try? await client.oauthAccounts() {
            oauthConfigured = oauth.configured
            oauthEmails = oauth.emails
        }
        fileRoots = (try? await client.listFileRoots()) ?? []
    }

    private func saveWebSearch(_ value: Bool) async {
        do {
            try await client.setWebSearchEnabled(value)
            statusNote = value ? "Recherche web activée" : "Recherche web désactivée"
        } catch {
            webSearchEnabled = !value
            statusNote = error.localizedDescription
        }
    }

    private func applyModel(_ modelId: String) async {
        guard modelId != selectedModel else { return }
        let previous = selectedModel
        selectedModel = modelId
        if let snap = try? await client.runtimeSnapshot(),
           snap.phase == "ready",
           snap.loadedModel == modelId {
            modelSwitching = false
            runtimeStatus = "READY"
            statusNote = "Modèle déjà prêt"
            AppHaptics.success()
            return
        }
        modelSwitching = true
        runtimeStatus = "SWITCHING"
        defer { modelSwitching = false }
        do {
            let accepted = try await client.selectModel(modelId)
            if accepted.phase == "ready", accepted.loadedModel == modelId {
                runtimeStatus = "READY"
                statusNote = "Modèle mis à jour"
                AppHaptics.success()
                return
            }
            for _ in 0..<80 {
                if let snap = try? await client.runtimeSnapshot() {
                    runtimeStatus = snap.phase == "ready" ? "READY" : "SWITCHING"
                    if snap.phase == "ready", snap.loadedModel == modelId {
                        statusNote = "Modèle mis à jour"
                        AppHaptics.success()
                        return
                    }
                    if snap.phase == "error" {
                        selectedModel = previous
                        statusNote = snap.message ?? "Impossible de charger le modèle"
                        runtimeStatus = "ERROR"
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            if let snap = try? await client.runtimeSnapshot(),
               snap.loadedModel == modelId {
                runtimeStatus = "READY"
                statusNote = "Modèle mis à jour"
                return
            }
            selectedModel = previous
            statusNote = "Le modèle ne confirme pas encore son chargement"
            runtimeStatus = (try? await client.runtimeStatus()) ?? "UNKNOWN"
        } catch {
            selectedModel = previous
            statusNote = error.localizedDescription
        }
    }

    private func connectGmail() async {
        do {
            let url = try await client.gmailAuthorizationURL()
            await MainActor.run { UIApplication.shared.open(url) }
            statusNote = "Termine la connexion dans Safari, puis tire pour rafraîchir."
        } catch {
            statusNote = error.localizedDescription
        }
    }

    private func disconnectGmail() async {
        do {
            try await client.disconnectGmail()
            oauthEmails = []
            AppHaptics.warning()
            statusNote = "Gmail déconnecté"
        } catch {
            statusNote = error.localizedDescription
        }
    }
}
