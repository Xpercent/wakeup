import Foundation
import Combine
import UserNotifications
import AVFoundation

@MainActor
final class AlarmStore: ObservableObject {
    @Published var alarmTime = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @Published var soundFiles: [String] = []
    @Published var selectedSoundFile = "Alarm-radar.wav"
    @Published var requiredReps = 15
    @Published var isArmed = false
    @Published var isChallengeActive = false
    @Published var emergencyCode = ""
    @Published var errorMessage: String?

    private let notificationID = "wakeup.alarm"
    private let dailyNotificationID = "wakeup.alarm.daily"
    private let burstNotificationPrefix = "wakeup.alarm.burst."
    private let burstCount = 63 // iOS keeps at most 64 pending notifications per app.
    private let defaults = UserDefaults.standard
    private let fileManager = FileManager.default

    var selectedSoundURL: URL? { soundURL(for: selectedSoundFile) }

    func prepare() async {
        load()
        refreshSoundFiles()
        if !soundFiles.contains(selectedSoundFile), let first = soundFiles.first {
            selectedSoundFile = first
        }
        do {
            try installNotificationSound(named: selectedSoundFile)
        } catch {
            errorMessage = "Could not prepare the alarm sound: \(error.localizedDescription)"
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .timeSensitive])
        activateIfDue()
    }

    func arm() async {
        do {
            try installNotificationSound(named: selectedSoundFile)
        } catch {
            errorMessage = "Could not prepare the alarm sound: \(error.localizedDescription)"
            return
        }

        let components = Calendar.current.dateComponents([.hour, .minute], from: alarmTime)
        let content = UNMutableNotificationContent()
        content.title = "WakeUp"
        content.body = "Open the app and finish your \(requiredReps) push-ups."
        content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: selectedSoundFile))
        content.interruptionLevel = .timeSensitive
        content.categoryIdentifier = "WAKEUP_ALARM"

        do {
            removePendingAlarms()
            // Keep a daily notification for future days.
            let dailyTrigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: dailyNotificationID, content: content, trigger: dailyTrigger))

            // The one-shot burst continues the selected sound on the lock screen.
            // The daily notification above plays the first sound.
            let nextAlarm = nextAlarmDate(from: components)
            let burstInterval = notificationRepeatInterval()
            for index in 1..<burstCount {
                let fireDate = nextAlarm.addingTimeInterval(Double(index) * burstInterval)
                let interval = max(1, fireDate.timeIntervalSinceNow)
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                let request = UNNotificationRequest(identifier: "\(burstNotificationPrefix)\(index)", content: content, trigger: trigger)
                try await UNUserNotificationCenter.current().add(request)
            }
            isArmed = true
            save()
        } catch {
            errorMessage = "Could not schedule the alarm: \(error.localizedDescription)"
        }
    }

    func importSound(from sourceURL: URL) {
        guard sourceURL.pathExtension.lowercased() == "wav" else {
            errorMessage = "Please select a WAV audio file."
            return
        }
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }

        do {
            let audio = try AVAudioPlayer(contentsOf: sourceURL)
            guard audio.duration < 30 else {
                errorMessage = "Notification sounds must be shorter than 30 seconds."
                return
            }
            let directory = try importedSoundsDirectory()
            let fileName = sourceURL.lastPathComponent
            let destination = directory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
            refreshSoundFiles()
            selectedSoundFile = fileName
            try installNotificationSound(named: fileName)
            save()
        } catch {
            errorMessage = "Could not import the sound: \(error.localizedDescription)"
        }
    }

    func disarm() {
        removePendingAlarms()
        isArmed = false
        isChallengeActive = false
        save()
    }

    func activateIfDue() {
        guard isArmed else { return }
        let now = Date()
        let todayAlarm = Calendar.current.date(bySettingHour: Calendar.current.component(.hour, from: alarmTime), minute: Calendar.current.component(.minute, from: alarmTime), second: 0, of: now) ?? now
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

    private func refreshSoundFiles() {
        let bundled = Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: nil) ?? []
        let imported = (try? fileManager.contentsOfDirectory(at: importedSoundsDirectory(), includingPropertiesForKeys: nil)) ?? []
        soundFiles = Set((bundled + imported).map(\.lastPathComponent))
            .filter { $0.lowercased().hasSuffix(".wav") }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func nextAlarmDate(from components: DateComponents) -> Date {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: now) ?? now
        return today > now ? today : calendar.date(byAdding: .day, value: 1, to: today) ?? today
    }

    private func removePendingAlarms() {
        var identifiers = [dailyNotificationID]
        identifiers.append(contentsOf: (0..<burstCount).map { "\(burstNotificationPrefix)\($0)" })
        identifiers.append(notificationID)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func notificationRepeatInterval() -> TimeInterval {
        guard let soundURL = selectedSoundURL,
              let audio = try? AVAudioPlayer(contentsOf: soundURL) else { return 15 }
        return min(30, max(2, audio.duration + 0.25))
    }

    private func soundURL(for fileName: String) -> URL? {
        let safeName = URL(fileURLWithPath: fileName).lastPathComponent
        let baseName = (safeName as NSString).deletingPathExtension
        if let bundled = Bundle.main.url(forResource: baseName, withExtension: "wav") { return bundled }
        return try? importedSoundsDirectory().appendingPathComponent(safeName)
    }

    private func importedSoundsDirectory() throws -> URL {
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw SoundInstallationError.libraryDirectoryUnavailable
        }
        let directory = applicationSupport.appendingPathComponent("ImportedSounds", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func installNotificationSound(named fileName: String) throws {
        guard let sourceSound = soundURL(for: fileName), fileManager.fileExists(atPath: sourceSound.path) else {
            throw SoundInstallationError.resourceMissing(fileName)
        }
        guard let libraryDirectory = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            throw SoundInstallationError.libraryDirectoryUnavailable
        }

        var soundsDirectories = [libraryDirectory.appendingPathComponent("Sounds", isDirectory: true)]
        if let liveContainerHome = ProcessInfo.processInfo.environment["LC_HOME_PATH"], !liveContainerHome.isEmpty {
            let hostSounds = URL(fileURLWithPath: liveContainerHome, isDirectory: true)
                .appendingPathComponent("Library/Sounds", isDirectory: true)
            if !soundsDirectories.contains(where: { $0.standardizedFileURL == hostSounds.standardizedFileURL }) {
                soundsDirectories.append(hostSounds)
            }
        }

        for soundsDirectory in soundsDirectories {
            try fileManager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
            let installedSound = soundsDirectory.appendingPathComponent(fileName)
            if fileManager.fileExists(atPath: installedSound.path) {
                try fileManager.removeItem(at: installedSound)
            }
            try fileManager.copyItem(at: sourceSound, to: installedSound)
        }
    }

    private func ensureEmergencyCode() {
        if emergencyCode.count != 20 {
            emergencyCode = (0..<20).map { _ in String(Int.random(in: 0...9)) }.joined()
            defaults.set(emergencyCode, forKey: "emergencyCode")
        }
    }

    private func save() {
        defaults.set(alarmTime.timeIntervalSinceReferenceDate, forKey: "alarmTime")
        defaults.set(selectedSoundFile, forKey: "selectedSoundFile")
        defaults.set(requiredReps, forKey: "requiredReps")
        defaults.set(isArmed, forKey: "isArmed")
        if isArmed { ensureEmergencyCode() }
    }

    private func load() {
        if defaults.object(forKey: "alarmTime") != nil {
            alarmTime = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: "alarmTime"))
        }
        selectedSoundFile = defaults.string(forKey: "selectedSoundFile") ?? "Alarm-radar.wav"
        if defaults.object(forKey: "requiredReps") != nil {
            requiredReps = max(1, min(defaults.integer(forKey: "requiredReps"), 100))
        }
        isArmed = defaults.bool(forKey: "isArmed")
        emergencyCode = defaults.string(forKey: "emergencyCode") ?? ""
        if isArmed { ensureEmergencyCode() }
    }
}

private enum SoundInstallationError: LocalizedError {
    case resourceMissing(String)
    case libraryDirectoryUnavailable

    var errorDescription: String? {
        switch self {
        case .resourceMissing(let fileName): return "\(fileName) is missing."
        case .libraryDirectoryUnavailable: return "The app Library directory is unavailable."
        }
    }
}
