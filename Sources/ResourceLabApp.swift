import SwiftUI

@main
struct ResourceLabApp: App {
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Arizona · Resource Lab").font(.title2.bold())
                    Text("arrow.dff · 138 вершин · 52 треугольника")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding()
                MetalMeshView(active: scenePhase == .active)
                Text("Проведи пальцем, чтобы повернуть модель")
                    .font(.footnote).foregroundStyle(.secondary).padding()
            }
            .preferredColorScheme(.dark)
        }
    }
}
