//
//  DiffWebView.swift
//  GitWatcher
//
//  diff / file 뷰어. 웜 WKWebView 인스턴스 하나를 띄워두고 Swift→JS 로 텍스트만 주입한다
//  (파일마다 새 웹뷰 금지, 웹뷰가 직접 fetch 하지 않음).
//  경량 렌더러를 HTML 문자열로 내장 — 네트워크/CDN 의존 없음(로컬 전용 원칙).
//

import SwiftUI
import WebKit

struct DiffWebView: NSViewRepresentable {
    /// 표시 내용. diff(unified) 또는 file(전체 + 추가된 줄 강조).
    enum Content: Equatable {
        case diff(String)
        case file(text: String, added: [Int])
    }

    let content: Content

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")   // 투명 배경(흰 플래시 방지)
        context.coordinator.webView = webView
        webView.loadHTMLString(Self.html, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.render(content)
    }

    // MARK: Coordinator — 웜 웹뷰 상태 관리

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var loaded = false
        private var pending: Content?
        private var lastRendered: Content?

        func render(_ content: Content) {
            guard content != lastRendered else { return }
            lastRendered = content
            if loaded { inject(content) } else { pending = content }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            if let p = pending { inject(p); pending = nil }
        }

        private func inject(_ content: Content) {
            guard let webView else { return }
            switch content {
            case .diff(let text):
                webView.evaluateJavaScript("window.renderDiff(\(jsString(text)));", completionHandler: nil)
            case .file(let text, let added):
                webView.evaluateJavaScript("window.renderFile(\(jsString(text)), \(jsArray(added)));", completionHandler: nil)
            }
        }

        /// 문자열을 JS 리터럴로 안전 변환(인젝션/이스케이프 처리).
        private func jsString(_ s: String) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: s, options: [.fragmentsAllowed])) ?? Data("\"\"".utf8)
            return String(data: data, encoding: .utf8) ?? "\"\""
        }
        private func jsArray(_ a: [Int]) -> String {
            let data = (try? JSONSerialization.data(withJSONObject: a)) ?? Data("[]".utf8)
            return String(data: data, encoding: .utf8) ?? "[]"
        }
    }

    // MARK: 내장 HTML/CSS/JS

    static let html = #"""
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <style>
      :root { color-scheme: light dark; }
      * { box-sizing: border-box; }
      /* 얇은 반투명 스크롤바 */
      ::-webkit-scrollbar { width: 8px; height: 8px; }
      ::-webkit-scrollbar-track { background: transparent; }
      ::-webkit-scrollbar-thumb { background: rgba(128,128,128,0.30); border-radius: 4px; }
      ::-webkit-scrollbar-thumb:hover { background: rgba(128,128,128,0.50); }
      ::-webkit-scrollbar-corner { background: transparent; }
      html, body { margin: 0; padding: 0;
        font: 12px ui-monospace, SFMono-Regular, Menlo, monospace;
        background: transparent;
        color: -apple-system-text, #1d1d1f; }
      @media (prefers-color-scheme: dark) { body { color: #e8e8ea; } }
      #empty { padding: 40px; text-align: center; color: #8a8a8e; font-family: -apple-system, sans-serif; }
      table { border-collapse: collapse; width: 100%; }
      tr { line-height: 1.5; }
      td { padding: 0 8px; white-space: pre; vertical-align: top; }
      td.num { width: 1%; text-align: right; color: #9a9a9e; user-select: none;
        border-right: 1px solid rgba(128,128,128,0.18); font-size: 11px; }
      td.code { width: 100%; }
      tr.add td.code { background: rgba(45,164,78,0.16); }
      tr.add td.code::before { content: "+"; color: rgba(45,164,78,0.9); }
      tr.del td.code { background: rgba(248,81,73,0.15); }
      tr.del td.code::before { content: "-"; color: rgba(248,81,73,0.9); }
      tr.ctx td.code::before { content: " "; }
      /* File View: 추가/수정된 줄 강조(삭제 없음, +/- 기호 없음) */
      tr.fadd td.code { background: rgba(45,164,78,0.16); }
      tr.hunk td { background: rgba(99,102,241,0.12); color: #6366f1;
        font-family: -apple-system, sans-serif; font-size: 11px; padding: 4px 8px; }
      tr.file td { background: rgba(128,128,128,0.10); font-weight: 600;
        font-family: -apple-system, sans-serif; padding: 6px 8px; }
    </style>
    </head>
    <body>
      <div id="empty">Select a file to view its diff.</div>
      <table id="diff" style="display:none"></table>
    <script>
      const empty = () => document.getElementById('empty');
      const table = () => document.getElementById('diff');

      // unified diff 텍스트를 라인별로 분류해 표로 렌더.
      window.renderDiff = function(text) {
        if (!text || !text.trim()) { showEmpty('Select a file to view its diff.'); return; }
        showTable();
        const lines = text.split('\n');
        let html = '';
        let oldLn = 0, newLn = 0;
        for (const line of lines) {
          if (line.startsWith('diff --git') || line.startsWith('index ') ||
              line.startsWith('new file') || line.startsWith('deleted file') ||
              line.startsWith('similarity ') || line.startsWith('rename ') ||
              line.startsWith('--- ') || line.startsWith('+++ ') ||
              line.startsWith('Binary ')) {
            if (line.startsWith('diff --git')) {
              const m = line.replace('diff --git a/', '').split(' b/');
              html += '<tr class="file"><td colspan="3">' + esc(m[0]) + '</td></tr>';
            }
            continue;
          }
          if (line.startsWith('@@')) {
            const m = line.match(/@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/);
            if (m) { oldLn = parseInt(m[1]); newLn = parseInt(m[2]); }
            html += '<tr class="hunk"><td colspan="3">' + esc(line) + '</td></tr>';
            continue;
          }
          const body = line.slice(1);
          if (line.startsWith('+'))      html += row3('add', '', newLn++, body);
          else if (line.startsWith('-')) html += row3('del', oldLn++, '', body);
          else                           html += row3('ctx', oldLn++, newLn++, line.startsWith(' ') ? body : line);
        }
        table().innerHTML = html;
        window.scrollTo(0, 0);
      };

      // 파일 전체를 표로 렌더하되, added 에 든 라인 번호만 배경 강조.
      window.renderFile = function(text, added) {
        if (text === null || text === undefined) { showEmpty('File content unavailable.'); return; }
        showTable();
        const addedSet = new Set(added);
        const lines = text.split('\n');
        if (lines.length && lines[lines.length - 1] === '') lines.pop();   // 끝 개행 제거
        let html = '';
        for (let i = 0; i < lines.length; i++) {
          const ln = i + 1;
          const cls = addedSet.has(ln) ? 'fadd' : '';
          html += '<tr class="' + cls + '"><td class="num">' + ln +
                  '</td><td class="code">' + esc(lines[i]) + '</td></tr>';
        }
        table().innerHTML = html;
        window.scrollTo(0, 0);
      };

      function showEmpty(msg) { empty().textContent = msg; empty().style.display = ''; table().style.display = 'none'; table().innerHTML = ''; }
      function showTable() { empty().style.display = 'none'; table().style.display = ''; }
      function row3(cls, o, n, code) {
        return '<tr class="' + cls + '"><td class="num">' + (o === '' ? '' : o) +
               '</td><td class="num">' + (n === '' ? '' : n) +
               '</td><td class="code">' + esc(code) + '</td></tr>';
      }
      function esc(s) { return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
    </script>
    </body>
    </html>
    """#
}
