import SwiftUI

/// Une seule présentation pour tout l’IA locale.
/// Plusieurs `.sheet` empilés sur un `Section` de `List` font dismiss SwiftUI
/// la feuille Tester dès le premier layout (sans `dismiss()` métier).
enum LocalAISettingsSheetItem: Identifiable, Equatable {
    case inferenceTest
    case modelDetails(LocalModelDescriptor)
    case visionManage(LocalModelDescriptor)
    case technicalError(String)

    var id: String {
        switch self {
        case .inferenceTest:
            return "local-ai.inference-test"
        case .modelDetails(let model):
            return "local-ai.details.\(model.id)"
        case .visionManage(let model):
            return "local-ai.vision.\(model.id)"
        case .technicalError:
            return "local-ai.technical-error"
        }
    }
}

enum LocalModelTestUILog {
    static func event(_ name: String, extra: String = "") {
        if extra.isEmpty {
            print("[test-ui] \(name)")
        } else {
            print("[test-ui] \(name) \(extra)")
        }
    }

    static func dismissRequested(caller: String, running: Bool, extra: String = "") {
        var parts = ["caller=\(caller)", "running=\(running)"]
        if !extra.isEmpty { parts.append(extra) }
        event("dismiss requested", extra: parts.joined(separator: " "))
        event("TEST_SHEET_DISMISS_REQUESTED", extra: "caller=\(caller)")
    }
}

enum LocalModelTestFormat {
    static func seconds(fromMs ms: Double?) -> String {
        guard let ms else { return "—" }
        return number(ms / 1000.0, digits: 2) + " s"
    }

    static func tokensPerSecond(_ value: Double?) -> String {
        guard let value else { return "—" }
        return number(value, digits: 1) + " tok/s"
    }

    static func number(_ value: Double, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(digits)f", value)
    }
}

struct LocalAISettingsPresentedContent: View {
    let item: LocalAISettingsSheetItem

    var body: some View {
        switch item {
        case .inferenceTest:
            LocalModelTestSheet()
                .id(LocalAISettingsSheetItem.inferenceTest.id)
        case .modelDetails(let model):
            LocalAIModelDetailsSheet(model: model)
        case .visionManage(let model):
            LocalAIVisionManageSheet(
                model: model,
                mutationsDisabled: visionMutationsDisabled,
                onInstall: {
                    Task { await LocalModelManager.shared.installVisionProjector(for: model) }
                },
                onRemove: {
                    Task { await LocalModelManager.shared.deleteVisionProjector(for: model) }
                }
            )
        case .technicalError(let message):
            LocalAITechnicalErrorSheet(message: message)
        }
    }

    private var visionMutationsDisabled: Bool {
        let models = LocalModelManager.shared
        return !LocalAISettingsActionGate.allowsNewMutationTask(
            busyAction: false,
            exclusiveOperation: models.exclusiveOperation,
            state: models.state
        )
    }
}
