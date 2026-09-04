import SwiftUI
import WebKit
import UIKit

/// Rendu HTML mail — contraste forcé (P1b), hauteur dynamique, liens externes.
struct MailHtmlView: UIViewRepresentable {
    let html: String
    @Binding var measuredHeight: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = context.coordinator
        web.setContentHuggingPriority(.defaultLow, for: .vertical)
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.heightBinding = $measuredHeight
        if context.coordinator.lastHtml != html {
            context.coordinator.lastHtml = html
            webView.loadHTMLString(Self.wrap(html), baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHtml: String?
        var heightBinding: Binding<CGFloat>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            remasure(webView)
            // Images / CSS tardifs
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.remasure(webView)
            }
        }

        private func remasure(_ webView: WKWebView) {
            let js = """
            (function(){
              var s=document.getElementById('cn-force');
              if(!s){
                s=document.createElement('style');
                s.id='cn-force';
                s.textContent='html,body,*{color:#f2f2f7!important;background:transparent!important;background-color:transparent!important;}a{color:#8ec7ff!important;}img{max-width:100%!important;height:auto!important;}';
                document.head.appendChild(s);
              }
              document.querySelectorAll('[style]').forEach(function(el){
                el.style.setProperty('color','#f2f2f7','important');
                el.style.setProperty('background','transparent','important');
                el.style.setProperty('background-color','transparent','important');
              });
              return Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, 120);
            })();
            """
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                let height = (result as? CGFloat)
                    ?? (result as? Double).map { CGFloat($0) }
                    ?? 220
                let clamped = max(120, min(height + 12, 4000))
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

    /// Neutralise couleurs illisibles sans détruire la structure (tables Gmail / spacers).
    private static func sanitize(_ html: String) -> String {
        var s = html
        // Retirer uniquement les <style> embbedés qui forcent fond clair + texte sombre
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
        // bgcolor → transparent
        if let regex = try? NSRegularExpression(
            pattern: "\\sbgcolor\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
            options: [.caseInsensitive]
        ) {
            s = regex.stringByReplacingMatches(
                in: s,
                options: [],
                range: NSRange(s.startIndex..., in: s),
                withTemplate: ""
            )
        }
        return s
    }

    private static func wrap(_ html: String) -> String {
        let body = sanitize(html)
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <meta name="color-scheme" content="dark">
        <base target="_blank" rel="noopener noreferrer">
        <style id="cn-base">
        html,body{margin:0;padding:0;background:transparent!important;color:#e8e8ec!important;
        font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif;font-size:17px;line-height:1.55;
        width:100%;max-width:100%;overflow-x:hidden;overflow-wrap:anywhere;word-break:break-word;-webkit-text-size-adjust:100%;}
        /* Ne pas forcer width:100% sur tous les td — casse les spacers Gmail (décalage droite). */
        body > table{width:100%!important;max-width:100%!important;margin-left:auto!important;margin-right:auto!important;}
        body > div, body > center{max-width:100%!important;margin-left:auto!important;margin-right:auto!important;}
        img{max-width:100%!important;height:auto!important}
        table{max-width:100%!important;border-collapse:collapse}
        td,th{word-break:break-word}
        a{color:#7EB8C4!important}
        pre,code{white-space:pre-wrap;word-break:break-word}
        blockquote{margin:0;padding-left:12px;border-left:3px solid #7EB8C4;color:#c8c8d0!important}
        </style></head><body>\(body)</body></html>
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
                .stroke(AppTheme.accent.opacity(0.3), lineWidth: 1)
        )
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
                .foregroundStyle(AppTheme.warning)
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
                .stroke(AppTheme.warning.opacity(0.45), lineWidth: 1)
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
