import SwiftUI
import WebKit
import AndorrCore

struct MarkdownPreview: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: Palette { Palette(colorScheme: colorScheme) }
    let source: String
    var zoom = EditorZoom.defaultScale
    @State private var html = ""
    @State private var loadError: String?
    @State private var retryID = UUID()

    var body: some View {
        ZStack {
            PreviewWebView(html: html, loadError: $loadError, retryID: retryID, zoom: zoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if let loadError {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass").font(.largeTitle).foregroundStyle(.secondary)
                    Text("L’aperçu n’a pas pu s’afficher.").font(.headline)
                    Text(loadError).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Réessayer") { self.loadError = nil; retryID = UUID() }
                }
                .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(palette.paper)
            } else if html.isEmpty {
                ProgressView("Préparation de l’aperçu…")
            }
        }
            .task(id: source) {
                let text = source
                let rendered = await Task.detached(priority: .userInitiated) { MarkdownRenderer.html(text) }.value
                guard !Task.isCancelled else { return }
                loadError = nil
                html = rendered
            }
    }
}

private struct PreviewWebView: NSViewRepresentable {
    let html: String
    @Binding var loadError: String?
    let retryID: UUID
    let zoom: Double
    @Environment(\.colorScheme) private var colorScheme

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.underPageBackgroundColor = .windowBackgroundColor
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.parent = self
        view.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        // Apply zoom independently of HTML changes: preserve the loaded page
        // and its scroll position instead of regenerating the preview.
        view.pageZoom = CGFloat(EditorZoom.normalized(zoom))
        guard !html.isEmpty,
              context.coordinator.html != html || context.coordinator.retryID != retryID else { return }
        context.coordinator.html = html
        context.coordinator.retryID = retryID
        view.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: PreviewWebView
        var html: String?
        var retryID: UUID?

        init(parent: PreviewWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            switch PreviewNavigationPolicy.decision(for: navigationAction.request.url,
                                                     userActivatedLink: navigationAction.navigationType == .linkActivated) {
            case .allowLocal:
                decisionHandler(.allow)
            case .openExternal(let url):
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            case .cancel:
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            parent.loadError = "Le moteur d’aperçu s’est arrêté. Vous pouvez relancer l’affichage."
        }

        private func report(_ error: Error) {
            let cocoaError = error as NSError
            // Replacing the document during a note change legitimately cancels
            // the previous navigation. It must not cover the new note with an error.
            guard cocoaError.domain != NSURLErrorDomain || cocoaError.code != NSURLErrorCancelled else { return }
            parent.loadError = error.localizedDescription
        }
    }
}

enum PreviewNavigationDecision: Equatable {
    case allowLocal
    case openExternal(URL)
    case cancel
}

enum PreviewNavigationPolicy {
    static func decision(for url: URL?, userActivatedLink: Bool) -> PreviewNavigationDecision {
        // loadHTMLString can start with a synthetic request without a URL.
        guard let url else { return userActivatedLink ? .cancel : .allowLocal }
        if url.absoluteString == "about:blank" || url.absoluteString.hasPrefix("about:blank#") {
            return .allowLocal
        }
        if userActivatedLink, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
            return .openExternal(url)
        }
        return .cancel
    }
}
