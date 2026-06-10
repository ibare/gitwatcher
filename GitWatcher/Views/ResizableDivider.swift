//
//  ResizableDivider.swift
//  GitWatcher
//
//  드래그로 인접 패널의 폭(수평) 또는 높이(수직)를 조정하는 분할선.
//  값은 호출부에서 @AppStorage 등으로 영속화한다.
//  SwiftUI HSplitView/VSplitView 가 분할 위치를 저장하지 않아, 이 커스텀 분할선으로 대체한다.
//

import SwiftUI
import AppKit

struct ResizableDivider: View {
    /// 분할 방향. horizontal = 좌측 패널 폭, vertical = 위쪽 패널 높이.
    enum Orientation { case horizontal, vertical }

    /// 조정 대상 크기(수평이면 폭, 수직이면 패널 높이).
    @Binding var width: Double
    let minWidth: Double
    let maxWidth: Double
    var orientation: Orientation = .horizontal
    /// 조정 대상 패널이 분할선의 trailing(오른쪽/아래)에 있을 때 true — 드래그 부호를 뒤집는다.
    /// (기본 false = leading 패널: 분할선을 끌어당기면 그 패널이 커진다.)
    var reversed: Bool = false

    @State private var dragBase: Double?

    var body: some View {
        Group {
            switch orientation {
            case .horizontal:
                ZStack {
                    Color.clear.frame(width: 10).contentShape(Rectangle())
                    Rectangle().fill(Color.primary.opacity(0.10)).frame(width: 1)
                }
                .frame(maxHeight: .infinity)
            case .vertical:
                ZStack {
                    Color.clear.frame(height: 10).contentShape(Rectangle())
                    Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onHover { inside in
            let cursor: NSCursor = orientation == .horizontal ? .resizeLeftRight : .resizeUpDown
            if inside { cursor.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let base = dragBase ?? width
                    if dragBase == nil { dragBase = width }
                    let raw = orientation == .horizontal ? value.translation.width : value.translation.height
                    let delta = reversed ? -raw : raw
                    width = min(max(base + delta, minWidth), maxWidth)
                }
                .onEnded { _ in dragBase = nil }
        )
    }
}
