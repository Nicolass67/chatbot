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
        // Fond opaque sombre : évite WKWebView « vide » (transparent + layout 0-width).
        let bg = UIColor(red: 0.12, green: 0.13, blue: 0.16, alpha: 1)
        web.isOpaque = true
        web.backgroundColor = bg
        web.scrollView.backgroundColor = bg
        web.scrollView.isScrollEnabled = false
        web.navigationDelegate = context.coordinator
        web.setContentHuggingPriority(.defaultLow, for: .vertical)
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.heightBinding = $measuredHeight
        let width = webView.bounds.width
        let needsReload =
            context.coordinator.lastHtml != html
            || (width > 1 && abs(context.coordinator.lastWidth - width) > 1)
        if needsReload {
            context.coordinator.lastHtml = html
            context.coordinator.lastWidth = width
            webView.loadHTMLString(Self.wrap(html), baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastHtml: String?
        var lastWidth: CGFloat = 0
        var heightBinding: Binding<CGFloat>?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            remasure(webView)
            // Images / CSS tardifs + second layout après largeur réelle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.remasure(webView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
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
              return Math.max(document.body.scrollHeight, document.documentElement.scrollHeight, 160);
            })();
            """
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                let height = (result as? CGFloat)
                    ?? (result as? Double).map { CGFloat($0) }
                    ?? 240
                let clamped = max(160, min(height + 16, 4000))
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

    /// Extrait le fragment body et retire styles qui forcent du texte sombre.
    private static func sanitize(_ html: String) -> String {
        var s = html
        // Document complet → fragment body (évite <html> imbriqué dans wrap).
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
        // Strip <style>…</style>
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
        // Strip bgcolor / color / style attributes (best-effort)
        if let regex = try? NSRegularExpression(
            pattern: "\\s(style|bgcolor|color|background|text)\\s*=\\s*(\"[^\"]*\"|'[^']*'|[^\\s>]+)",
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

    private static func wrap(_ html: String) -> String {
        let body = sanitize(html)
        return """
        <!DOCTYPE html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
        <meta name="color-scheme" content="dark light">
        <base target="_blank" rel="noopener noreferrer">
        <style id="cn-base">
        html,body{margin:0;padding:0 12px;
        background:light-dark(#F3F4F6,#1e2128)!important;
        color:light-dark(#14161A,#f2f2f7)!important;
        font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',sans-serif;font-size:17px;line-height:1.55;width:100%;
        max-width:100%;overflow-x:hidden;overflow-wrap:anywhere;word-break:break-word;-webkit-text-size-adjust:100%;}
        /* Ne pas forcer width:100% sur tous les td (casse spacers Gmail). */
        body > table{width:100%!important;max-width:100%!important;margin-left:auto!important;margin-right:auto!important;}
        body > div, body > center{max-width:100%!important;margin-left:auto!important;margin-right:auto!important;}
        html,body,p,span,div,li,td,th{color:light-dark(#14161A,#f2f2f7)!important;}
        a,a *{color:light-dark(#3B6EA5,#8ec7ff)!important}
        img{max-width:100%!important;height:auto!important}
        table{max-width:100%!important;border-collapse:collapse}
        td,th{word-break:break-word}
        pre,code{white-space:pre-wrap;word-break:break-word}
        blockquote{margin:0;padding-left:12px;border-left:3px solid light-dark(#3B6EA5,#3ECFBE);color:light-dark(#5C6370,#d1d1d6)!important}
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
