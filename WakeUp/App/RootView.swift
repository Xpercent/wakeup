import SwiftUI
import UIKit

struct RootView: View {
    @EnvironmentObject private var alarmStore: AlarmStore

    var body: some View {
        Group {
            if alarmStore.isChallengeActive {
                ChallengeView()
            } else {
                AlarmSetupView()
            }
        }
        .alert("WakeUp", isPresented: Binding(get: { alarmStore.errorMessage != nil }, set: { if !$0 { alarmStore.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(alarmStore.errorMessage ?? "") }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            alarmStore.activateIfDue()
        }
    }
}

private struct AlarmSetupView: View {
    @EnvironmentObject private var store: AlarmStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Alarm") {
                    DatePicker("Time", selection: $store.alarmTime, displayedComponents: .hourAndMinute)
                    Picker("Sound", selection: $store.tone) {
                        ForEach(AlarmTone.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Stepper("Push-ups: \(store.requiredReps)", value: $store.requiredReps, in: 1...100)
                }
                Section {
                    Button(store.isArmed ? "Update Alarm" : "Set Alarm") { Task { await store.arm() } }
                        .frame(maxWidth: .infinity)
                    if store.isArmed {
                        Button("Turn Off Alarm", role: .destructive) { store.disarm() }
                            .frame(maxWidth: .infinity)
                    }
                }
                if store.isArmed {
                    Section("Emergency code") {
                        Text("Keep this 20-digit code somewhere accessible. It can dismiss an active alarm if the camera challenge is unavailable.")
                            .font(.footnote)
                        Text(store.emergencyCode).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("WakeUp")
        }
    }
}
