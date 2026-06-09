//
//  MaterialIconTheme.swift
//  GitWatcher
//
//  VS Code Material Icon Theme 매핑을 로드해 파일/폴더 이름 → 컬러 SVG 아이콘으로 변환한다.
//  아이콘과 매핑(material-icons.json)은 번들 리소스로 내장(로컬 전용).
//

import AppKit

@MainActor
final class MaterialIconTheme {
    static let shared = MaterialIconTheme()

    private var fileExtensions: [String: String] = [:]
    private var fileNames: [String: String] = [:]
    private var folderNames: [String: String] = [:]
    private var folderNamesExpanded: [String: String] = [:]
    private var iconDefinitions: [String: String] = [:]   // iconName → svg 파일명(확장자 제외)
    private var defaultFile = "file"
    private var defaultFolder = "folder"
    private var defaultFolderExpanded = "folder-open"

    private var imageCache: [String: NSImage] = [:]

    private init() { load() }

    // MARK: 매핑 로드

    private func load() {
        guard let url = bundleURL("material-icons", "json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        fileExtensions = json["fileExtensions"] as? [String: String] ?? [:]
        fileNames = json["fileNames"] as? [String: String] ?? [:]
        folderNames = json["folderNames"] as? [String: String] ?? [:]
        folderNamesExpanded = json["folderNamesExpanded"] as? [String: String] ?? [:]
        defaultFile = json["file"] as? String ?? "file"
        defaultFolder = json["folder"] as? String ?? "folder"
        defaultFolderExpanded = json["folderExpanded"] as? String ?? "folder-open"

        if let defs = json["iconDefinitions"] as? [String: [String: String]] {
            for (name, def) in defs {
                if let path = def["iconPath"] {
                    iconDefinitions[name] = (path as NSString).lastPathComponent
                        .replacingOccurrences(of: ".svg", with: "")
                }
            }
        }
    }

    // MARK: 이름 → 아이콘

    func iconName(forFile fileName: String) -> String {
        let lower = fileName.lowercased()
        if let n = fileNames[lower] { return n }
        // 복합 확장자(d.ts, stories.tsx 등) 우선 → 단일 확장자.
        let parts = lower.split(separator: ".")
        if parts.count > 1 {
            for i in 1..<parts.count {
                let ext = parts[i...].joined(separator: ".")
                if let n = fileExtensions[ext] { return n }
            }
        }
        return defaultFile
    }

    func iconName(forFolder folderName: String, expanded: Bool) -> String {
        let lower = folderName.lowercased()
        if expanded {
            if let n = folderNamesExpanded[lower] { return n }
            if let n = folderNames[lower] { return n }   // 펼침 전용이 없으면 일반 폴더 아이콘
            return defaultFolderExpanded
        } else {
            if let n = folderNames[lower] { return n }
            return defaultFolder
        }
    }

    // MARK: 아이콘 이미지

    func image(named iconName: String) -> NSImage? {
        if let cached = imageCache[iconName] { return cached }
        let base = iconDefinitions[iconName] ?? iconName
        guard let url = bundleURL(base, "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        imageCache[iconName] = image
        return image
    }

    // MARK: 번들 경로 (MaterialIcons folder reference — 폴더 구조 그대로 번들에 복사됨)

    private func bundleURL(_ name: String, _ ext: String) -> URL? {
        let b = Bundle.main
        return b.url(forResource: name, withExtension: ext, subdirectory: "MaterialIcons/icons")
            ?? b.url(forResource: name, withExtension: ext, subdirectory: "MaterialIcons")
            ?? b.url(forResource: name, withExtension: ext)
    }
}
