import SwiftUI

/// Bannière compacte — uniquement si un service contextuel a un problème confirmé.
struct ServiceStatusBanner: View {
    let title: String
    let detail: String?
    let serviceId: String?
    var repairing: Bool = false
    var onRepair: (() -> Void)?

    @Environment(\.themeRevision) private var themeRevision

    var body: some View {
        let _ = themeRevision
        HStack(alignment: .center, spacing: AppTheme.space10) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(AppTheme.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CNFont.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.foreground)
                    .lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(CNFont.caption2)
                        .foregroundStyle(AppTheme.muted)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            if let onRepair {
                Button {
                    AppHaptics.light()
                    onRepair()
                } label: {
                    if repairing {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(minWidth: 56)
                    } else {
                        Text(actionLabel)
                            .font(CNFont.caption.weight(.semibold))
                    }
                }
                .foregroundStyle(AppTheme.accent)
                .disabled(repairing)
                .accessibilityLabel(repairA11yLabel)
                .accessibilityHint(actionHint)
            }
        }
        .padding(.horizontal, AppTheme.space12)
        .padding(.vertical, AppTheme.space10)
        .background(AppTheme.surfaceElevated.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(bannerA11yLabel)
    }

    private var bannerA11yLabel: String {
        if let detail, !detail.isEmpty {
            return "\(title). \(detail)"
        }
        return title
    }

    private var actionLabel: String {
        serviceId == nil && title.localizedCaseInsensitiveContains("hors ligne")
            ? "Allumer"
            : "Réparer"
    }

    private var actionHint: String {
        actionLabel == "Allumer"
            ? "Envoie un signal de réveil au PC"
            : "Tente de rétablir le service"
    }

    private var repairA11yLabel: String {
        if actionLabel == "Allumer" { return "Allumer le PC" }
        if let serviceId, !serviceId.isEmpty {
            return "Réparer le service \(serviceId)"
        }
        return "Réparer"
    }
}

extension ServiceStatusBanner {
    /// Chat : assistant / recherche — seulement après confirmation (pas pendant healthcheck).
    static func chatContext(
        infra: InfrastructureStore,
        onRepair: @escaping (String) -> Void
    ) -> ServiceStatusBanner? {
        // Force SwiftUI à recalculer après la fenêtre de grâce.
        let _ = infra.alertEpoch
        guard infra.canSurfaceServiceAlerts else { return nil }

        let assistantDown = infra.shouldSurfaceBanner(forServiceId: InfrastructureServiceID.assistant)
        let searchDown = infra.shouldSurfaceBanner(forServiceId: InfrastructureServiceID.webSearch)
        guard assistantDown || searchDown else { return nil }

        if assistantDown && searchDown {
            return ServiceStatusBanner(
                title: "Assistant et recherche indisponibles",
                detail: "Tu peux tenter une réparation depuis ici.",
                serviceId: InfrastructureServiceID.assistant,
                repairing: infra.repairing,
                onRepair: { onRepair(InfrastructureServiceID.assistant) }
            )
        }
        if assistantDown {
            return ServiceStatusBanner(
                title: "Assistant indisponible",
                detail: infra.status?.service(id: InfrastructureServiceID.assistant)?.summary,
                serviceId: InfrastructureServiceID.assistant,
                repairing: infra.repairing,
                onRepair: { onRepair(InfrastructureServiceID.assistant) }
            )
        }
        return ServiceStatusBanner(
            title: "Recherche web indisponible",
            detail: infra.status?.service(id: InfrastructureServiceID.webSearch)?.summary,
            serviceId: InfrastructureServiceID.webSearch,
            repairing: infra.repairing,
            onRepair: { onRepair(InfrastructureServiceID.webSearch) }
        )
    }

    /// Mail / Files : PC hors ligne confirmé, ou backend Chatbot confirmé down.
    static func backendContext(
        infra: InfrastructureStore,
        surface: String,
        onRepair: @escaping (String) -> Void,
        onWake: (() -> Void)? = nil
    ) -> ServiceStatusBanner? {
        let _ = infra.alertEpoch
        guard infra.canSurfaceServiceAlerts else { return nil }

        if infra.isPcConfirmedOffline {
            return ServiceStatusBanner(
                title: "PC hors ligne",
                detail: "\(surface) nécessite que le PC soit allumé.",
                serviceId: nil,
                repairing: infra.repairing,
                onRepair: onWake
            )
        }
        guard infra.shouldSurfaceBanner(forServiceId: InfrastructureServiceID.chatbot) else { return nil }
        return ServiceStatusBanner(
            title: "Serveur indisponible",
            detail: "\(surface) ne peut pas joindre Chatbot.",
            serviceId: InfrastructureServiceID.chatbot,
            repairing: infra.repairing,
            onRepair: { onRepair(InfrastructureServiceID.chatbot) }
        )
    }
}
