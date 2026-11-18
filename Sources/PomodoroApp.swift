import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement

@main
struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var timer = PomodoroTimer()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(timer)
        } label: {
            // Idle: just the dot ring (the app's icon). Running: minutes + filling ring.
            Image(nsImage: SecondDots.menuBarLabel(minutes: timer.isActive ? timer.minutesLeft : nil,
                                                   lit: timer.litDots,
                                                   showCup: timer.phase == .rest))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Open at login by default (once); the popover's checkbox can turn it off.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "loginItemConfigured") {
            try? SMAppService.mainApp.register()
            defaults.set(true, forKey: "loginItemConfigured")
        }

        // `open Pomodoro.app --args --rocket` previews the break animation.
        if CommandLine.arguments.contains("--rocket") {
            RocketLaunch.play()
        }
        // `--focus-edge` previews the right-edge focus line for 15 seconds (two pulses).
        if CommandLine.arguments.contains("--focus-edge") {
            Task { @MainActor in
                FocusEdge.update(.running)
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                FocusEdge.update(.hidden)
            }
        }
    }

    // Show the banner even while the app is "frontmost" (it always is, as a menu bar app).
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
