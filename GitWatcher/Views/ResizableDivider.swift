//
//  ResizableDivider.swift
//  GitWatcher
//
//  드래그로 좌측 패널 폭을 조정하는 분할선. 폭은 호출부에서 @AppStorage 등으로 영속화한다.
//  SwiftUI HSplitView 가 분할 위치를 저장하지 않아, 이 커스텀 분할선으로 대체한다.
//

import SwiftUI
import AppKit

struct ResizableDivider: View {
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double

    @State private var dragBase: Double?

    var body: some View {
        ZStack {
            Color.clear.frame(width: 10).contentShape(Rectangle())
            Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1)
        }
        .frame(maxHeight: .infinity)
        .onHover { inside in
            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let base = dragBase ?? width
                    if dragBase == nil { dragBase = width }
                    width = min(max(base + value.translation.width, minWidth), maxWidth)
                }
                .onEnded { _ in dragBase = nil }
        )
    }
}
