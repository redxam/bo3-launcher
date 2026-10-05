import SwiftUI
import WebKit

struct SteamWebView: View {
    @State private var urlString = "https://steamcommunity.com/id/co-Y2/myworkshopfiles/?appid=311210&browsefilter=mysubscriptions"
    @State private var isLoading = true
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var pageTitle = "Workshop"

    @StateObject private var coordinator = WebCoordinator()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().background(Theme.divider)
            ZStack {
                WebViewRepresentable(coordinator: coordinator)

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                        .colorScheme(.dark)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bgDark)
        .onAppear {
            coordinator.onLoadingChange = { loading in isLoading = loading }
            coordinator.onNavigationChange = { back, forward in
                canGoBack = back
                canGoForward = forward
            }
            coordinator.onTitleChange = { title in pageTitle = title }
            coordinator.load(urlString)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                navButton(icon: "chevron.left", enabled: canGoBack) {
                    coordinator.goBack()
                }
                navButton(icon: "chevron.right", enabled: canGoForward) {
                    coordinator.goForward()
                }
                navButton(icon: "arrow.clockwise", enabled: true) {
                    coordinator.reload()
                }
            }

            Text(pageTitle)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
                .lineLimit(1)

            Spacer()

            Button(action: {
                coordinator.load("https://steamcommunity.com/id/co-Y2/myworkshopfiles/?appid=311210&browsefilter=mysubscriptions")
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet")
                    Text("My Subscriptions")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.orange)
            }
            .focusable(false)
            .buttonStyle(ClickableStyle())

            Button(action: {
                coordinator.load("https://steamcommunity.com/app/311210/workshop/")
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                    Text("Browse Workshop")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.textSecondary)
            }
            .focusable(false)
            .buttonStyle(ClickableStyle())

            Button(action: {
                if let url = coordinator.currentURL {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.textMuted)
            }
            .focusable(false)
            .buttonStyle(ClickableStyle())
            .help("Open in browser")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Theme.bgMedium)
    }

    private func navButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(enabled ? Theme.textSecondary : Theme.textMuted.opacity(0.4))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .focusable(false)
        .buttonStyle(ClickableStyle())
        .disabled(!enabled)
    }
}

final class WebCoordinator: NSObject, ObservableObject, WKNavigationDelegate {
    var webView: WKWebView?
    var onLoadingChange: ((Bool) -> Void)?
    var onNavigationChange: ((Bool, Bool) -> Void)?
    var onTitleChange: ((String) -> Void)?

    var currentURL: URL? { webView?.url }

    func load(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        webView?.load(URLRequest(url: url))
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }
    func reload() { webView?.reload() }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onLoadingChange?(true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadingChange?(false)
        onNavigationChange?(webView.canGoBack, webView.canGoForward)
        onTitleChange?(webView.title ?? "Workshop")

        // Inject dark mode CSS to match the launcher theme
        let css = """
        body { background-color: #141210 !important; }
        .responsive_page_template_content { background-color: #141210 !important; }
        .apphub_HomeHeader, .apphub_HeaderTop { background-color: #1a1816 !important; }
        """
        let js = "var s=document.createElement('style');s.textContent=`\(css)`;document.head.appendChild(s);"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url,
           let host = url.host,
           !host.contains("steam") && !host.contains("valve") && navigationAction.navigationType == .linkActivated {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }
}

struct WebViewRepresentable: NSViewRepresentable {
    let coordinator: WebCoordinator

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.setValue(false, forKey: "drawsBackground")
        coordinator.webView = webView
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
