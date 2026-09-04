import SwiftUI
import QuickLook

/// Quick Look pour documents locaux (PDF, etc.).
struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    var onDismiss: (() -> Void)?

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, onDismiss: onDismiss)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource, @preconcurrency QLPreviewControllerDelegate, @unchecked Sendable {
        var url: URL
        private var dismissHandler: (() -> Void)?

        init(url: URL, onDismiss: (() -> Void)?) {
            self.url = url
            self.dismissHandler = onDismiss
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }

        func previewControllerDidDismiss(_ controller: QLPreviewController) {
            let handler = dismissHandler
            DispatchQueue.main.async {
                handler?()
            }
        }
    }
}

@MainActor
enum AttachmentFileCache {
    static func localURL(
        attachmentId: String,
        filename: String,
        baseURL: URL,
        token: String?
    ) async throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ql-attachments", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safe = filename.replacingOccurrences(of: "/", with: "_")
        let dest = dir.appendingPathComponent("\(attachmentId)-\(safe)")
        if FileManager.default.fileExists(atPath: dest.path) {
            return dest
        }
        var components = URLComponents(url: baseURL.appendingPathComponent("api/attachments/\(attachmentId)"), resolvingAgainstBaseURL: false)!
        components.queryItems = nil
        var req = URLRequest(url: components.url!)
        req.setValue("ios", forHTTPHeaderField: "X-Client")
        req.setValue("3.0.0", forHTTPHeaderField: "X-App-Version")
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw APIClientError.http(http.statusCode, "Download failed")
        }
        try data.write(to: dest, options: .atomic)
        return dest
    }
}
