import SwiftUI

/// Capacité disque « importante » (iOS) — omit si l’API ne répond pas.
enum LocalDeviceStorageInfo {
    static func availableImportantBytes() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage,
              bytes > 0
        else {
            return nil
        }
        return bytes
    }

    static func availableLabel() -> String? {
        guard let bytes = availableImportantBytes() else { return nil }
        return "\(LocalModelByteLabel.decimal(bytes)) disponibles"
    }
}

/// Pastille d’action compacte (visuel serré, cible 44 pt).
struct LocalAICompactChip: View {
    enum Kind {
        case accent
        case outline
        case destructive
    }

    let title: String
    var kind: Kind = .accent
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(CNFont.caption.weight(.semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(background, in: Capsule())
                .overlay {
                    if kind == .outline || kind == .destructive {
                        Capsule()
                            .stroke(stroke, lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .frame(minWidth: AppTheme.touchMin, minHeight: AppTheme.touchMin)
        .contentShape(Rectangle())
        .accessibilityLabel(title)
    }

    private var foreground: Color {
        switch kind {
        case .accent: return AppTheme.accentForeground
        case .outline: return AppTheme.accent
        case .destructive: return AppTheme.danger
        }
    }

    private var background: Color {
        switch kind {
        case .accent: return AppTheme.accent
        case .outline, .destructive: return Color.clear
        }
    }

    private var stroke: Color {
        switch kind {
        case .accent: return .clear
        case .outline: return AppTheme.accent.opacity(0.35)
        case .destructive: return AppTheme.danger.opacity(0.35)
        }
    }
}

struct LocalAIStatusMark: View {
    enum Kind {
        case active
        case installed
        case available
        case downloading
        case loading
        case error
        case incompatible
    }

    let kind: Kind

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(CNFont.caption2.weight(.semibold))
        }
        .foregroundStyle(color)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }

    private var title: String {
        switch kind {
        case .active: return "Actif"
        case .installed: return "Installé"
        case .available: return "Disponible"
        case .downloading: return "Téléchargement"
        case .loading: return "Chargement"
        case .error: return "Erreur"
        case .incompatible: return "Non compatible avec le runtime actuel"
        }
    }

    private var symbol: String {
        switch kind {
        case .active: return "circle.fill"
        case .installed: return "checkmark"
        case .available: return "arrow.down"
        case .downloading: return "arrow.down.circle"
        case .loading: return "hourglass"
        case .error: return "exclamationmark.triangle.fill"
        case .incompatible: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch kind {
        case .active, .downloading, .loading: return AppTheme.accent
        case .installed: return AppTheme.success
        case .available: return AppTheme.mutedForeground
        case .error, .incompatible: return AppTheme.danger
        }
    }
}

struct LocalAIRecommendedBadge: View {
    var body: some View {
        Text("Recommandé")
            .font(CNFont.caption2.weight(.semibold))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(AppTheme.accentSubtle, in: Capsule())
            .accessibilityLabel("Recommandé")
    }
}

struct LocalAIModelDetailsSheet: View {
    let model: LocalModelDescriptor
    @Environment(\.dismiss) private var dismiss
    @State private var showComparison = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Famille", value: model.familyDisplayName)
                    LabeledContent("Architecture", value: model.architecture)
                    LabeledContent("Quantification", value: model.quant)
                    LabeledContent("Paramètres", value: model.parameterCountLabel)
                    LabeledContent("Taille", value: model.userFacingTextSizeLabel)
                    if let vision = model.userFacingVisionSizeLabel {
                        LabeledContent("Vision", value: vision)
                        LabeledContent("Total", value: model.userFacingPackSizeLabel)
                    } else if model.capabilities.vision {
                        LabeledContent("Vision", value: "Oui — pas de GGUF")
                    } else {
                        LabeledContent("Vision", value: "Non")
                    }
                    LabeledContent("Contexte", value: "\(model.contextLength) tokens")
                    LabeledContent("Runtime", value: templateLabel)
                }
                Section {
                    LabeledContent("Fournisseur", value: model.provider)
                    LabeledContent("Licence", value: model.license)
                    LabeledContent("Fichier", value: model.filename)
                    if let mmproj = model.mmproj {
                        LabeledContent("Projecteur", value: mmproj.filename)
                        LabeledContent("SHA256 mmproj", value: mmproj.sha256 ?? "—")
                    }
                    if let sha = model.sha256 {
                        LabeledContent("SHA256", value: sha)
                    }
                } header: {
                    Text("Fichiers")
                }
                if !model.compatibilityNote.isEmpty {
                    Section {
                        Text(model.compatibilityNote)
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.mutedForeground)
                    } header: {
                        Text("Compatibilité")
                    }
                }
                if model.id == "qwen35-2b-q4_k_m" || model.id == "gemma4-e2b-it-q4_0" {
                    Section {
                        Button("Comparer les modèles") {
                            showComparison = true
                        }
                    }
                }
            }
            .navigationTitle("Détails du modèle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .sheet(isPresented: $showComparison) {
                LocalModelComparisonSheet()
            }
        }
    }

    private var templateLabel: String {
        switch model.runtimeProfile.templateKind {
        case .chatml: return "ChatML"
        case .gemma: return "Gemma"
        case .gemma4: return "Gemma 4"
        case .granite: return "Granite"
        case .phi: return "Phi"
        case .generic: return "Générique"
        }
    }
}

struct LocalAIVisionManageSheet: View {
    let model: LocalModelDescriptor
    let mutationsDisabled: Bool
    let onInstall: () -> Void
    let onRemove: () -> Void

    @ObservedObject private var models = LocalModelManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Modèle", value: model.displayName)
                    if let size = model.userFacingVisionSizeLabel {
                        LabeledContent("Taille", value: size)
                    }
                    HStack {
                        Text("État")
                        Spacer()
                        if models.isInstallingVision(model) {
                            LocalAIStatusMark(kind: .downloading)
                        } else if models.isVisionProjectorInstalled(model) {
                            Text("Installée")
                                .foregroundStyle(AppTheme.accent)
                                .font(CNFont.callout.weight(.semibold))
                        } else {
                            Text("Disponible")
                                .foregroundStyle(AppTheme.mutedForeground)
                        }
                    }
                    if models.isInstallingVision(model) {
                        ProgressView(value: models.visionProjectorProgress)
                            .tint(AppTheme.accent)
                        Text("\(Int((models.visionProjectorProgress * 100).rounded())) %")
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.mutedForeground)
                    }
                } footer: {
                    if model.requiresCompanionVisionToLoad {
                        Text("Sans ce projecteur, « \(model.displayName) » ne peut pas être chargé. La vision ne change pas le modèle déjà en mémoire.")
                    } else {
                        Text("La vision appartient à ce modèle. Elle ne change pas le modèle chargé.")
                    }
                }

                Section {
                    if models.isInstallingVision(model) {
                        Button("Annuler", role: .cancel) {
                            models.cancelDownload()
                        }
                    } else if models.isVisionProjectorInstalled(model) {
                        Button("Retirer la vision", role: .destructive) {
                            confirmRemove = true
                        }
                        .disabled(mutationsDisabled || models.visionProjectorBusy)
                    } else {
                        Button("Installer la vision") {
                            onInstall()
                        }
                        .disabled(mutationsDisabled || models.visionProjectorBusy || models.textInstallBusy)
                    }
                }
            }
            .navigationTitle("Vision")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .confirmationDialog(
                "Retirer la vision ?",
                isPresented: $confirmRemove,
                titleVisibility: .visible
            ) {
                Button("Retirer", role: .destructive, action: onRemove)
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Le projecteur vision sera supprimé. Le modèle texte reste installé.")
            }
        }
    }
}

struct LocalAITechnicalErrorSheet: View {
    let message: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(message)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(AppTheme.background)
            .navigationTitle("Détails de l’erreur")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }
}
