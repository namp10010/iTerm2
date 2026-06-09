//
//  iTermBrowserPrewarmer.swift
//  iTerm2
//
//  Warms up the WebKit engine shortly after launch so the first browser tab
//  opens quickly. The first WKWebView the app creates pays a one-time cost:
//  dyld loads the WebKit framework graph (WebKit, WebCore, JavaScriptCore) and
//  WebKit launches its auxiliary processes (WebContent, Networking, GPU).
//
//  WebKit is not linked at launch, so that framework load is a heavy synchronous
//  cost. We move it off the main thread (dlopen on a background queue) and only
//  touch the main thread to create the warm WKWebView once the main run loop is
//  idle, so app startup stays responsive.
//
//  Controlled by the `preloadWebBrowserEngine` advanced setting (off by default).
//

import WebKit

@objc
class iTermBrowserPrewarmer: NSObject {
    @objc static let shared = iTermBrowserPrewarmer()

    // Strong reference keeps the warm webview (and thus the WebKit processes)
    // alive for the lifetime of the app. The webview only ever holds about:blank,
    // so its footprint is small.
    private var warmWebView: WKWebView?
    private var didStart = false

    @objc
    func prewarmIfNeeded() {
        guard !didStart else {
            return
        }
        guard iTermAdvancedSettingsModel.preloadWebBrowserEngine() else {
            return
        }
        // Respect the browser feature gate (browser profiles enabled + plugin
        // installed). No point warming WebKit if the browser can't be used.
        guard iTermBrowserGateway.browserAllowed(checkIfNo: false) else {
            return
        }
        didStart = true

        // Step 1 (background thread): force the WebKit framework graph to load
        // into the process off the main thread. This is the heaviest synchronous
        // cost and would otherwise stall the main thread when the first WKWebView
        // is created.
        DispatchQueue.global(qos: .utility).async {
            _ = dlopen("/System/Library/Frameworks/WebKit.framework/WebKit", RTLD_LAZY)

            // Step 2 (main thread, but only when idle): create the webview. It is
            // main-thread-only, but with the frameworks already resident this is
            // cheap, and the helper processes spin up asynchronously.
            Self.runWhenMainThreadIdle { [weak self] in
                self?.createWarmWebView()
            }
        }
    }

    private func createWarmWebView() {
        let configuration = WKWebViewConfiguration()
        // Share the regular browser user's data store on macOS 14+ so the warmed
        // networking partition matches the one real browser tabs use. Mirrors
        // iTermBrowserManager.configure(_:contentManager:).
        if #available(macOS 14, *) {
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: iTermBrowserUser.defaultRegularID)
        }

        // No window: loading a page is enough to spin up the Networking and
        // WebContent processes. The GPU/render process warms cheaply when the
        // first real tab is displayed, so we skip the off-screen window's cost.
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1, height: 1),
                                configuration: configuration)
        if let url = URL(string: "about:blank") {
            webView.load(URLRequest(url: url))
        }
        warmWebView = webView
        DLog("Prewarmed web browser engine")
    }

    // Runs `block` on the main thread the next time the main run loop is about to
    // go idle (kCFRunLoopBeforeWaiting), so warm-up work never delays startup or
    // window restoration. Safe to call from any thread.
    private static func runWhenMainThreadIdle(_ block: @escaping () -> Void) {
        DispatchQueue.main.async {
            let runLoop = CFRunLoopGetCurrent()
            var observer: CFRunLoopObserver?
            observer = CFRunLoopObserverCreateWithHandler(
                nil,
                CFRunLoopActivity.beforeWaiting.rawValue,
                false,  // one-shot
                0) { _, _ in
                    if let observer {
                        CFRunLoopRemoveObserver(runLoop, observer, .commonModes)
                    }
                    block()
                }
            if let observer {
                CFRunLoopAddObserver(runLoop, observer, .commonModes)
            }
        }
    }
}
