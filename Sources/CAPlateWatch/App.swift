import AppKit
import SwiftUI
import UserNotifications
import CAPlateWatchCore

@main
struct CAPlateWatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var store: Store!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Finder opens an existing instance; also guard direct executable launches.
        let peers = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "local.CAPlateWatch")
        if peers.contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        UNUserNotificationCenter.current().delegate = self
        store = Store()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 410, height: 580)
        popover.contentViewController = NSHostingController(rootView: WatchView(store: store))
        store.changed = { [weak self] in self?.updateIcon() }
        updateIcon()
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            show()
        }
    }

    func updateIcon() {
        let count = store.plates.filter(\.unread).count
        let badge: PlateArtwork.Badge = count > 0 ? .available : (store.plates.contains { $0.error != nil } ? .error : .none)
        item.button?.image = PlateArtwork.menuIcon(badge: badge)
        item.button?.title = count > 0 ? " \(count)" : ""
        item.button?.toolTip = count > 0 ? "CA Plate Watch — \(count) new availability alerts" : "CA Plate Watch"
    }

    @objc func toggle() { if popover.isShown { popover.performClose(nil) } else { show() } }
    func show() {
        guard let button = item?.button else { return }
        store.refreshLogin()
        Task { await store.refreshNotifications() }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
        popover.contentViewController?.view.window?.makeKey()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in self.show(); completionHandler() }
    }
}

struct WatchView: View {
    @ObservedObject var store: Store
    @State private var input = ""
    private let dmv = URL(string: "https://www.dmv.ca.gov/wasapp/ipp2/initPers.do")!

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(nsImage: PlateArtwork.plate(size: NSSize(width: 60, height: 32)))
                    .accessibilityLabel("California license plate")
                VStack(alignment: .leading, spacing: 2) {
                    Text("CA Plate Watch").font(.title2.bold())
                    Text("CALIFORNIA · EVERY 6 HOURS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await store.checkDue(force: true) }
                } label: {
                    ZStack {
                        if store.running {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise").font(.system(size: 16, weight: .medium))
                        }
                    }.frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .disabled(store.running || store.plates.isEmpty)
                .accessibilityLabel(store.running ? "Checking plates" : "Recheck all")
                .help("Recheck all plates")
            }
            HStack {
                TextField("Plate (e.g. SUNSHNE)", text: $input).textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .accessibilityLabel("License plate to watch")
                Button("Add", action: add).buttonStyle(.borderedProminent).disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ScrollView {
                LazyVStack(spacing: 10) {
                    if store.plates.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "binoculars").font(.system(size: 32)).foregroundStyle(.secondary)
                            Text("Your next plate starts here").font(.headline)
                            Text("Add a plate to watch for availability.").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity).padding(.vertical, 40)
                    }
                    ForEach(store.plates) { plate in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(plate.text).font(.system(size: 20, weight: .bold, design: .monospaced))
                                if plate.unread { Circle().fill(.green).frame(width: 7, height: 7) }
                                Spacer()
                                Button { store.remove(plate.id) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless).foregroundStyle(.secondary)
                                    .help("Remove \(plate.text)").accessibilityLabel("Remove \(plate.text)")
                            }
                            if store.checking == plate.id {
                                Label("Checking DMV…", systemImage: "arrow.triangle.2.circlepath").font(.caption)
                            } else if let error = plate.error {
                                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                            } else {
                                Text(status(plate)).font(.caption.weight(.medium))
                                    .foregroundStyle(plate.availability == .available ? .green : .secondary)
                            }
                            if let last = plate.lastSuccess {
                                Text("Last confirmed: \(last.formatted(date: .abbreviated, time: .shortened)) · \(plate.availability.rawValue)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                            if let last = plate.lastAttempt {
                                Text("Next check: \(last.addingTimeInterval(Plate.interval).formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }.frame(minHeight: 150, maxHeight: .infinity)
            if store.plates.contains(where: \.unread) {
                Button("Mark availability alerts as seen") { store.acknowledge() }.font(.caption)
            }
            Divider()
            Toggle("Launch at login", isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) }))
                .toggleStyle(.switch).controlSize(.small)
            HStack {
                Text(store.notificationStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !store.notificationsAllowed {
                    Button(store.notificationsDenied ? "Settings" : "Enable") {
                        Task { await store.requestNotifications() }
                    }.controlSize(.small)
                }
            }
            Text("Checks run while your Mac is awake. Missed checks resume after wake or launch.")
                .font(.caption2).foregroundStyle(.secondary)
            HStack {
                Link("Open California DMV ↗", destination: dmv)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }.buttonStyle(.borderless)
            }.font(.caption)
        }
        .padding(20).frame(width: 410, height: 580)
        .alert("CA Plate Watch", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
            Button("OK") { store.message = nil }
        } message: { Text(store.message ?? "") }
    }

    private func add() { if store.add(input) { input = "" } }
    private func status(_ plate: Plate) -> String {
        switch plate.availability {
        case .available: return "Available — visit DMV to order"
        case .unavailable: return "Unavailable · watching for a change"
        case .unknown: return "Waiting for first check"
        }
    }
}
