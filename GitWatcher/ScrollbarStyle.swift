//
//  ScrollbarStyle.swift
//  GitWatcher
//
//  SwiftUI ScrollView/List 의 스크롤바를 overlay(스크롤할 때만 보이는 얇은 스크롤바)로.
//  NSScrollView swizzle 은 SwiftUI 내부 스크롤뷰와 충돌해 크래시하므로, 해당 뷰의
//  enclosingScrollView 에만 scrollerStyle 을 설정하는 안전한 방식을 쓴다.
//

import SwiftUI
import AppKit

private struct OverlayScrollerApplier: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView else { return }
            if scrollView.scrollerStyle != .overlay {
                scrollView.scrollerStyle = .overlay
            }
        }
    }
}

extension View {
    /// 이 뷰가 속한 ScrollView/List 의 스크롤바를 overlay 스타일로 만든다.
    func overlayScrollbars() -> some View {
        background(OverlayScrollerApplier())
    }
}
