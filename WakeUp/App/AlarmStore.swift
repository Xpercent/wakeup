import Foundation
import Combine
import UserNotifications

@MainActor
final class AlarmStore: ObservableObject {
    @Published var alarmTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @Published var tone = AlarmTone.defaultTone
    @Published var requiredReps = 15
    @Published var isArmed = false
    @Published var isChallengeActive = false
    @Published var emergencyCode = ""
    @Published var errorMessage: String?

    private let notificationID = "wakeup.alarm"
    private let defaults = UserDefaults.standard

    func prepare() async {
        do {
            try installNotificationSound()
        } catch {
            errorMessage = "Could not prepare the alarm sound: \(error.localizedDescription)"
        }
        load()
        // Requesting again lets an upgraded app ask for time-sensitive delivery
        // even when ordinary notification permission was granted previously.
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
        activateIfDue()
    }

    func arm() async {
        if tone == .wakeUpAlarm {
            do {
                try installNotificationSound()
            } catch {
                errorMessage = "Could not prepare the alarm sound: \(error.localizedDescription)"
                return
            }
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        let content = UNMutableNotificationContent()
        content.title = "WakeUp"
        content.body = "Open the app and finish your \(requiredReps) push-ups."
        content.sound = tone.notificationSound
        content.interruptionLevel = .timeSensitive
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

    private func installNotificationSound() throws {
        let fileManager = FileManager.default
        guard let bundledSound = Bundle.main.url(forResource: "WakeUpAlarm", withExtension: "wav") else {
            throw SoundInstallationError.resourceMissing
        }
        guard let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw SoundInstallationError.libraryDirectoryUnavailable
        }

        var soundsDirectories = [libraryDirectory.appendingPathComponent("Sounds", isDirectory: true)]

        // LiveContainer redirects HOME to the guest data folder but submits
        // notifications using the host bundle identifier. usernotificationsd
        // therefore resolves custom sounds from the host container instead.
        if let liveContainerHome = ProcessInfo.processInfo.environment["LC_HOME_PATH"], !liveContainerHome.isEmpty {
            let hostSounds = URL(fileURLWithPath: liveContainerHome, isDirectory: true)
                .appendingPathComponent("Library/Sounds", isDirectory: true)
            if !soundsDirectories.contains(where: { $0.standardizedFileURL == hostSounds.standardizedFileURL }) {
                soundsDirectories.append(hostSounds)
            }
        }

        for soundsDirectory in soundsDirectories {
            try fileManager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
            let installedSound = soundsDirectory.appendingPathComponent("WakeUpAlarm.wav")
            if fileManager.fileExists(atPath: installedSound.path) {
                let bundledSize = try bundledSound.resourceValues(forKeys: [.fileSizeKey]).fileSize
                let installedSize = try installedSound.resourceValues(forKeys: [.fileSizeKey]).fileSize
                if bundledSize == installedSize { continue }
                try fileManager.removeItem(at: installedSound)
            }
            try fileManager.copyItem(at: bundledSound, to: installedSound)
        }
    }

    private func save() {
        defaults.set(alarmTime.timeIntervalSinceReferenceDate, forKey: "alarmTime")
        defaults.set(tone.rawValue, forKey: "tone")
        defaults.set(requiredReps, forKey: "requiredReps")
        defaults.set(isArmed, forKey: "isArmed")
        if isArmed { ensureEmergencyCode() }
    }

    private func load() {
        if defaults.object(forKey: "alarmTime") != nil {
            alarmTime = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: "alarmTime"))
        }
        tone = AlarmTone(rawValue: defaults.string(forKey: "tone") ?? "") ?? .defaultTone
        if defaults.object(forKey: "requiredReps") != nil {
            requiredReps = max(1, min(defaults.integer(forKey: "requiredReps"), 100))
        }
        isArmed = defaults.bool(forKey: "isArmed")
        emergencyCode = defaults.string(forKey: "emergencyCode") ?? ""
        if isArmed { ensureEmergencyCode() }
    }
}

private enum SoundInstallationError: LocalizedError {
    case resourceMissing
    case libraryDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .resourceMissing: return "WakeUpAlarm.wav is missing from the app bundle."
        case .libraryDirectoryUnavailable: return "The app Library directory is unavailable."
        }
    }
}

enum AlarmTone: String, CaseIterable, Identifiable {
    case defaultTone = "System Default"
    case wakeUpAlarm = "WakeUp Alarm"
    var id: String { rawValue }
    var notificationSound: UNNotificationSound {
        self == .defaultTone ? .default : UNNotificationSound(named: UNNotificationSoundName(rawValue: "WakeUpAlarm.wav"))
    }
}
