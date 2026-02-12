import SwiftUI
import WebKit

struct SandboxInspectorView: View {
    let url: URL
    let username: String
    let password: String
    let onContinue: () -> Void
    let onCancel: () -> Void
    let onComplete: (URL) -> Void

    var body: some View {
        NavigationView {
            SandboxWebView(
                url: url,
                username: username,
                password: password,
                onComplete: onComplete
            )
                .navigationTitle("Sandbox Inspector")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            onCancel()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Continue") {
                            onContinue()
                        }
                    }
                }
        }
    }
}

struct SandboxWebView: UIViewRepresentable {
    let url: URL
    let username: String
    let password: String
    let onComplete: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIView(context: Context) -> WKWebView {
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "elementClick")
        contentController.add(context.coordinator, name: "pageChange")

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        let script = WKUserScript(
            source: Coordinator.eventCaptureJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(script)

        let autoLoginScript = WKUserScript(
            source: Coordinator.autoLoginJS(username: username, password: password),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        contentController.addUserScript(autoLoginScript)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if uiView.url != url {
            uiView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        private let onComplete: (URL) -> Void

        init(onComplete: @escaping (URL) -> Void) {
            self.onComplete = onComplete
        }

        static let eventCaptureJS = #"""
        (function() {
          function normalize(text) {
            return (text || '').toLowerCase().replace(/\s+/g, ' ').trim();
          }

          function safeText(text) {
            return (text || '').replace(/\s+/g, ' ').trim();
          }

          function labelFor(el) {
            var label = '';
            if (el.id && window.CSS && CSS.escape) {
              var labelEl = document.querySelector('label[for="' + CSS.escape(el.id) + '"]');
              if (labelEl) {
                label = safeText(labelEl.innerText || labelEl.textContent || '');
              }
            }
            if (!label) {
              var parentLabel = el.closest ? el.closest('label') : null;
              if (parentLabel) {
                label = safeText(parentLabel.innerText || parentLabel.textContent || '');
              }
            }
            if (!label) {
              label = safeText(el.getAttribute && (el.getAttribute('aria-label') || el.getAttribute('title')));
            }
            return label || null;
          }

          function describe(el) {
            if (!el) { return null; }
            return {
              label: labelFor(el),
              tag: el.tagName ? el.tagName.toLowerCase() : null,
              id: el.id || null,
              name: el.name || null,
              type: el.type || null,
              value: el.value || null,
              placeholder: el.placeholder || null,
              text: safeText(el.innerText || el.textContent || el.value || '')
            };
          }

          document.addEventListener('click', function(e) {
            if (!e.isTrusted) { return; }
            var payload = describe(e.target);
            if (payload && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.elementClick) {
              window.webkit.messageHandlers.elementClick.postMessage(JSON.stringify(payload));
            }
          }, true);

          function notify(type) {
            if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.pageChange) {
              window.webkit.messageHandlers.pageChange.postMessage(JSON.stringify({ type: type, url: window.location.href }));
            }
          }

          var pushState = history.pushState;
          history.pushState = function() {
            pushState.apply(history, arguments);
            notify('pushState');
          };

          var replaceState = history.replaceState;
          history.replaceState = function() {
            replaceState.apply(history, arguments);
            notify('replaceState');
          };

          window.addEventListener('popstate', function() { notify('popstate'); });
          window.addEventListener('hashchange', function() { notify('hashchange'); });
          notify('load');
        })();
        """#

        static func autoLoginJS(username: String, password: String) -> String {
            let encodedUser = jsString(username)
            let encodedPass = jsString(password)
            return """
            (function () {
              if (window.__smartAutoLoginInstalled) { return; }
              window.__smartAutoLoginInstalled = true;

              var creds = { username: \(encodedUser), password: \(encodedPass) };
              var state = window.__smartAutoLoginState || {
                login: false,
                lastNextClickAt: 0,
                lastConsentClickAt: 0,
                consentClicks: 0,
                lastRunAt: 0
              };
              window.__smartAutoLoginState = state;

              var firstLoadDelayReady = false;
              var firstLoadDelayScheduled = false;
              var firstLoadDelayKey = "__smartAutoLoginFirstLoadDelayDone";

              try {
                if (sessionStorage.getItem(firstLoadDelayKey) === "1") {
                  firstLoadDelayReady = true;
                }
              } catch (e) {}

              function setNativeValue(el, value) {
                var proto = Object.getPrototypeOf(el);
                var desc = Object.getOwnPropertyDescriptor(proto, "value");
                if (desc && desc.set) desc.set.call(el, value);
                else el.value = value;
                el.dispatchEvent(new Event("input", { bubbles: true }));
                el.dispatchEvent(new Event("change", { bubbles: true }));
              }

              function click(el) {
                el.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true, view: window }));
                el.click();
              }

              function isDisabled(el) {
                return !!(el.disabled || el.getAttribute("aria-disabled") === "true");
              }

              function tryLogin() {
                if (state.login) { return false; }
                var usernameField = document.querySelector("#Login");
                var passwordField = document.querySelector("#Password");
                var submitButton = document.querySelector("#submit");
                if (usernameField && passwordField && submitButton && !isDisabled(submitButton)) {
                  setNativeValue(usernameField, creds.username);
                  setNativeValue(passwordField, creds.password);
                  click(submitButton);
                  state.login = true;
                  console.log("[Sandbox][AutoLogin] submitted username + password");
                  return true;
                }

                if (usernameField && submitButton && !passwordField && !isDisabled(submitButton)) {
                  setNativeValue(usernameField, creds.username);
                  click(submitButton);
                  state.login = true;
                  console.log("[Sandbox][AutoLogin] submitted username only");
                  return true;
                }
                return false;
              }

              function tryNext() {
                var nextButton = document.querySelector("#nextButton");
                if (nextButton && !isDisabled(nextButton)) {
                  var now = Date.now();
                  if (now - state.lastNextClickAt < 800) { return false; }
                  click(nextButton);
                  state.lastNextClickAt = now;
                  console.log("[Sandbox][AutoLogin] clicked nextButton");
                  return true;
                }
                return false;
              }

              function normalizeText(value) {
                return (value || "").toLowerCase().replace(/\\s+/g, " ").trim();
              }

              function findConsentButton() {
                var selectors = [
                  "#allowDataSharing",
                  "#authorize",
                  "#authorizeButton",
                  "#AuthorizeButton",
                  "button[name='authorize']",
                  "input[name='authorize']",
                  "button[data-action='authorize']",
                  "input[data-action='authorize']"
                ];

                for (var i = 0; i < selectors.length; i++) {
                  var el = document.querySelector(selectors[i]);
                  if (el) { return el; }
                }

                var candidates = document.querySelectorAll("button, input[type='submit'], input[type='button']");
                for (var j = 0; j < candidates.length; j++) {
                  var candidate = candidates[j];
                  if (isDisabled(candidate)) { continue; }
                  var text = normalizeText(candidate.innerText || candidate.textContent || candidate.value || candidate.getAttribute("aria-label") || "");
                  if (text.indexOf("allow") >= 0 || text.indexOf("authorize") >= 0 || text.indexOf("grant") >= 0 || text.indexOf("accept") >= 0) {
                    return candidate;
                  }
                }

                return null;
              }

              function tryConsent() {
                var now = Date.now();
                if (now - state.lastConsentClickAt < 900) { return false; }

                var consentButton = findConsentButton();
                if (consentButton && !isDisabled(consentButton)) {
                  click(consentButton);
                  state.lastConsentClickAt = now;
                  state.consentClicks += 1;
                  console.log("[Sandbox][AutoLogin] clicked consent button", consentButton.id || consentButton.name || consentButton.value || consentButton.innerText || "<unknown>");
                  return true;
                }

                return false;
              }

              function runAutomation() {
                if (!firstLoadDelayReady) { return; }
                var now = Date.now();
                if (now - state.lastRunAt < 100) { return; }
                state.lastRunAt = now;

                // Completion-driven order: login -> next -> consent/auth.
                // If one action occurs, return and wait for DOM/navigation to settle.
                if (tryLogin()) { return; }
                if (tryNext()) { return; }
                tryConsent();
              }

              function scheduleFirstLoadDelay() {
                if (firstLoadDelayReady || firstLoadDelayScheduled) { return; }
                firstLoadDelayScheduled = true;
                setTimeout(function() {
                  firstLoadDelayReady = true;
                  try { sessionStorage.setItem(firstLoadDelayKey, "1"); } catch (e) {}
                  runAutomation();
                }, 500);
              }

              function attachObserver() {
                if (!document.documentElement) { return null; }
                var observer = new MutationObserver(function() {
                  runAutomation();
                });
                observer.observe(document.documentElement, {
                  childList: true,
                  subtree: true,
                  attributes: true
                });
                return observer;
              }

              var observer = attachObserver();
              window.addEventListener("load", runAutomation, true);
              window.addEventListener("load", scheduleFirstLoadDelay, true);
              document.addEventListener("readystatechange", runAutomation, true);
              window.addEventListener("pageshow", runAutomation, true);
              window.addEventListener("popstate", runAutomation, true);
              window.addEventListener("hashchange", runAutomation, true);
              document.addEventListener("click", function(e) {
                if (e.isTrusted) { runAutomation(); }
              }, true);

              if (!firstLoadDelayReady && document.readyState === "complete") {
                scheduleFirstLoadDelay();
              }

              runAutomation();

              // Backup path if observers/events miss an update.
              var fallbackAttempts = 0;
              var fallbackTimer = setInterval(function() {
                fallbackAttempts += 1;
                runAutomation();
                var reachedCallback = false;
                try { reachedCallback = (window.location.href || "").indexOf("myapp://") === 0; } catch (e) {}
                if (reachedCallback || fallbackAttempts > 60) {
                  clearInterval(fallbackTimer);
                  if (observer) { observer.disconnect(); }
                }
              }, 1500);
            })();
            """
        }

        private static func jsString(_ value: String) -> String {
            let data = try? JSONEncoder().encode(value)
            return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? String, let data = body.data(using: .utf8) else { return }

            if message.name == "elementClick" {
                if let info = try? JSONDecoder().decode(WebElementInfo.self, from: data) {
                    Self.printElement(info, label: "Clicked")
                }
                return
            }

            if message.name == "pageChange" {
                if let change = try? JSONDecoder().decode(PageChangeEvent.self, from: data) {
                    print("[Sandbox] Page change (\(change.type)): \(change.url)")
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            print("[Sandbox] Navigation started: \(webView.url?.absoluteString ?? "unknown")")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("[Sandbox] Navigation finished: \(webView.url?.absoluteString ?? "unknown")")
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, url.scheme == Config.callbackScheme {
                DispatchQueue.main.async { [onComplete] in
                    onComplete(url)
                }
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private static func printElement(_ info: WebElementInfo, label: String) {
            let id = info.id ?? "<none>"
            let name = info.name ?? "<none>"
            let type = info.type ?? "<none>"
            let value = (info.type == "password") ? "<redacted>" : (info.value ?? "<none>")
            let placeholder = info.placeholder ?? "<none>"
            let text = info.text ?? "<none>"
            let labelText = info.label ?? "<none>"
            print("[Sandbox] \(label) element -> id=\(id) name=\(name) type=\(type) value=\(value) placeholder=\(placeholder) text=\(text) label=\(labelText)")
        }
    }
}

struct PageChangeEvent: Decodable {
    let type: String
    let url: String
}
