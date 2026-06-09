//
//  FileViewerWebView.swift
//  GitWatcher
//
//  파일 탐색기 코드 뷰어. highlight.js + 테마 CSS 를 번들 리소스에서 읽어 HTML 에 인라인하고
//  (네트워크/CDN 의존 없음 — 로컬 전용 원칙), 웜 WKWebView 에 코드 텍스트만 주입한다.
//

import SwiftUI
import WebKit

struct FileViewerWebView: NSViewRepresentable {
    let code: String
    let language: String?    // hljs 언어명. nil 이면 자동 감지.

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = webView
        webView.loadHTMLString(Self.html, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.render(code: code, language: language)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var loaded = false
        private var pending: (String, String?)?
        private var lastKey: String?

        func render(code: String, language: String?) {
            let key = "\(language ?? "auto")\u{1}\(code.count)\u{1}\(code.hashValue)"
            guard key != lastKey else { return }
            lastKey = key
            if loaded { inject(code, language) } else { pending = (code, language) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let (c, l) = pending { inject(c, l); pending = nil }
        }

        private func inject(_ code: String, _ language: String?) {
            guard let webView else { return }
            let codeLit = jsString(code)
            let langLit = language.map { jsString($0) } ?? "null"
            webView.evaluateJavaScript("window.renderCode(\(codeLit), \(langLit));", completionHandler: nil)
        }

        private func jsString(_ s: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])) ?? Data("\"\"".utf8)
            return String(data: data, encoding: .utf8) ?? "\"\""
        }
    }

    // MARK: 번들 리소스 인라인 HTML

    static let html: String = {
        let js = bundleString("highlight.min", "js") ?? ""
        let lineNumbersJS = bundleString("highlightjs-line-numbers.min", "js") ?? ""
        let themeCSS = bundleString("atom-one-dark.min", "css") ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          \(themeCSS)
          * { box-sizing: border-box; }
          /* 코드 뷰어는 항상 atom-one-dark 다크 고정 */
          html, body { margin: 0; padding: 0; background: #282c34; color: #abb2bf; }
          pre { margin: 0; }
          pre code.hljs {
            display: block;
            padding: 12px 0;
            font: 12px ui-monospace, SFMono-Regular, Menlo, monospace;
            line-height: 1.7;
            white-space: pre;
            background: transparent;
          }
          /* 라인 넘버 gutter (specificity 를 td.클래스 로 높여 .hljs-ln td 를 이긴다) */
          .hljs-ln { border-collapse: collapse; }
          .hljs-ln td { border: 0; line-height: 1.7; }
          .hljs-ln td.hljs-ln-numbers {
            text-align: right; vertical-align: top;
            color: rgba(171,178,191,0.4);
            padding: 0 18px 0 16px;
            user-select: none; -webkit-user-select: none;
            white-space: nowrap;
            border-right: 1px solid rgba(171,178,191,0.18);
          }
          .hljs-ln td.hljs-ln-code { padding: 0 14px 0 18px; white-space: pre; }
          #empty { padding: 40px; text-align: center; color: #6b7280;
            font-family: -apple-system, sans-serif; }
        </style>
        <script>\(js)</script>
        <script>\(lineNumbersJS)</script>
        </head>
        <body>
          <div id="empty">Select a file to view it.</div>
          <pre style="display:none"><code id="code"></code></pre>
        <script>
          window.renderCode = function(code, lang) {
            const empty = document.getElementById('empty');
            const pre = document.querySelector('pre');
            const el = document.getElementById('code');
            empty.style.display = 'none';
            pre.style.display = '';
            delete el.dataset.highlighted;
            el.className = lang ? ('language-' + lang) : '';
            el.textContent = code;
            try {
              if (lang && hljs.getLanguage(lang)) { hljs.highlightElement(el); }
              else { const r = hljs.highlightAuto(code); el.innerHTML = r.value; el.classList.add('hljs'); }
            } catch (e) { el.classList.add('hljs'); }
            try { hljs.lineNumbersBlock(el, { singleLine: true }); } catch (e) {}
            window.scrollTo(0, 0);
          };
        </script>
        </body>
        </html>
        """
    }()

    private static func bundleString(_ name: String, _ ext: String) -> String? {
        let b = Bundle.main
        let url = b.url(forResource: name, withExtension: ext, subdirectory: "highlight")
            ?? b.url(forResource: name, withExtension: ext)
        guard let url, let s = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return s
    }
}

// MARK: - 확장자 → highlight.js 언어 매핑

nonisolated enum CodeLanguage {
    static func hljsName(for fileName: String) -> String? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "jsx", "mjs", "cjs": return "javascript"
        case "ts", "tsx": return "typescript"
        case "json": return "json"
        case "html", "htm": return "xml"
        case "xml", "plist", "storyboard", "xib", "svg": return "xml"
        case "css": return "css"
        case "scss", "sass": return "scss"
        case "md", "markdown": return "markdown"
        case "py": return "python"
        case "rb": return "ruby"
        case "go": return "go"
        case "rs": return "rust"
        case "java": return "java"
        case "kt", "kts": return "kotlin"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "m", "mm": return "objectivec"
        case "sh", "bash", "zsh": return "bash"
        case "yml", "yaml": return "yaml"
        case "toml": return "ini"
        case "sql": return "sql"
        case "php": return "php"
        case "dart": return "dart"
        default: return nil   // 자동 감지
        }
    }
}
