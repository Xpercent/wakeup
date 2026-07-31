import SwiftUI

@main
struct WakeUpApp: App {
    @StateObject private var alarmStore = AlarmStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(alarmStore)
                .task { await alarmStore.prepare() }
        }
    }
}
