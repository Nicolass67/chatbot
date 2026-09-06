import SwiftUI

/// Écran Réglages — état système (PC, services, actions, incidents).
/// Soft / premium ; pas de chrome DevOps.
struct SystemStatusView: View {
    @EnvironmentObject private var infra: InfrastructureStore
    @Environment(\.themeRevision) private var themeRevision

    @State private var confirmShutdown = false
    @State private var confirmRestart = false
    @State private var techExpanded = false

    var body: some View {
        let _ = themeRevision
        ZStack {
            AmbientBackground()
            List {
                overallSection
                powerSection
                servicesSection
                actionsSection
                if !infra.incidents.isEmpty {
                    incidentsSection
                }
                technicalSection
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("État du système")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier(A11yID.Settings.systemStatus)
        .task { await infra.refresh() }
        .refreshable { await infra.refresh() }
        .alert("Éteindre le PC ?", isPresented: $confirmShutdown) {
            Button("Annuler", role: .cancel) {}
            Button("Éteindre", role: .destructive) {
                Task { await infra.shutdown() }
            }
        } message: {
            Text("Le PC s’éteindra dans environ 60 secondes. Sur le PC : shutdown /a pour annuler.")
        }
        .alert("Redémarrer le PC ?", isPresented: $confirmRestart) {
            Button("Annuler", role: .cancel) {}
            Button("Redémarrer", role: .destructive) {
                Task { await infra.restart() }
            }
        } message: {
            Text("Le PC redémarrera dans environ 30 secondes.")
        }
    }

    // MARK: - Sections

    private var overallSection: some View {
        Section {
            HStack(alignment: .top, spacing: AppTheme.space12) {
                overallGlyph
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppTheme.space4) {
                    Text(infra.overallState.frenchLabel)
                        .font(CNFont.headline)
                        .foregroundStyle(AppTheme.foreground)
                    if let message = infra.status?.message, !message.isEmpty {
                        Text(message)
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let last = infra.lastRefresh {
                        Text("Mis à jour \(relativeTime(last))")
                            .font(CNFont.caption2)
                            .foregroundStyle(AppTheme.mutedForeground)
                    }
                }
                Spacer(minLength: 0)
                if infra.loading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Actualisation en cours")
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(overallA11yLabel)

            if let err = infra.errorMessage {
                SoftErrorBanner(message: err, retryTitle: "Réessayer") {
                    infra.clearError()
                    Task { await infra.refresh() }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
            }

            if let note = infra.lastRepairMessage, !note.isEmpty {
                Text(note)
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        } header: {
            Text("Résumé")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var powerSection: some View {
        Section {
            HStack(spacing: AppTheme.space12) {
                Image(systemName: powerIcon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(powerColor)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ordinateur")
                        .font(CNFont.body.weight(.medium))
                        .foregroundStyle(AppTheme.foreground)
                    Text(infra.status?.powerState.frenchLabel ?? "Inconnu")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                }
                Spacer()
                Text(infra.isPcOnline ? "En ligne" : "Hors ligne")
                    .font(CNFont.caption.weight(.semibold))
                    .foregroundStyle(powerColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(powerColor.opacity(0.12))
                    .clipShape(Capsule())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Ordinateur : \(infra.status?.powerState.frenchLabel ?? "état inconnu")")
        } header: {
            Text("Alimentation")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var servicesSection: some View {
        Section {
            if let services = infra.status?.services, !services.isEmpty {
                ForEach(services) { service in
                    serviceRow(service)
                }
            } else if infra.loading {
                HStack(spacing: AppTheme.space8) {
                    ProgressView().controlSize(.small)
                    Text("Chargement des services…")
                        .font(CNFont.caption)
                        .foregroundStyle(AppTheme.muted)
                }
            } else {
                Text("Aucun service signalé pour le moment.")
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.muted)
            }
        } header: {
            Text("Services")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var actionsSection: some View {
        Section {
            Button {
                AppHaptics.medium()
                Task { await infra.diagnoseAndRepair() }
            } label: {
                Label {
                    Text(infra.repairing ? "Réparation…" : "Diagnostiquer et réparer")
                } icon: {
                    if infra.repairing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "wrench.and.screwdriver")
                    }
                }
            }
            .disabled(infra.repairing || infra.loading)
            .foregroundStyle(AppTheme.accent)
            .accessibilityHint("Analyse l’état puis tente une réparation minimale")

            Button {
                AppHaptics.light()
                Task { await infra.wake() }
            } label: {
                Label("Allumer", systemImage: "power.circle")
            }
            .disabled(infra.repairing)
            .foregroundStyle(AppTheme.foreground)
            .accessibilityHint("Envoie un signal de réveil au PC")

            Button {
                AppHaptics.light()
                Task { await infra.startServices() }
            } label: {
                Label("Démarrer les services", systemImage: "play.circle")
            }
            .disabled(infra.repairing)
            .foregroundStyle(AppTheme.foreground)
            .accessibilityHint("Lance la stack Chatbot si le PC est déjà allumé")

            Button {
                AppHaptics.light()
                Task { await infra.restartServices() }
            } label: {
                Label("Relancer les services", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(infra.repairing)
            .foregroundStyle(AppTheme.foreground)
            .accessibilityHint("Arrête puis relance la stack Chatbot")

            Button {
                confirmRestart = true
            } label: {
                Label("Redémarrer le PC", systemImage: "arrow.clockwise")
            }
            .disabled(infra.repairing)
            .foregroundStyle(AppTheme.foreground)
            .accessibilityHint("Planifie un redémarrage du PC")

            Button(role: .destructive) {
                confirmShutdown = true
            } label: {
                Label("Éteindre", systemImage: "power")
            }
            .disabled(infra.repairing)
            .accessibilityIdentifier(A11yID.Settings.shutdownPc)
            .accessibilityHint("Planifie l’extinction du PC après confirmation")
        } header: {
            Text("Actions")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var incidentsSection: some View {
        Section {
            ForEach(infra.incidents.prefix(8)) { incident in
                VStack(alignment: .leading, spacing: AppTheme.space4) {
                    HStack {
                        Text(incidentTitle(incident))
                            .font(CNFont.body.weight(.medium))
                            .foregroundStyle(AppTheme.foreground)
                        Spacer()
                        Text(incident.isOpen ? "Ouvert" : "Résolu")
                            .font(CNFont.caption2.weight(.semibold))
                            .foregroundStyle(incident.isOpen ? AppTheme.warning : AppTheme.success)
                    }
                    if !incident.diagnosis.isEmpty {
                        Text(incident.diagnosis)
                            .font(CNFont.caption)
                            .foregroundStyle(AppTheme.muted)
                            .lineLimit(3)
                    }
                    if !incident.detectedAt.isEmpty {
                        Text(AppDates.friendly(incident.detectedAt))
                            .font(CNFont.caption2)
                            .foregroundStyle(AppTheme.mutedForeground)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(incidentA11y(incident))
            }
        } header: {
            Text("Incidents récents")
        }
        .listRowBackground(AppTheme.surface)
    }

    private var technicalSection: some View {
        Section {
            DisclosureGroup(isExpanded: $techExpanded) {
                LabeledContent("État global", value: infra.overallState.rawValue)
                LabeledContent("Alimentation", value: infra.status?.powerState.rawValue ?? "—")
                LabeledContent(
                    "Supervisor",
                    value: (infra.status?.supervisorAlive == true) ? "actif" : "inactif"
                )
                if let repairId = infra.status?.activeRepairId, !repairId.isEmpty {
                    LabeledContent("Réparation", value: repairId)
                }
                if let generated = infra.status?.generatedAt, !generated.isEmpty {
                    LabeledContent("Snapshot", value: AppDates.short(generated))
                }
            } label: {
                Text("Détails techniques")
                    .font(CNFont.caption.weight(.medium))
                    .foregroundStyle(AppTheme.muted)
            }
            .tint(AppTheme.muted)
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: - Rows

    private func serviceRow(_ service: ServiceStatusDTO) -> some View {
        HStack(alignment: .center, spacing: AppTheme.space12) {
            Circle()
                .fill(availabilityColor(service.availability))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.preferredName)
                    .font(CNFont.body.weight(.medium))
                    .foregroundStyle(AppTheme.foreground)
                Text(serviceSummaryLine(service))
                    .font(CNFont.caption)
                    .foregroundStyle(AppTheme.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(service.availability.frenchLabel)
                .font(CNFont.caption2.weight(.semibold))
                .foregroundStyle(availabilityColor(service.availability))
                .accessibilityHidden(true)
            if service.availability.needsAttention {
                Button {
                    AppHaptics.light()
                    Task { await infra.repairService(id: service.id) }
                } label: {
                    Text("Réparer")
                        .font(CNFont.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
                .disabled(infra.repairing)
                .accessibilityLabel("Réparer \(service.preferredName)")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(service.preferredName), \(service.availability.frenchLabel)")
        .accessibilityHint(service.summary.isEmpty ? "" : service.summary)
    }

    // MARK: - Visual helpers

    private var overallGlyph: some View {
        Image(systemName: overallIcon)
            .font(.title3.weight(.semibold))
            .foregroundStyle(overallColor)
            .frame(width: 36, height: 36)
            .background(overallColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusSm, style: .continuous))
    }

    private var overallIcon: String {
        switch infra.overallState {
        case .healthy: return "checkmark.seal.fill"
        case .degraded, .recovering: return "exclamationmark.circle.fill"
        case .offline, .error, .unknown: return "xmark.octagon.fill"
        }
    }

    private var overallColor: Color {
        switch infra.overallState {
        case .healthy: return AppTheme.success
        case .degraded, .recovering: return AppTheme.warning
        case .offline, .error, .unknown: return AppTheme.danger
        }
    }

    private var powerIcon: String {
        infra.isPcOnline ? "desktopcomputer" : "desktopcomputer.and.arrow.down"
    }

    private var powerColor: Color {
        infra.isPcOnline ? AppTheme.success : AppTheme.danger
    }

    private func availabilityColor(_ a: ServiceAvailability) -> Color {
        switch a {
        case .available: return AppTheme.success
        case .degraded: return AppTheme.warning
        case .unavailable: return AppTheme.danger
        case .unknown: return AppTheme.mutedForeground
        }
    }

    private func serviceSummaryLine(_ service: ServiceStatusDTO) -> String {
        let summary = service.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summary.isEmpty { return summary }
        return service.availability.frenchLabel
    }

    private func incidentTitle(_ incident: IncidentDTO) -> String {
        if let service = infra.status?.service(id: incident.serviceId) {
            return service.preferredName
        }
        if !incident.serviceId.isEmpty { return incident.serviceId }
        return "Incident"
    }

    private var overallA11yLabel: String {
        var parts = [infra.overallState.frenchLabel]
        if let message = infra.status?.message, !message.isEmpty {
            parts.append(message)
        }
        return parts.joined(separator: ". ")
    }

    private func incidentA11y(_ incident: IncidentDTO) -> String {
        let state = incident.isOpen ? "ouvert" : "résolu"
        return "\(incidentTitle(incident)), \(state). \(incident.diagnosis)"
    }

    private func relativeTime(_ date: Date) -> String {
        let rel = RelativeDateTimeFormatter()
        rel.locale = Locale(identifier: "fr_FR")
        rel.unitsStyle = .short
        return rel.localizedString(for: date, relativeTo: Date())
    }
}
