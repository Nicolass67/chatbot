import CoreGraphics
import Foundation

/// Règles de scroll du fil — testables sans SwiftUI.
enum ChatScrollPolicy {
    /// Slack sous le contenu : chrome composer, pas un viewport entier dès qu’Agent/stream grandit.
    static func bottomSlack(
        isSending: Bool,
        pinToTopActive: Bool,
        agentOrStreamActive: Bool,
        chromePadding: CGFloat,
        viewportHeight: CGFloat
    ) -> CGFloat {
        let chrome = max(chromePadding, 0)
        guard isSending, pinToTopActive, !agentOrStreamActive, viewportHeight > 80 else {
            return chrome
        }
        return max(chrome, viewportHeight - 12)
    }

    /// Suivre le bas seulement si l’utilisateur n’a pas remonté volontairement.
    static func shouldFollowNewContent(
        userReleasedAutoScroll: Bool,
        pinToTopActive: Bool
    ) -> Bool {
        !userReleasedAutoScroll && !pinToTopActive
    }
}
