import AppKit
import SwiftUI
import UserNotifications
import ServiceManagement
import CAPlateWatchCore

@MainActor
final class Store: ObservableObject {
    @Published var plates: [Plate] = []
    @Published var checking: UUID?
    @Published var message: String?
    @Published var loginEnabled = false
    @Published var notificationStatus = ""
    @Published var notificationsAllowed = false
    @Published var notificationsDenied = false
    var changed: (() -> Void)?
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?
    @Published private(set) var running = false
    private var persistenceFailed = false
    private let file: URL

    init() {
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CA Plate Watch/watchlist.json")
        do {
            _ = try LegacyMigration.importWatchlist(in: file.deletingLastPathComponent().deletingLastPathComponent())
            if FileManager.default.fileExists(atPath: file.path) {
                plates = try JSONDecoder().decode([Plate].self, from: Data(contentsOf: file))
            }
        } catch {
            persistenceFailed = true
            message = "Could not read the saved watchlist. Your file has been preserved: \(error.localizedDescription)"
        }
        refreshLogin()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.checkDue() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in await self?.checkDue() } }
        Task { await refreshNotifications(); await checkDue() }
    }

    func add(_ text: String) -> Bool {
        guard !persistenceFailed else { return false }
        do {
            let plate = try Plate(text: text)
            guard !plates.contains(where: { $0.text == plate.text }) else {
                message = "That plate is already on your watchlist."
                return false
            }
            plates.append(plate)
            save()
            Task { await checkDue() }
            return true
        } catch { message = error.localizedDescription; return false }
    }

    func remove(_ id: UUID) {
        plates.removeAll { $0.id == id }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        save()
    }

    func acknowledge() {
        for index in plates.indices { plates[index].unread = false }
        save()
    }

    func save() {
        defer { changed?() }
        guard !persistenceFailed else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(plates).write(to: file, options: .atomic)
        } catch { message = "Could not save watchlist: \(error.localizedDescription)" }
    }

    func checkDue(force: Bool = false) async {
        guard !running, !persistenceFailed else { return }
        running = true
        defer { running = false; checking = nil; changed?() }
        // Each plate has its own persisted deadline. Missed checks run once after wake.
        let due = plates.filter { force || $0.isDue(at: Date()) }.map(\.id)
        for id in due {
            guard let plate = plates.first(where: { $0.id == id }) else { continue }
            checking = id
            changed?()
            let result: Result<Availability, Error>
            do { result = .success(try await Checker.check(plate.text)) }
            catch { result = .failure(error) }
            guard let index = plates.firstIndex(where: { $0.id == id }) else { continue }
            let alert = plates[index].record(result, at: Date())
            save()
            if alert { await notify(plates[index]) }
        }
    }

    func notify(_ plate: Plate) async {
        let content = UNMutableNotificationContent()
        content.title = "\(plate.text) is available"
        content.body = "The DMV checker reports availability. Open CA Plate Watch to visit the DMV and order."
        content.sound = .default
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: plate.id.uuidString, content: content, trigger: nil))
        } catch { message = "Notification could not be delivered: \(error.localizedDescription)" }
    }

    func requestNotifications() async {
        if notificationsDenied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) }
        catch { message = error.localizedDescription }
        await refreshNotifications()
    }

    func refreshNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = [.authorized, .provisional].contains(settings.authorizationStatus)
        notificationsDenied = settings.authorizationStatus == .denied
        switch settings.authorizationStatus {
        case .authorized, .provisional: notificationStatus = "Notifications enabled"
        case .denied: notificationStatus = "Notifications disabled in System Settings"
        default: notificationStatus = "Enable notifications to receive availability alerts"
        }
    }

    func refreshLogin() { loginEnabled = SMAppService.mainApp.status == .enabled }

    func setLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval {
                message = "Allow CA Plate Watch in System Settings → General → Login Items."
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch { message = "Could not update launch at login: \(error.localizedDescription)" }
        refreshLogin()
    }
}
