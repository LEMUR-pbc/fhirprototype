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
              var creds = { username: \(encodedUser), password: \(encodedPass) };
              var state = window.__smartAutoLoginState || { login: false, next: false, allow: false };
              window.__smartAutoLoginState = state;

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

              function tryLogin() {
                if (state.login) { return false; }
                var usernameField = document.querySelector("#Login");
                var passwordField = document.querySelector("#Password");
                var submitButton = document.querySelector("#submit");
                if (usernameField && passwordField && submitButton) {
                  setNativeValue(usernameField, creds.username);
                  setNativeValue(passwordField, creds.password);
                  click(submitButton);
                  state.login = true;
                  return true;
                }

                if (usernameField && submitButton && !passwordField) {
                  setNativeValue(usernameField, creds.username);
                  click(submitButton);
                  state.login = true;
                  return true;
                }
                return false;
              }

              function tryNext() {
                if (state.next) { return false; }
                var nextButton = document.querySelector("#nextButton");
                if (nextButton) {
                  click(nextButton);
                  state.next = true;
                  return true;
                }
                return false;
              }

              function tryAllow() {
                if (state.allow) { return false; }
                var allowButton = document.querySelector("#allowDataSharing");
                if (allowButton) {
                  click(allowButton);
                  state.allow = true;
                  return true;
                }
                return false;
              }

              var attempts = 0;
              var timer = setInterval(function() {
                attempts += 1;
                tryLogin();
                tryNext();
                tryAllow();
                if ((state.login && state.next && state.allow) || attempts > 80) {
                  clearInterval(timer);
                }
              }, 500);
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
