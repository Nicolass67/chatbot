import SwiftUI
import WebKit
import UIKit

/// Rendu HTML mail — contraste forcé (P1b), hauteur dynamique, liens externes.
struct MailHtmlView: UIViewRepresentable {
    let html: String
    @Binding var measuredHeight: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = true
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.contentInset = .zero
        web.scrollView.scrollIndicatorInsets = .zero
        web.navigationDelegate = context.coordinator
        web.setContentHuggingPriority(.defaultLow, for: .vertical)
        web.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.heightBinding = $measuredHeight
        let width = webView.bounds.width
        let dark = colorScheme == .dark
        let needsReload =
            context.coordinator.lastHtml != html
            || context.coordinator.lastDark != dark
            || (width > 1 && abs(context.coordinator.lastWidth - width) > 1)
        if needsReload {
            context.coordinator.lastHtml = html
            context.coordinator.lastWidth = width
            context.coordinator.lastDark = dark
            webView.loadHTMLString(Self.wrap(html, dark: dark), baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHtml: String?
        var lastWidth: CGFloat = 0
        var lastDark: Bool?
        var heightBinding: Binding<CGFloat>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            remasure(webView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.remasure(webView)
            }
        }

        private func remasure(_ webView: WKWebView) {
            let js = """
            (function(){
              var b=document.body;
              if(!b) return 160;
              b.style.margin='0';
              b.style.padding='0';
              b.style.width='100%';
              b.style.maxWidth='100%';
              b.style.boxSizing='border-box';
              var tables=b.querySelectorAll('table');
              for(var i=0;i<tables.length;i++){
                var t=tables[i];
                t.style.maxWidth='100%';
                t.style.marginLeft='0';
                t.style.marginRight='0';
                if(t.parentElement===b || (t.parentElement && t.parentElement.id==='cn-mail-root')){
                  t.style.width='100%';
                }
              }
              return Math.max(b.scrollHeight, document.documentElement.scrollHeight, 160);
            })();
            """
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                let height = (result as? CGFloat)
                    ?? (result as? Double).map { CGFloat($0) }
                    ?? 240
                let clamped = max(160, min(height + 8, 4000))
                DispatchQueue.main.async {
                    self?.heightBinding?.wrappedValue = clamped
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    private static func sanitize(_ html: String) -> String {
        var s = html
        if let regex = try? NSRegularExpression(
            pattern: "<body[^>]*>([\\s\\S]*?)</body>",
            options: [.caseInsensitive]
        ),
           let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let range = Range(match.range(at: 1), in: s) {
            s = String(s[range])
        }
        s = s.replacingOccurrences(of: #"(?i)</?html[^>]*>"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?i)</?head[^>]*>"#, with: "", options: .regularExpression)
        if let regex = try? NSRegularExpression(
            pattern: "<style[^>]*>[\\s\\S]*?</style>",
            options: [.caseInsensitive]
        ) {
            s = regex.stringByReplacingMatches(
                in: s,
                options: [],
                range: NSRange(s.startIndex..., in: s),
                withTemplate: ""
            )
        }
        if let regex = try? NSRegularExpression(
            pattern: "\\s(bgcolor|color|background|text)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
            options: [.caseInsensitive]
        ) {
            s = regex.stringByReplacingMatches(
                in: s,
                options: [],
                range: NSRange(s.startIndex..., in: s),
                withTemplate: ""
            )
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wrap(_ html: String, dark: Bool) -> String {
        let body = sanitize(html)
        let bg = dark ? "#18181a" : "#F4F4F5"
        let fg = dark ? "#e2e2e6" : "#1a1a1e"
        let link = dark ? "#7eb8c4" : "#5a9aa6"
        let muted = dark ? "#a3a3aa" : "#5c5c66"
        let quote = dark ? "#7eb8c4" : "#5a9aa6"
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,viewport-fit=cover">
        <base target="_blank" rel="noopener noreferrer">
        <style id="cn-base">
        *,*::before,*::after{box-sizing:border-box;}
        html{margin:0;padding:0;width:100%;max-width:100%;overflow-x:hidden;-webkit-text-size-adjust:100%;}
        body{margin:0;padding:0;width:100%;max-width:100%;
        background:\(bg)!important;color:\(fg)!important;
        font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif;font-size:17px;line-height:1.55;
        overflow-x:hidden;overflow-wrap:anywhere;word-break:break-word;text-align:left;}
        #cn-mail-root{display:block;width:100%;max-width:100%;margin:0;padding:0;text-align:left;}
        #cn-mail-root > table{width:100%!important;max-width:100%!important;margin:0!important;}
        #cn-mail-root > center,#cn-mail-root > div{max-width:100%!important;margin:0!important;}
        img{max-width:100%!important;height:auto!important}
        table{max-width:100%!important;border-collapse:collapse}
        td,th{word-break:break-word}
        a,a *{color:\(link)!important}
        pre,code{white-space:pre-wrap;word-break:break-word}
        blockquote{margin:0;padding-left:12px;border-left:3px solid \(quote);color:\(muted)!important}
        </style></head><body><div id="cn-mail-root">\(body)</div></body></html>
        """
    }
}

struct MemorySavedNotice: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(AppTheme.accent)
            Text(text)
                .font(.caption)
                .foregroundStyle(AppTheme.foreground)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.mutedForeground)
            }
        }
        .padding(12)
        .background(AppTheme.accentSubtle)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 0.5)
        )
    }
}

/// Chip discret au-dessus d'une réponse assistant (style ChatGPT).
struct MemoryUpdatedChip: View {
    let memory: SavedMemoryChipDTO
    var onOpen: (() -> Void)? = nil
    var onForget: (() -> Void)? = nil

    @State private var confirmingForget = false

    var body: some View {
        Group {
            if confirmingForget {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Oublier ce souvenir ?")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.foreground)
                    Text(memory.content)
                        .font(.caption2)
                        .foregroundStyle(AppTheme.mutedForeground)
                        .lineLimit(3)
                    HStack(spacing: 10) {
                        Button("Oublier") {
                            confirmingForget = false
                            onForget?()
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                        Button("Garder") {
                            confirmingForget = false
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppTheme.mutedForeground)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(AppTheme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous)
                        .stroke(AppTheme.borderSubtle, lineWidth: 0.5)
                )
            } else {
                Button {
                    onOpen?()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                        Text("Mémoire mise à jour")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.foreground)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.mutedForeground)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.accentSubtle.opacity(0.85))
                    .clipShape(Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(AppTheme.borderSubtle, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mémoire mise à jour")
                .accessibilityHint(memory.content)
                .contextMenu {
                    Button("Voir le souvenir", systemImage: "brain.head.profile") {
                        onOpen?()
                    }
                    if onForget != nil {
                        Button("Oublier…", systemImage: "trash", role: .destructive) {
                            confirmingForget = true
                        }
                    }
                }
            }
        }
        .accessibilityLabel("Mémoire mise à jour: \(memory.content)")
    }
}

struct FileActionPendingCard: View {
    let op: String
    let detail: String
    let expiresAt: String?
    let confirming: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Action fichiers en attente", systemImage: "exclamationmark.shield")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.foreground)
            Text(opLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(AppTheme.foreground)
            Text(detail)
                .font(.caption)
                .foregroundStyle(AppTheme.muted)
                .lineLimit(3)
            if let expiresAt {
                Text("Expire : \(expiresAt)")
                    .font(.caption2)
                    .foregroundStyle(AppTheme.mutedForeground)
            }
            HStack {
                Button(action: onCancel) {
                    Text("Annuler")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .background(AppTheme.surfaceHover)
                        .foregroundStyle(AppTheme.foreground)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                }
                Button(action: onConfirm) {
                    HStack {
                        if confirming { ProgressView().controlSize(.mini).tint(.white) }
                        Text("Confirmer")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 40)
                    .background(AppTheme.accent)
                    .foregroundStyle(AppTheme.accentForeground)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusMd, style: .continuous))
                }
                .disabled(confirming)
            }
        }
        .padding(14)
        .background(AppTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.radiusLg, style: .continuous)
                .stroke(AppTheme.borderSubtle, lineWidth: 0.5)
        )
    }

    private var opLabel: String {
        switch op {
        case "create_directory": return "Créer un dossier"
        case "rename_file": return "Renommer"
        case "move_file": return "Déplacer"
        default: return op
        }
    }
}
