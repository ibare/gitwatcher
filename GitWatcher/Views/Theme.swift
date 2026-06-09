//
//  Theme.swift
//  GitWatcher
//
//  Baden 대시보드와 통일한 비주얼 언어.
//  clean=green, dirty=amber(빨강 아님 — dirty 는 에러가 아니라 정상 상태),
//  diverged/behind=blue/indigo, accent=indigo.
//

import SwiftUI
import AppKit

// MARK: - 변경 종류 표시 헬퍼

extension ChangeKind {
    /// 파일 변경 종류 아이콘.
    var symbolName: String {
        switch self {
        case .modified:    return "pencil"
        case .added:       return "plus"
        case .deleted:     return "minus"
        case .renamed:     return "arrow.right"
        case .copied:      return "doc.on.doc"
        case .typeChanged: return "arrow.triangle.2.circlepath"
        case .untracked:   return "plus.circle"
        case .unmerged:    return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .added, .untracked:   return Theme.clean
        case .deleted:             return .red
        case .renamed, .copied:    return Theme.diverged
        case .unmerged:            return .red
        default:                   return Theme.dirty
        }
    }

    /// "modified", "added" … 변경 요약 문구용.
    var label: String {
        switch self {
        case .modified:    return "modified"
        case .added:       return "added"
        case .deleted:     return "deleted"
        case .renamed:     return "renamed"
        case .copied:      return "copied"
        case .typeChanged: return "type changed"
        case .untracked:   return "untracked"
        case .unmerged:    return "unmerged"
        }
    }
}

enum Theme {
    static let accent = Color.indigo

    static let clean = Color.green
    static let dirty = Color(red: 0.95, green: 0.62, blue: 0.10)   // amber
    static let diverged = Color.blue

    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let cardStroke = Color.primary.opacity(0.08)

    /// 히트맵/스파크라인 강도 색(accent 기반 단계).
    static func heatColor(intensity: Double) -> Color {
        // intensity 0...1
        if intensity <= 0 { return Color.primary.opacity(0.06) }
        return accent.opacity(0.15 + 0.85 * min(intensity, 1))
    }
}

// MARK: - 표시용 포맷 (모든 숫자는 정수화/반올림)

enum Fmt {
    /// "3m ago", "2h ago", "5d ago"
    static func relative(_ date: Date?) -> String {
        guard let date else { return "—" }
        let s = Int(Date().timeIntervalSince(date))
        if s < 60 { return "\(max(s, 0))s ago" }
        let m = s / 60
        if m < 60 { return "\(m)m ago" }
        let h = m / 60
        if h < 24 { return "\(h)h ago" }
        let d = h / 24
        if d < 30 { return "\(d)d ago" }
        let mo = d / 30
        if mo < 12 { return "\(mo)mo ago" }
        return "\(mo / 12)y ago"
    }

    /// 큰 수 축약: 1234 → "1.2k"
    static func compact(_ n: Int) -> String {
        if n < 1000 { return "\(n)" }
        let k = Double(n) / 1000
        return String(format: "%.1fk", k)
    }

    static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
