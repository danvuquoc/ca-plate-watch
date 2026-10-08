import BackgroundTasks
import CAPlateWatchCore
import Foundation
import UserNotifications

@MainActor
final class WatchStore: ObservableObject {
    static let shared = WatchStore()
    static let refreshIdentifier = "local.CAPlateWatch.iOS.refresh"

    @Published private(set) var plates: [Plate] = []
    @Published private(set) var recheckInterval: RecheckInterval
    @Published private(set) var checking: UUID?
    @Published private(set) var running = false
    @Published private(set) var notificationsAllowed = false
    @Published private(set) var notificationsDenied = false
    @Published var message: String?

    private let file: URL
    private let defaults: UserDefaults
    private var persistenceFailed = false
    private var timer: Timer?

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        recheckInterval = RecheckInterval.load(from: defaults)
        file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CA Plate Watch/watchlist.json")
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                plates = try JSONDecoder().decode([Plate].self, from: Data(contentsOf: file))
            }
        } catch {
            persistenceFailed = true
            message = "Could not read the saved watchlist. The file has been preserved: \(error.localizedDescription)"
        }
        // A NEW marker belongs to the previous app run. Keep the watchlist and
        // confirmed availability, but start this run without old markers.
        if !persistenceFailed && plates.contains(where: \.unread) {
            let previous = plates
            for index in plates.indices { plates[index].unread = false }
            if !save() { plates = previous }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in _ = await self?.checkDue() }
        }
    }

    @discardableResult
    func add(_ text: String, vehicleType: VehicleType, designID: String, veteranDecalID: String?) -> Bool {
        guard !persistenceFailed else { return false }
        do {
            let plate = try Plate(text: text, vehicleType: vehicleType, designID: designID, veteranDecalID: veteranDecalID)
            guard !plates.contains(where: { $0.matchesSelection(of: plate) }) else {
                message = "That plate, vehicle type, and design are already on your watchlist."
                return false
            }
            plates.append(plate)
            guard save() else {
                plates.removeLast()
                return false
            }
            scheduleBackgroundRefresh()
            Task { _ = await checkDue() }
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }

    func remove(_ id: UUID) {
        guard !persistenceFailed else { return }
        let previous = plates
        plates.removeAll { $0.id == id }
        guard save() else {
            plates = previous
            return
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        scheduleBackgroundRefresh()
    }

    func setRecheckInterval(_ interval: RecheckInterval) {
        recheckInterval = interval
        defaults.set(interval.rawValue, forKey: RecheckInterval.preferenceKey)
        scheduleBackgroundRefresh()
        Task { _ = await checkDue() }
    }

    /// One pass attempts each due plate at most once. Cancellation leaves the current plate due.
    @discardableResult
    func checkDue(force: Bool = false, maxAttempts: Int? = nil) async -> Bool {
        guard !persistenceFailed else { return false }
        guard !running else { return true }
        running = true
        defer {
            running = false
            checking = nil
            scheduleBackgroundRefresh()
        }
        var attempted = Set<UUID>()
        while !Task.isCancelled,
              let plate = CheckSchedule.nextPlate(in: plates, at: Date(), interval: recheckInterval.seconds,
                                                  attempted: attempted, force: force) {
            attempted.insert(plate.id)
            checking = plate.id
            let result: Result<Availability, Error>
            do { result = .success(try await DMVClient().check(plate)) }
            catch {
                if Task.isCancelled { break }
                result = .failure(error)
            }
            if Task.isCancelled { break }
            guard let index = plates.firstIndex(where: { $0.id == plate.id }) else { continue }
            let previous = plates[index]
            let shouldAlert = plates[index].record(result, at: Date())
            guard save() else {
                plates[index] = previous
                break
            }
            if shouldAlert { await notify(plates[index]) }
            if let maxAttempts, attempted.count >= maxAttempts { break }
        }
        return !Task.isCancelled
    }

    func scheduleBackgroundRefresh() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshIdentifier)
        guard !persistenceFailed, !plates.isEmpty else { return }
        let nextDue = plates.map { $0.lastAttempt?.addingTimeInterval(recheckInterval.seconds) ?? Date() }.min() ?? Date()
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshIdentifier)
        request.earliestBeginDate = max(nextDue, Date().addingTimeInterval(15 * 60))
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // A declined request must not hide a confirmed DMV result or block manual checks.
            NSLog("CA Plate Watch background refresh unavailable: %@", error.localizedDescription)
        }
    }

    func refreshNotifications() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationsAllowed = [.authorized, .provisional].contains(settings.authorizationStatus)
        notificationsDenied = settings.authorizationStatus == .denied
    }

    func requestNotifications() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            message = error.localizedDescription
        }
        await refreshNotifications()
    }

    private func notify(_ plate: Plate) async {
        let content = UNMutableNotificationContent()
        content.title = plate.notificationTitle
        content.body = plate.notificationBody
        content.sound = .default
        do {
            try await UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier: plate.id.uuidString, content: content, trigger: nil))
        } catch {
            message = "Notification could not be delivered: \(error.localizedDescription)"
        }
    }

    @discardableResult
    private func save() -> Bool {
        guard !persistenceFailed else { return false }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(plates).write(to: file, options: .atomic)
            return true
        } catch {
            persistenceFailed = true
            message = "Could not save the watchlist: \(error.localizedDescription)"
            return false
        }
    }
}
