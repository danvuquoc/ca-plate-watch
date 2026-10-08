import BackgroundTasks
import SwiftUI
import UIKit
import UserNotifications

@main
struct CAPlateWatchiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = WatchStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchView(store: store)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await store.refreshNotifications()
                    await store.checkDue()
                }
            } else if phase == .background {
                store.scheduleBackgroundRefresh()
            }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        BGTaskScheduler.shared.register(forTaskWithIdentifier: WatchStore.refreshIdentifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let worker = Task { @MainActor in
                let success = await WatchStore.shared.checkDue(maxAttempts: 1)
                WatchStore.shared.scheduleBackgroundRefresh()
                refresh.setTaskCompleted(success: success)
            }
            refresh.expirationHandler = { worker.cancel() }
        }
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
