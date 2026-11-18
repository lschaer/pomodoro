import Foundation
import AppKit
import UserNotifications
import ServiceManagement

/// One finished focus session.
struct LogEntry: Codable, Identifiable {
    var id = UUID()
    let start: Date
    let task: String
    let minutes: Int
}

@MainActor
final class PomodoroTimer: ObservableObject {
    enum Phase {
        case focus, rest
        var label: String { self == .focus ? "Focus" : "Break" }
    }

    static let focusOptions = [10, 15, 20, 25, 30, 45, 50]
    static let lunchMinutes = 60
    static let breakOptions = [5, 10, 15, lunchMinutes]
    /// Dots in the seconds ring — each one stands for 60 / dotCount seconds.
    nonisolated static let dotCount = 12

    private let defaults = UserDefaults.standard
    private let notificationID = "pomodoro.phase.end"
    private let logKey = "sessionLog"

    @Published private(set) var phase: Phase = .focus { didSet { updateFocusEdge() } }
    @Published private(set) var remaining: TimeInterval = 25 * 60 { didSet { updateFocusEdge() } }
    @Published private(set) var isRunning = false { didSet { updateFocusEdge() } }
    @Published private(set) var log: [LogEntry] = []

    @Published var task: String = "" {
        didSet { defaults.set(task, forKey: "task") }
    }
    /// Once a focus session starts, the topic is fixed until you clear it yourself.
    @Published private(set) var taskLocked = false {
        didSet { defaults.set(taskLocked, forKey: "taskLocked") }
    }
    @Published var focusMinutes: Int = 25 {
        didSet { defaults.set(focusMinutes, forKey: "focusMinutes"); resetIfIdle() }
    }
    @Published var breakMinutes: Int = 5 {
        didSet { defaults.set(breakMinutes, forKey: "breakMinutes"); resetIfIdle() }
    }

    /// Mirrors the system login item; toggling it registers/unregisters the app.
    @Published var openAtLogin = SMAppService.mainApp.status == .enabled {
        didSet {
            guard openAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if openAtLogin { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                refreshLoginItem()
            }
        }
    }

    func refreshLoginItem() {
        let enabled = SMAppService.mainApp.status == .enabled
        if openAtLogin != enabled { openAtLogin = enabled }
    }

    private var endDate: Date?
    private var ticker: Timer?
    private var activity: NSObjectProtocol?

    init() {
        task = defaults.string(forKey: "task") ?? ""
        taskLocked = defaults.bool(forKey: "taskLocked") && !task.isEmpty
        focusMinutes = defaults.object(forKey: "focusMinutes") as? Int ?? 25
        breakMinutes = defaults.object(forKey: "breakMinutes") as? Int ?? 5
        remaining = duration
        if let data = defaults.data(forKey: logKey),
           let saved = try? JSONDecoder().decode([LogEntry].self, from: data) {
            log = saved
        }
    }

    // MARK: Derived state

    var duration: TimeInterval { Double(phase == .focus ? focusMinutes : breakMinutes) * 60 }
    var isPaused: Bool { !isRunning && remaining < duration }
    var isActive: Bool { isRunning || isPaused }
    var progress: Double { duration > 0 ? 1 - remaining / duration : 0 }

    var todayLog: [LogEntry] { log.filter { Calendar.current.isDateInToday($0.start) } }
    var completedToday: Int { todayLog.count }

    private var wholeSeconds: Int { max(0, Int(remaining.rounded(.up))) }

    var timeString: String {
        String(format: "%02d:%02d", wholeSeconds / 60, wholeSeconds % 60)
    }

    /// Whole minutes left, shown as the main number.
    var minutesLeft: Int { wholeSeconds / 60 }

    /// The ring starts each minute full and one dot goes out every 60/dotCount seconds,
    /// so it is empty right as the minute number ticks down. Full while idle.
    var litDots: Int {
        guard isActive else { return Self.dotCount }
        let secs = wholeSeconds % 60
        let step = 60 / Self.dotCount
        return (secs + step - 1) / step
    }

    // MARK: Controls

    func toggle() { isRunning ? pause() : start() }

    /// The topic can be cleared any time except during a focus session.
    var canClearTask: Bool { !(phase == .focus && isActive) }

    func clearTask() {
        guard canClearTask else { return }
        task = ""
        taskLocked = false
    }

    func start() {
        guard !isRunning else { return }
        task = task.trimmingCharacters(in: .whitespaces)
        if phase == .focus && !task.isEmpty { taskLocked = true }
        endDate = Date().addingTimeInterval(remaining)
        isRunning = true
        scheduleNotification(in: remaining)
        activity = ProcessInfo.processInfo.beginActivity(options: .userInitiated,
                                                         reason: "Pomodoro timer running")
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func pause() {
        guard isRunning else { return }
        tick()
        stopTicking()
        cancelNotification()
    }

    func reset() {
        stopTicking()
        cancelNotification()
        remaining = duration
    }

    /// Jump to the next phase without logging the current one.
    func skip() {
        stopTicking()
        cancelNotification()
        phase = phase == .focus ? .rest : .focus
        remaining = duration
    }

    /// Today's log as plain text, e.g. for pasting into a timesheet.
    func copyTodayLog() {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let text = todayLog.map { "\(f.string(from: $0.start))\t\($0.minutes) min\t\($0.task)" }
                           .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: Internals

    private func tick() {
        guard let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow)
        if remaining <= 0 { finishPhase() }
    }

    private func finishPhase() {
        stopTicking()
        NSSound(named: "Glass")?.play()
        if phase == .focus {
            logSession()
            RocketLaunch.play()
        }
        phase = phase == .focus ? .rest : .focus
        remaining = duration
    }

    private func logSession() {
        let name = task.trimmingCharacters(in: .whitespaces)
        log.append(LogEntry(start: Date().addingTimeInterval(-Double(focusMinutes) * 60),
                            task: name.isEmpty ? "Untitled" : name,
                            minutes: focusMinutes))
        if log.count > 1000 { log.removeFirst(log.count - 1000) }
        saveLog()
    }

    private func saveLog() {
        if let data = try? JSONEncoder().encode(log) { defaults.set(data, forKey: logKey) }
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
        endDate = nil
        isRunning = false
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }

    /// Right-edge line: on while focusing, dim while a focus session is paused.
    private func updateFocusEdge() {
        guard phase == .focus else { return FocusEdge.update(.hidden) }
        FocusEdge.update(isRunning ? .running : (isPaused ? .paused : .hidden))
    }

    private func resetIfIdle() {
        if !isActive { remaining = duration }
    }

    // Scheduled with the system up front, so it fires on time even if the app is throttled.
    private func scheduleNotification(in seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        let name = task.trimmingCharacters(in: .whitespaces)
        let isLunch = breakMinutes == Self.lunchMinutes
        let breakText = isLunch ? "time for lunch!" : "time for a \(breakMinutes)-minute break."
        if phase == .focus {
            content.title = "Focus session done"
            content.body = name.isEmpty ? breakText.prefix(1).uppercased() + breakText.dropFirst()
                                        : "\(name) — logged. Now \(breakText)"
        } else {
            content.title = isLunch ? "Lunch is over" : "Break is over"
            content.body = name.isEmpty ? "What are you working on next?" : "Back to: \(name)"
        }
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }
}
