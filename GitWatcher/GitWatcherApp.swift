//
//  GitWatcherApp.swift
//  GitWatcher
//
//  여러 로컬 git 리포의 변경 현황을 한 화면에서 실시간 모니터링하는 읽기 전용 도구.
//

import SwiftUI

@main
struct GitWatcherApp: App {
    @State private var store = RepoStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .frame(minWidth: 720, minHeight: 480)
        }
        .defaultSize(width: 1100, height: 760)
    }
}
