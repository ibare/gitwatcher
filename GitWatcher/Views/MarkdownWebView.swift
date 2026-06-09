//
//  MarkdownWebView.swift
//  GitWatcher
//
//  마크다운 프리뷰 뷰어. marked.js 로 md→html 변환, 코드블록은 highlight.js 로 하이라이트한다.
//  모든 리소스는 번들 내장(네트워크/CDN 의존 없음 — 로컬 전용 원칙). 웜 WKWebView 에 텍스트만 주입.
//

import SwiftUI
import WebKit

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String

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
        context.coordinator.render(markdown: markdown)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var loaded = false
        private var pending: String?
        private var lastKey: String?

        func render(markdown: String) {
            let key = "\(markdown.count)\u{1}\(markdown.hashValue)"
            guard key != lastKey else { return }
            lastKey = key
            if loaded { inject(markdown) } else { pending = markdown }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let md = pending { inject(md); pending = nil }
        }

        // 외부 링크 클릭은 기본 브라우저로(로컬 파일 내비게이션은 막는다).
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        private func inject(_ markdown: String) {
            guard let webView else { return }
            webView.evaluateJavaScript("window.renderMarkdown(\(jsString(markdown)));", completionHandler: nil)
        }

        private func jsString(_ s: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])) ?? Data("\"\"".utf8)
            return String(data: data, encoding: .utf8) ?? "\"\""
        }
    }

    // MARK: 번들 리소스 인라인 HTML

    static let html: String = {
        let markedJS = bundleString("marked.min", "js") ?? ""
        let hljsJS = bundleString("highlight.min", "js") ?? ""
        let themeCSS = bundleString("atom-one-dark.min", "css") ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          \(themeCSS)
          * { box-sizing: border-box; }
          ::-webkit-scrollbar { width: 8px; height: 8px; }
          ::-webkit-scrollbar-track { background: transparent; }
          ::-webkit-scrollbar-thumb { background: rgba(171,178,191,0.22); border-radius: 4px; }
          ::-webkit-scrollbar-thumb:hover { background: rgba(171,178,191,0.40); }
          ::-webkit-scrollbar-corner { background: transparent; }
          html, body { margin: 0; padding: 0; background: #1e1e1e; }
          #content {
            padding: 24px 28px 48px;
            color: #cdd3dc;
            font: 14px/1.7 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
            max-width: 920px;
            word-wrap: break-word;
          }
          #content h1, #content h2, #content h3, #content h4, #content h5, #content h6 {
            margin: 24px 0 16px; font-weight: 600; line-height: 1.3; color: #e6e6e6;
          }
          #content h1 { font-size: 1.9em; padding-bottom: .3em; border-bottom: 1px solid #333; }
          #content h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid #333; }
          #content h3 { font-size: 1.25em; }
          #content h4 { font-size: 1em; }
          #content p, #content ul, #content ol, #content blockquote, #content table { margin: 0 0 16px; }
          #content ul, #content ol { padding-left: 2em; }
          #content li { margin: 4px 0; }
          #content li > ul, #content li > ol { margin: 4px 0; }
          #content a { color: #4ea1f3; text-decoration: none; }
          #content a:hover { text-decoration: underline; }
          #content blockquote {
            padding: 0 1em; color: #8b949e; border-left: 3px solid #444;
          }
          #content hr { height: 1px; background: #333; border: 0; margin: 24px 0; }
          #content img { max-width: 100%; }
          #content table { border-collapse: collapse; display: block; overflow: auto; }
          #content th, #content td { padding: 6px 13px; border: 1px solid #3a3a3a; }
          #content th { background: #262626; font-weight: 600; }
          #content tr:nth-child(2n) { background: #232323; }
          /* 인라인 코드 */
          #content code {
            background: rgba(171,178,191,0.13); padding: .2em .4em; border-radius: 4px;
            font: 12.5px ui-monospace, SFMono-Regular, Menlo, monospace;
          }
          /* 코드블록 — atom-one-dark 토큰 */
          #content pre {
            margin: 0 0 16px; padding: 14px 16px; background: #282c34;
            border-radius: 8px; overflow: auto;
          }
          #content pre code {
            background: transparent; padding: 0; border-radius: 0;
            font: 12.5px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; color: #abb2bf;
          }
          #content :first-child { margin-top: 0; }
          #empty { padding: 40px; text-align: center; color: #6b7280;
            font-family: -apple-system, sans-serif; }
        </style>
        <script>\(markedJS)</script>
        <script>\(hljsJS)</script>
        </head>
        <body>
          <div id="empty">No content.</div>
          <div id="content" style="display:none"></div>
        <script>
          if (window.marked && marked.setOptions) { marked.setOptions({ gfm: true, breaks: false }); }
          window.renderMarkdown = function(md) {
            const empty = document.getElementById('empty');
            const content = document.getElementById('content');
            empty.style.display = 'none';
            content.style.display = '';
            try { content.innerHTML = marked.parse(md); }
            catch (e) { content.textContent = md; }
            content.querySelectorAll('pre code').forEach(function(el) {
              try { hljs.highlightElement(el); } catch (e) {}
            });
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
