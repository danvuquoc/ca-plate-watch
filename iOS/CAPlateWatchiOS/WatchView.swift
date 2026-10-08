import CAPlateWatchCore
import SwiftUI
import UIKit

struct WatchView: View {
    @ObservedObject var store: WatchStore
    @State private var showingAddPlate = false
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                if store.plates.isEmpty {
                    ContentUnavailableView {
                        Label("No watched plates", systemImage: "car.side")
                    } description: {
                        Text("Add a plate to see its availability here.")
                    } actions: {
                        Button("Watch a plate") { showingAddPlate = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 360)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    Text("Watching \(store.plates.count) \(store.plates.count == 1 ? "plate" : "plates")")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    ForEach(store.plates) { plate in
                        PlateCard(plate: plate, checking: store.checking == plate.id,
                                  interval: store.recheckInterval)
                            .swipeActions(edge: .trailing) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    store.remove(plate.id)
                                }
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("CA Plate Watch")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingAddPlate = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Watch a plate")
                    Button {
                        Task { await store.checkDue(force: true) }
                    } label: {
                        if store.running { ProgressView() }
                        else { Image(systemName: "arrow.clockwise") }
                    }
                    .disabled(store.running || store.plates.isEmpty)
                    .accessibilityLabel(store.running ? "Checking plates" : "Recheck all plates")
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(isPresented: $showingAddPlate) { AddPlateView(store: store) }
            .navigationDestination(isPresented: $showingSettings) { WatchSettingsView(store: store) }
            .alert("CA Plate Watch", isPresented: Binding(
                get: { store.message != nil && !showingAddPlate && !showingSettings },
                set: { if !$0 { store.message = nil } }
            )) {
                Button("OK") { store.message = nil }
            } message: {
                Text(store.message ?? "")
            }
        }
    }
}

private struct PlateCard: View {
    let plate: Plate
    let checking: Bool
    let interval: RecheckInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Text("California")
                        .font(.system(size: 18, weight: .medium, design: .serif))
                        .italic()
                        .foregroundStyle(.red)
                        .frame(height: 24)
                    Text(plate.text)
                        .font(.system(size: 76, weight: .bold, design: .monospaced))
                        .fontWidth(.compressed)
                        .lineLimit(1)
                        .minimumScaleFactor(0.48)
                        .frame(maxWidth: .infinity)
                        .frame(height: 88)
                        .foregroundStyle(Color(red: 0.12, green: 0.25, blue: 0.46))
                }
                .padding(.horizontal, 8)
                .frame(width: 252, height: 120)
                .background(.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.18, green: 0.28, blue: 0.43), lineWidth: 2))
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Label(statusTitle, systemImage: statusIcon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusColor)
                    if plate.unread {
                        Text("NEW")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.12), in: Capsule())
                    }
                    Spacer()
                }
                Text(plate.selectionLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let decalID = plate.veteranDecalID, let decal = VeteranDecal.decal(id: decalID) {
                    Text(decal.name).font(.footnote).foregroundStyle(.secondary)
                }
                if let error = plate.selectionError ?? plate.error, !checking {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
            }

            if let lastAttempt = plate.lastAttempt {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Last Checked: \(lastAttempt.formatted(date: .abbreviated, time: .shortened))")
                    Text("Next Check: \(lastAttempt.addingTimeInterval(interval.seconds).formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var statusTitle: String {
        if checking { return "Checking DMV…" }
        if plate.selectionError != nil || plate.error != nil { return "Check needs attention" }
        switch plate.availability {
        case .available: return "Available"
        case .unavailable: return "Unavailable"
        case .unknown: return "Waiting for first check"
        }
    }

    private var statusIcon: String {
        if checking { return "arrow.triangle.2.circlepath" }
        if plate.selectionError != nil || plate.error != nil { return "exclamationmark.triangle" }
        switch plate.availability {
        case .available: return "checkmark.circle.fill"
        case .unavailable: return "clock"
        case .unknown: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        if checking { return .blue }
        if plate.selectionError != nil || plate.error != nil { return .orange }
        switch plate.availability {
        case .available: return .green
        case .unavailable, .unknown: return .secondary
        }
    }
}

private struct AddPlateView: View {
    @ObservedObject var store: WatchStore
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var vehicleType = VehicleType.automobile
    @State private var designID = PlateCatalog.defaultDesignID
    @State private var veteranDecalID = ""

    private var design: PlateDesign? { PlateCatalog.design(id: designID) }

    var body: some View {
        Form {
            Section("Plate selection") {
                Picker("Vehicle", selection: $vehicleType) {
                    ForEach(VehicleType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .onChange(of: vehicleType) { _, vehicle in
                    if design?.supports(vehicle) != true { designID = PlateCatalog.defaultDesignID }
                }
                Picker("Design", selection: $designID) {
                    ForEach(PlateCatalog.designs(for: vehicleType)) { Text($0.name).tag($0.id) }
                }
                if vehicleType == .motorcycle || vehicleType == .trailer {
                    Text("The DMV online checker offers only Environmental plates for this vehicle type.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if design?.requiresDecal == true {
                    Picker("Decal", selection: $veteranDecalID) {
                        Text("Select organization…").tag("")
                        ForEach(VeteranDecal.all) { Text($0.name).tag($0.id) }
                    }
                }
            }
            Section("Plate text") {
                Text("Enter the plate you want to watch.")
                    .font(.subheadline).foregroundStyle(.secondary)
                TextField(design?.requiresSymbol == true ? "Plate text (e.g. AB♥123)" : "Plate text (e.g. ABC123)", text: $input)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(add)
                    .accessibilityLabel("License plate to watch")
                if design?.requiresSymbol == true {
                    HStack {
                        Text("Kids symbol")
                        Spacer()
                        ForEach(KidsSymbol.allCases, id: \.self) { symbol in
                            Button(String(symbol.character)) { insertSymbol(symbol) }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Insert \(symbol.rawValue) symbol")
                        }
                    }
                }
                Text(design?.inputGuidance ?? "Select a supported design.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: add) {
                Text("Add plate to watchlist")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial)
        }
        .navigationTitle("Add a plate")
        .navigationBarTitleDisplayMode(.inline)
        .alert("CA Plate Watch", isPresented: Binding(
            get: { store.message != nil },
            set: { if !$0 { store.message = nil } }
        )) {
            Button("OK") { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }

    private func add() {
        if store.add(input, vehicleType: vehicleType, designID: designID,
                     veteranDecalID: design?.requiresDecal == true ? veteranDecalID : nil) {
            dismiss()
        }
    }

    private func insertSymbol(_ symbol: KidsSymbol) {
        if let index = input.firstIndex(where: { KidsSymbol.matching($0) != nil }) {
            input.replaceSubrange(index...index, with: String(symbol.character))
        } else {
            input.append(symbol.character)
        }
    }
}

private struct WatchSettingsView: View {
    @ObservedObject var store: WatchStore
    private let dmv = URL(string: "https://www.dmv.ca.gov/wasapp/ipp2/initPers.do")!

    var body: some View {
        Form {
            Section("Checking") {
                Picker("Recheck every", selection: Binding(
                    get: { store.recheckInterval },
                    set: { store.setRecheckInterval($0) }
                )) {
                    ForEach(RecheckInterval.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Text("iOS runs background checks when it allows app refresh. Checks may occur later than the selected interval. Open the app or tap refresh to check now.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Alerts") {
                if store.notificationsAllowed {
                    Label("Notifications enabled", systemImage: "bell.badge")
                } else if store.notificationsDenied {
                    Button("Enable notifications in Settings") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                } else {
                    Button("Enable availability alerts") {
                        Task { await store.requestNotifications() }
                    }
                }
            }
            Section {
                Link("Open California DMV", destination: dmv)
            } footer: {
                Text("Availability is not a reservation or final DMV approval. Plate choices stay on this iPhone and do not sync with the Mac app.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("CA Plate Watch", isPresented: Binding(
            get: { store.message != nil },
            set: { if !$0 { store.message = nil } }
        )) {
            Button("OK") { store.message = nil }
        } message: {
            Text(store.message ?? "")
        }
    }
}
