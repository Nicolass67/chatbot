import SwiftUI
import WidgetKit

@main
struct ChatbotWidgetsBundle: WidgetBundle {
    var body: some Widget {
        AssistantStatusWidget()
        MailUnreadWidget()
        FilesRecentWidget()
    }
}
