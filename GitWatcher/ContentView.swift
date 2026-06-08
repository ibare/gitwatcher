//
//  ContentView.swift
//  GitWatcher
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        DashboardView()
    }
}

#Preview {
    ContentView()
        .environment(RepoStore())
}
