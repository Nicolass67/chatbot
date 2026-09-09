import SwiftUI
import UIKit
import MessageUI

/// Partage / envoi mail **local** — aucun appel PC.
enum NativeMailShare {
    @MainActor
    static func present(
        fileURLs: [URL],
        subject: String? = nil,
        body: String? = nil,
        to: [String] = []
    ) {
        let urls = fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
        let tooLargeForComposer = urls.contains { url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return size > 12_000_000
        }
        if !tooLargeForComposer, MFMailComposeViewController.canSendMail(), let presenter = topViewController() {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = MailComposeRelayer.shared
            if let subject, !subject.isEmpty { mail.setSubject(subject) }
            if let body, !body.isEmpty { mail.setMessageBody(body, isHTML: false) }
            if !to.isEmpty { mail.setToRecipients(to) }
            for url in urls {
                let data = (try? Data(contentsOf: url)) ?? Data()
                let mime = LocalFileTypeDetector.mimeType(for: url)
                mail.addAttachmentData(data, mimeType: mime, fileName: url.lastPathComponent)
            }
            presenter.present(mail, animated: true)
            return
        }
        if urls.count == 1, let url = urls.first {
            NativeShare.present(url: url, title: subject)
            return
        }
        NativeShare.presentItems(urls)
    }

    @MainActor
    static func presentComposer(to: String?, subject: String, body: String) {
        if MFMailComposeViewController.canSendMail(), let presenter = topViewController() {
            let mail = MFMailComposeViewController()
            mail.mailComposeDelegate = MailComposeRelayer.shared
            if let to, !to.isEmpty {
                mail.setToRecipients(to.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            }
            mail.setSubject(subject)
            mail.setMessageBody(body, isHTML: false)
            presenter.present(mail, animated: true)
            return
        }
        var lines = [subject, body]
        if let to, !to.isEmpty { lines.insert("À : \(to)", at: 0) }
        NativeShare.presentText(lines.filter { !$0.isEmpty }.joined(separator: "\n\n"))
    }

    @MainActor
    private static func topViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}

@MainActor
final class MailComposeRelayer: NSObject, MFMailComposeViewControllerDelegate {
    static let shared = MailComposeRelayer()

    func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?
    ) {
        controller.dismiss(animated: true)
    }
}

extension NativeShare {
    @MainActor
    static func presentItems(_ items: [Any]) {
        let activity = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let presenter = topPresenter() else { return }
        if let pop = activity.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
            pop.permittedArrowDirections = []
        }
        presenter.present(activity, animated: true)
    }

    @MainActor
    static func presentText(_ text: String) {
        presentItems([text])
    }

    @MainActor
    fileprivate static func topPresenter() -> UIViewController? {
        let base = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
        return unwrap(base)
    }

    @MainActor
    private static func unwrap(_ base: UIViewController?) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return unwrap(nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return unwrap(tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return unwrap(presented)
        }
        return base
    }
}
