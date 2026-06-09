//
//  PillSegmentedControl.swift
//  GitWatcher
//
//  toolbar segmented picker(회색 캡슐 톤)와 통일된 커스텀 세그먼트 컨트롤.
//  일반 뷰의 .pickerStyle(.segmented) 는 파란 강조라 톤이 달라, 이걸로 대체한다.
//

import SwiftUI
import AppKit

struct PillSegmentedControl<T: Hashable>: View {
    struct Option: Identifiable {
        let value: T
        let title: String
        var id: T { value }
    }

    let options: [Option]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { idx, opt in
                segment(idx: idx, opt: opt)
            }
        }
        .padding(2)
        .background(
            Capsule(style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.10), lineWidth: 1))
        )
    }

    @ViewBuilder
    private func segment(idx: Int, opt: Option) -> some View {
        let selected = selection == opt.value
        let prevSelected = idx > 0 && selection == options[idx - 1].value

        // Button 대신 Text + onTapGesture: macOS 26 toolbar 가 ToolbarItem 안의 Button 을
        // 시스템 캡슐 배경으로 자동 감싸는 것을 피한다(시각/동작 동일).
        Text(opt.title)
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background {
                if selected {
                    Capsule(style: .continuous).fill(Color.primary.opacity(0.09))
                }
            }
            .overlay(alignment: .leading) {
                // 인접 두 항목이 모두 비선택일 때만 구분선(toolbar segmented 와 동일).
                if idx > 0 && !selected && !prevSelected {
                    Rectangle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 1, height: 14)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { selection = opt.value }
    }
}
