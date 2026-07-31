import SwiftUI

struct ChallengeView: View {
    @EnvironmentObject private var store: AlarmStore
    @StateObject private var counter = PushUpCounter()
    @State private var showEmergency = false

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreview(session: counter.session).ignoresSafeArea()
            LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("\(counter.count) / 15").font(.system(size: 54, weight: .bold, design: .rounded)).monospacedDigit()
                Text("Complete 15 push-ups to dismiss the alarm").font(.headline)
                Text(counter.status).font(.subheadline).foregroundStyle(.secondary)
                Button("Emergency code") { showEmergency = true }.buttonStyle(.bordered)
            }
            .foregroundStyle(.white).padding(.bottom, 42).padding(.horizontal)
        }
        .task { await counter.start() }
        .onChange(of: counter.count) { _, value in if value >= 15 { store.finishChallenge() } }
        .sheet(isPresented: $showEmergency) { EmergencyDismissView() }
    }
}

private struct EmergencyDismissView: View {
    @EnvironmentObject private var store: AlarmStore
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var invalid = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Enter the 20-digit emergency code") {
                    TextField("00000000000000000000", text: $code).keyboardType(.numberPad).font(.system(.body, design: .monospaced))
                    if invalid { Text("That code is not valid.").foregroundStyle(.red) }
                }
                Button("Dismiss Alarm", role: .destructive) {
                    if store.emergencyDismiss(code: code) { dismiss() } else { invalid = true }
                }.disabled(code.count != 20)
            }.navigationTitle("Emergency Dismiss").toolbar { Button("Cancel") { dismiss() } }
        }
    }
}
