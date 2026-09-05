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
            // Newsletters: images / layout asynchrone — remeasure pour le scale-to-fit.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                self?.remasure(webView)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.remasure(webView)
            }
        }

        private func remasure(_ webView: WKWebView) {
            let js = """
            (function(){
              var root=document.getElementById('cn-mail-root')||document.body;
              var b=document.body;
              if(!root||!b) return 160;
              var vw=Math.max(document.documentElement.clientWidth||0, window.innerWidth||0, 320);
              b.style.margin='0';
              b.style.padding='0';
              b.style.overflowX='hidden';
              root.style.transform='none';
              root.style.transformOrigin='top left';
              root.style.width='100%';
              root.style.maxWidth='100%';
              root.style.margin='0';
              root.style.padding='0';
              root.style.boxSizing='border-box';

              // Newsletters: tables/images à largeur fixe (ex. 600px) → forcer le reflow.
              var nodes=root.querySelectorAll('table,td,th,div,center,section,article,img,video');
              for(var i=0;i<nodes.length;i++){
                var el=nodes[i];
                var tag=el.tagName;
                el.style.maxWidth='100%';
                el.style.boxSizing='border-box';
                el.style.minWidth='0';
                if(tag==='IMG'||tag==='VIDEO'){
                  el.style.height='auto';
                  el.removeAttribute('width');
                  el.removeAttribute('height');
                }
                if(tag==='TABLE'){
                  el.style.marginLeft='0';
                  el.style.marginRight='0';
                  el.removeAttribute('width');
                  el.style.width='100%';
                }
                var attrW=el.getAttribute('width');
                if(attrW){
                  var aw=parseInt(attrW,10);
                  if(!isNaN(aw) && aw>vw){ el.removeAttribute('width'); }
                }
                if(el.style && el.style.width && /px$/i.test(el.style.width)){
                  var sw=parseFloat(el.style.width);
                  if(!isNaN(sw) && sw>vw){ el.style.width='100%'; }
                }
                if(el.style && el.style.minWidth && /px$/i.test(el.style.minWidth)){
                  var mw=parseFloat(el.style.minWidth);
                  if(!isNaN(mw) && mw>vw){ el.style.minWidth='0'; }
                }
              }

              // Mesure après reflow ; si ça déborde encore, scale-to-fit (évite la troncature).
              var contentW=Math.max(
                root.scrollWidth||0,
                b.scrollWidth||0,
                document.documentElement.scrollWidth||0,
                vw
              );
              var scale=1;
              if(contentW>vw+1){
                scale=vw/contentW;
                root.style.width=contentW+'px';
                root.style.maxWidth=contentW+'px';
                root.style.transformOrigin='top left';
                root.style.transform='scale('+scale+')';
              } else {
                root.style.width='100%';
                root.style.maxWidth='100%';
                root.style.transform='none';
              }

              var rawH=Math.max(root.scrollHeight||0, b.scrollHeight||0, document.documentElement.scrollHeight||0, 160);
              return Math.ceil(rawH*scale);
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
        #cn-mail-root{display:block;width:100%;max-width:100%;margin:0;padding:0;text-align:left;transform-origin:top left;}
        #cn-mail-root table{width:100%!important;max-width:100%!important;min-width:0!important;margin-left:0!important;margin-right:0!important;border-collapse:collapse;}
        #cn-mail-root td,#cn-mail-root th{max-width:100%!important;min-width:0!important;word-break:break-word;overflow-wrap:anywhere;}
        #cn-mail-root center,#cn-mail-root div,#cn-mail-root section,#cn-mail-root article{max-width:100%!important;min-width:0!important;box-sizing:border-box;}
        #cn-mail-root img,#cn-mail-root video{max-width:100%!important;width:auto!important;height:auto!important}
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
