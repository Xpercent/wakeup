import Foundation
import Combine
import UserNotifications

@MainActor
final class AlarmStore: ObservableObject {
    @Published var alarmTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @Published var tone = AlarmTone.defaultTone
    @Published var isArmed = false
    @Published var isChallengeActive = false
    @Published var emergencyCode = ""
    @Published var errorMessage: String?

    private let notificationID = "wakeup.alarm"
    private let defaults = UserDefaults.standard

    func prepare() async {
        load()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        activateIfDue()
    }

    func arm() async {
        let components = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        let content = UNMutableNotificationContent()
        content.title = "WakeUp"
        content.body = "Open the app and finish your 15 push-ups."
        content.sound = tone.notificationSound
        content.categoryIdentifier = "WAKEUP_ALARM"

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        do {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
            try await UNUserNotificationCenter.current().add(request)
            isArmed = true
            save()
        } catch {
            errorMessage = "Could not schedule the alarm: \(error.localizedDescription)"
        }
    }

    func disarm() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        isArmed = false
        isChallengeActive = false
        save()
    }

    func activateIfDue() {
        guard isArmed else { return }
        let now = Date()
        let todayAlarm = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: alarmTime), minute: Calendar.current.component(.minute, from: alarmTime), second: 0, of: now) ?? now
        // Keep the challenge available for 15 minutes after today's scheduled alarm.
        if now >= todayAlarm && now.timeIntervalSince(todayAlarm) < 15 * 60 {
            isChallengeActive = true
            ensureEmergencyCode()
        }
    }

    func finishChallenge() { disarm() }

    func emergencyDismiss(code: String) -> Bool {
        guard code == emergencyCode, code.count == 20 else { return false }
        disarm()
        return true
    }

    private func ensureEmergencyCode() {
        if emergencyCode.count != 20 {
            emergencyCode = (0..<20).map { _ in String(Int.random(in: 0...9)) }.joined()
            defaults.set(emergencyCode, forKey: "emergencyCode")
        }
    }

    private func save() {
        defaults.set(alarmTime.timeIntervalSinceReferenceDate, forKey: "alarmTime")
        defaults.set(tone.rawValue, forKey: "tone")
        defaults.set(isArmed, forKey: "isArmed")
        if isArmed { ensureEmergencyCode() }
    }

    private func load() {
        if defaults.object(forKey: "alarmTime") != nil {
            alarmTime = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: "alarmTime"))
        }
        tone = AlarmTone(rawValue: defaults.string(forKey: "tone") ?? "") ?? .defaultTone
        isArmed = defaults.bool(forKey: "isArmed")
        emergencyCode = defaults.string(forKey: "emergencyCode") ?? ""
        if isArmed { ensureEmergencyCode() }
    }
}

enum AlarmTone: String, CaseIterable, Identifiable {
    case defaultTone = "Default"
    case alarm = "Alarm"
    case alert = "Alert"
    var id: String { rawValue }
    // Named CAF files can be added later; keep every selection functional until then.
    var notificationSound: UNNotificationSound { .default }
}
