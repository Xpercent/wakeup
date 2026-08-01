import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var alarmStore: AlarmStore
    private let alarmCheck = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

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
        .onReceive(alarmCheck) { _ in alarmStore.activateIfDue() }
    }
}

private struct AlarmSetupView: View {
    @EnvironmentObject private var store: AlarmStore
    @State private var showSoundImporter = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Alarm") {
                    DatePicker("Time", selection: $store.alarmTime, displayedComponents: .hourAndMinute)
                    Picker("Sound", selection: $store.selectedSoundFile) {
                        ForEach(store.soundFiles, id: \.self) { Text($0).tag($0) }
                    }
                    Button {
                        showSoundImporter = true
                    } label: {
                        Label("Add Sound", systemImage: "plus")
                    }
                    Stepper("Push-ups: \(store.requiredReps)", value: $store.requiredReps, in: 1...100)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("App volume")
                            Spacer()
                            Text("\(Int(store.playbackVolume * 100))%")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $store.playbackVolume, in: 0...1, step: 0.05)
                    }
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
            .fileImporter(isPresented: $showSoundImporter, allowedContentTypes: [.wav]) { result in
                switch result {
                case .success(let url): store.importSound(from: url)
                case .failure(let error): store.errorMessage = "Could not select the sound: \(error.localizedDescription)"
                }
            }
        }
    }
}
