import Foundation
import WebKit

struct WebElementInfo: Decodable {
    let label: String?
    let tag: String?
    let id: String?
    let name: String?
    let type: String?
    let value: String?
    let placeholder: String?
    let text: String?
}

struct AuthElementReport: Decodable {
    let username: WebElementInfo?
    let password: WebElementInfo?
    let login: WebElementInfo?
}

struct AuthCapturePayload: Decodable {
    let html: String
    let elements: AuthElementReport?
}

@MainActor
final class AuthHTMLCapturer: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<String, Error>?

    func captureHTML(from url: URL) async throws -> String {
        let webView = WKWebView(frame: .zero)
        self.webView = webView
        webView.navigationDelegate = self
        webView.load(URLRequest(url: url))

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak webView] in
            guard let self, let webView else { return }
            webView.evaluateJavaScript(Self.captureAndDiscoverJS) { [weak self] result, error in
                guard let self else { return }
                if let error = error {
                    self.finish(.failure(error))
                    return
                }
                guard let json = result as? String,
                      let data = json.data(using: .utf8),
                      let payload = try? JSONDecoder().decode(AuthCapturePayload.self, from: data) else {
                    self.finish(.failure(AppError.invalidHTMLCapture))
                    return
                }

                if let report = payload.elements {
                    Self.printElement(report.username, label: "Username")
                    Self.printElement(report.password, label: "Password")
                    Self.printElement(report.login, label: "Log in")
                } else {
                    print("[Sandbox] element discovery returned no data")
                }

                self.finish(.success(payload.html))
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    private static func printElement(_ info: WebElementInfo?, label: String) {
        guard let info else {
            print("[Sandbox] \(label) element not found")
            return
        }

        let id = info.id ?? "<none>"
        let name = info.name ?? "<none>"
        let type = info.type ?? "<none>"
        let value = info.value ?? "<none>"
        let placeholder = info.placeholder ?? "<none>"
        let text = info.text ?? "<none>"
        let labelText = info.label ?? "<none>"

        print("[Sandbox] \(label) element -> id=\(id) name=\(name) type=\(type) value=\(value) placeholder=\(placeholder) text=\(text) label=\(labelText)")
    }

    private func finish(_ result: Result<String, Error>) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        self.webView = nil
        continuation.resume(with: result)
    }

    private static let captureAndDiscoverJS = #"""
    (function() {
      function normalize(text) {
        return (text || '').toLowerCase().replace(/\s+/g, ' ').trim();
      }

      function matches(text, keywords) {
        var n = normalize(text);
        return keywords.some(function(k) { return n.indexOf(k) !== -1; });
      }

      function describe(el, label) {
        if (!el) { return null; }
        return {
          label: label || null,
          tag: el.tagName ? el.tagName.toLowerCase() : null,
          id: el.id || null,
          name: el.name || null,
          type: el.type || null,
          value: el.value || null,
          placeholder: el.placeholder || null,
          text: (el.innerText || el.value || '').trim()
        };
      }

      function findInputByLabelKeywords(keywords) {
        var labels = Array.prototype.slice.call(document.querySelectorAll('label'));
        for (var i = 0; i < labels.length; i++) {
          var label = labels[i];
          var labelText = label.innerText || label.textContent || '';
          if (matches(labelText, keywords)) {
            var target = null;
            if (label.htmlFor) {
              target = document.getElementById(label.htmlFor);
            }
            if (!target) {
              target = label.querySelector('input,textarea,select');
            }
            if (!target) {
              var sibling = label.nextElementSibling;
              if (sibling) {
                target = sibling.querySelector('input,textarea,select') || sibling;
              }
            }
            if (target) {
              return { element: target, label: labelText };
            }
          }
        }

        var inputs = Array.prototype.slice.call(document.querySelectorAll('input,textarea,select'));
        for (var j = 0; j < inputs.length; j++) {
          var input = inputs[j];
          var placeholder = input.placeholder || input.getAttribute('aria-label') || '';
          if (matches(placeholder, keywords)) {
            return { element: input, label: placeholder };
          }
        }

        return null;
      }

      function findLoginButton() {
        var candidates = [];
        candidates = candidates.concat(Array.prototype.slice.call(document.querySelectorAll('button')));
        candidates = candidates.concat(Array.prototype.slice.call(document.querySelectorAll('input[type=submit], input[type=button], input[type=submit]')));

        function score(el) {
          var text = (el.innerText || el.value || el.getAttribute('aria-label') || '').toLowerCase();
          if (text.indexOf('log in') !== -1 || text.indexOf('login') !== -1) { return 3; }
          if (text.indexOf('sign in') !== -1 || text.indexOf('sign-in') !== -1) { return 2; }
          if (text.indexOf('continue') !== -1 || text.indexOf('authorize') !== -1 || text.indexOf('allow') !== -1) { return 1; }
          return 0;
        }

        var best = null;
        var bestScore = 0;
        for (var i = 0; i < candidates.length; i++) {
          var s = score(candidates[i]);
          if (s > bestScore) {
            bestScore = s;
            best = candidates[i];
          }
        }
        return best;
      }

      var userMatch = findInputByLabelKeywords(['username', 'user name', 'email', 'email address', 'userid', 'user id']);
      var passMatch = findInputByLabelKeywords(['password', 'passcode']);
      var login = findLoginButton();

      return JSON.stringify({
        html: document.documentElement.outerHTML || '',
        elements: {
          username: userMatch ? describe(userMatch.element, userMatch.label) : null,
          password: passMatch ? describe(passMatch.element, passMatch.label) : null,
          login: login ? describe(login, null) : null
        }
      });
    })();
    """#
}

enum HTMLStorage {
    static func save(_ html: String, filename: String = "sandbox_auth_page.html") throws -> URL {
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = directory.appendingPathComponent(filename)
        try html.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
