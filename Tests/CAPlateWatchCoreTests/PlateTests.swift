import Foundation
import CAPlateWatchCore

final class PlateTests {
    func testValidationAndNormalization() throws {
        XCTAssertEqual(try Plate(text: " hi/mom ").text, "HI/MOM")
        for text in ["A", "TOOLONG8", "HI♥", "ÉMIRA", "   ", "///"] {
            XCTAssertThrowsError(try Plate(text: text))
        }
    }

    func testConfigurableDeadlinesAndPreferences() throws {
        let suite = "CAPlateWatchTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(RecheckInterval.load(from: defaults), .twelveHours)
        XCTAssertEqual(RecheckInterval.allCases.map(\.rawValue), [1, 3, 6, 12, 24, 48])
        let now = Date(timeIntervalSince1970: 1_000_000)
        for interval in RecheckInterval.allCases {
            defaults.set(interval.rawValue, forKey: RecheckInterval.preferenceKey)
            XCTAssertEqual(RecheckInterval.load(from: UserDefaults(suiteName: suite)!), interval)
            var plate = try Plate(text: "EMIRA")
            XCTAssertTrue(plate.isDue(at: now, interval: interval.seconds))
            plate.record(.success(.unavailable), at: now)
            let restored = try JSONDecoder().decode(Plate.self, from: JSONEncoder().encode(plate))
            XCTAssertFalse(restored.isDue(at: now.addingTimeInterval(interval.seconds - 1), interval: interval.seconds))
            XCTAssertTrue(restored.isDue(at: now.addingTimeInterval(interval.seconds), interval: interval.seconds))
            XCTAssertTrue(restored.isDue(at: now.addingTimeInterval(3 * interval.seconds), interval: interval.seconds))
            plate.record(.failure(CheckError.message("offline")), at: now.addingTimeInterval(interval.seconds))
            XCTAssertFalse(plate.isDue(at: now.addingTimeInterval(2 * interval.seconds - 1), interval: interval.seconds))
            XCTAssertTrue(plate.isDue(at: now.addingTimeInterval(2 * interval.seconds), interval: interval.seconds))
        }
        for invalid in [0, -1, 2, 100] {
            defaults.set(invalid, forKey: RecheckInterval.preferenceKey)
            XCTAssertEqual(RecheckInterval.load(from: defaults), .twelveHours)
        }
    }

    func testScheduleChangesDuringChecking() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var first = try Plate(text: "FIRST")
        var second = try Plate(text: "SECOND")
        first.record(.success(.unavailable), at: now)
        second.record(.success(.unavailable), at: now)
        let later = now.addingTimeInterval(6 * 3600)
        XCTAssertNil(CheckSchedule.nextPlate(in: [first, second], at: later, interval: 12 * 3600, attempted: []))
        // Shortening makes entries due; the in-flight entry cannot be selected again.
        XCTAssertEqual(CheckSchedule.nextPlate(in: [first, second], at: later, interval: 3 * 3600, attempted: [])?.id, first.id)
        let attempted: Set<UUID> = [first.id]
        XCTAssertEqual(CheckSchedule.nextPlate(in: [first, second], at: later, interval: 3 * 3600, attempted: attempted)?.id, second.id)
        // Lengthening while a request runs postpones the next automatic request.
        XCTAssertNil(CheckSchedule.nextPlate(in: [first, second], at: later, interval: 24 * 3600, attempted: attempted))
        XCTAssertEqual(CheckSchedule.nextPlate(in: [first, second], at: later, interval: 24 * 3600, attempted: attempted, force: true)?.id, second.id)
        let added = try Plate(text: "NEWONE")
        XCTAssertEqual(CheckSchedule.nextPlate(in: [first, added], at: later, interval: 24 * 3600, attempted: attempted)?.id, added.id)
        XCTAssertNil(CheckSchedule.nextPlate(in: [first], at: later, interval: 3600, attempted: attempted, force: true))
        // Days asleep still yield only one attempt per entry in this run.
        XCTAssertNil(CheckSchedule.nextPlate(in: [first, second], at: later.addingTimeInterval(7 * 86400), interval: 3600,
                                            attempted: [first.id, second.id]))
    }

    func testAlertsOnlyOnConfirmedTransitionsAndErrorsPreserveState() throws {
        var plate = try Plate(text: "EMIRA")
        let now = Date()
        XCTAssertTrue(plate.record(.success(.available), at: now))
        XCTAssertTrue(plate.unread)
        plate.unread = false
        XCTAssertFalse(plate.record(.failure(CheckError.message("offline")), at: now))
        XCTAssertEqual(plate.availability, .available)
        XCTAssertNotNil(plate.error)
        XCTAssertFalse(plate.record(.success(.available), at: now))
        XCTAssertNil(plate.error)
        XCTAssertFalse(plate.unread)
        XCTAssertFalse(plate.record(.success(.unavailable), at: now))
        XCTAssertTrue(plate.record(.success(.available), at: now))
    }

    func testDMVResponsesNeverGuessAvailability() throws {
        XCTAssertEqual(try DMVClient.parse(Data(#"{"code":"AVAILABLE"}"#.utf8)), .available)
        XCTAssertEqual(try DMVClient.parse(Data(#"{"code":"UNAVAILABLE"}"#.utf8)), .unavailable)
        XCTAssertEqual(try DMVClient.parse(Data(#"{"code":"NOT_AVAILABLE"}"#.utf8)), .unavailable)
        for response in [#"{"code":"SERVICE_UNAVAILABLE"}"#, #"{"code":"UNKNOWN"}"#, "[]", "null", "<html>congratulations unavailable</html>"] {
            XCTAssertThrowsError(try DMVClient.parse(Data(response.utf8)))
        }
    }

    func testFormEncodingPreservesSpacesAndHalfSpaces() {
        XCTAssertEqual(DMVClient.formEncode(["plateChar2": "/", "plateChar1": " "]), "plateChar1=%20&plateChar2=%2F")
    }

    func testNativeHandshakeAndPlateFields() async throws {
        for plate in [try Plate(text: "HI/MOM"),
                      try Plate(text: "HI MOM", vehicleType: .commercial, designID: "Q"),
                      try Plate(text: "HI♥MOM", designID: "K"),
                      try Plate(text: "EMIRA", vehicleType: .motorcycle)] {
            let expected = try DMVClient.fields(for: plate)
            DMVStub.reset(expected: expected)
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DMVStub.self]
            let result = try await DMVClient(session: URLSession(configuration: configuration)).check(plate)
            XCTAssertEqual(result, .unavailable)
            XCTAssertEqual(DMVStub.paths, ["initPers.do", "startPers.do", "checkPers.do"])
        }
    }

    func testLiveDMV() async throws {
        guard ProcessInfo.processInfo.environment["CA_PLATE_WATCH_LIVE_TEST"] == "1" else {
            print("SKIP live DMV lookups (set CA_PLATE_WATCH_LIVE_TEST=1 to enable)")
            return
        }
        // Representative vehicles and the seven-slot, six-slot, symbol, and decal forms.
        let plates = [try Plate(text: "EMIRA"),
                      try Plate(text: "EMIRA", vehicleType: .commercial, designID: "Q"),
                      try Plate(text: "EMIRA", vehicleType: .trailer),
                      try Plate(text: "EMIRA", vehicleType: .motorcycle),
                      try Plate(text: "HI♥MOM", designID: "K"),
                      try Plate(text: "EMIRA", designID: "V", veteranDecalID: "V61"),
                      try Plate(text: "HI/MOM", designID: "Z")]
        for plate in plates {
            let result = try await DMVClient().check(plate)
            print("Live DMV: \(plate.text) · \(plate.selectionLabel): \(result.rawValue)")
            XCTAssertNotEqual(result, .unknown)
        }
    }

    func testCatalogAndRequestMatrix() throws {
        // Independently transcribed from DMV ipp2 v84's design cards and selectPlate handlers.
        let expected: [(String, String, Int)] = [
            ("R", "Environmental", 7), ("Q", "Breast Cancer Awareness", 6),
            ("J", "California Museums", 6), ("Z", "California 1960s Legacy", 7),
            ("I", "Pet Lover's", 6), ("D", "California Agriculture", 6),
            ("G", "California Memorial", 6), ("W", "California Coastal Commission", 7),
            ("H", "Lake Tahoe Conservancy", 7), ("Y", "Yosemite Foundation", 7),
            ("A", "California Arts Council", 6), ("V", "Veterans' Organization", 6), ("K", "Kids", 7)
        ]
        XCTAssertEqual(PlateCatalog.designs.map(\.id), expected.map { $0.0 })
        XCTAssertEqual(VehicleType.allCases.map(\.rawValue), ["AUTO", "COMM", "TRAI", "MOTO"])
        for vehicle in VehicleType.allCases {
            let permitted = vehicle == .automobile || vehicle == .commercial ? expected.map { $0.0 } : ["R"]
            XCTAssertEqual(PlateCatalog.designs(for: vehicle).map(\.id), permitted)
            for (code, name, length) in expected {
                let text = code == "K" ? "HI♥MOM" : "HI/MOM"
                let decal = code == "V" ? "V61" : nil
                guard permitted.contains(code) else {
                    XCTAssertThrowsError(try Plate(text: text, vehicleType: vehicle, designID: code, veteranDecalID: decal))
                    continue
                }
                let plate = try Plate(text: text, vehicleType: vehicle, designID: code, veteranDecalID: decal)
                let fields = try DMVClient.fields(for: plate)
                XCTAssertEqual(fields["vehicleType"], vehicle.rawValue)
                XCTAssertEqual(fields["plateType"], code)
                XCTAssertEqual(fields["plateName"], name)
                XCTAssertEqual(fields["plateNameLow"], name.lowercased())
                XCTAssertEqual(fields["plateLength"], String(length))
                XCTAssertEqual(fields["kidsPlate"], code == "K" ? "heart" : "")
                XCTAssertEqual(fields["vetDecalCd"], decal ?? "")
                XCTAssertEqual(fields["vetDecalDesc"], code == "V" ? "US Army" : "")
                let start = length == 6 ? 8 : 0
                for offset in 0..<14 {
                    let expectedChars = ["H", "I", code == "K" ? "." : "/", "M", "O", "M"]
                    let position = offset - start
                    XCTAssertEqual(fields["plateChar\(offset)"], (0..<6).contains(position) ? expectedChars[position] : "")
                }
                XCTAssertTrue(plate.notificationBody.contains(vehicle.label))
                XCTAssertTrue(plate.notificationBody.contains(name))
                XCTAssertEqual(plate.notificationTitle, "\(text) is available")
            }
        }
        for decal in VeteranDecal.all {
            let fields = try DMVClient.fields(for: Plate(text: "ARMY", designID: "V", veteranDecalID: decal.id))
            XCTAssertEqual(fields["vetDecalCd"], decal.id)
            XCTAssertEqual(fields["vetDecalDesc"], decal.name)
        }
        XCTAssertEqual(Set(VeteranDecal.all.map(\.id)).count, VeteranDecal.all.count)
    }

    func testDesignValidationAndSymbols() throws {
        for design in PlateCatalog.designs where !design.requiresSymbol {
            let decal = design.requiresDecal ? "V61" : nil
            _ = try Plate(text: "AB", designID: design.id, veteranDecalID: decal)
            _ = try Plate(text: String(repeating: "A", count: design.length), designID: design.id, veteranDecalID: decal)
            XCTAssertThrowsError(try Plate(text: String(repeating: "A", count: design.length + 1), designID: design.id, veteranDecalID: decal))
            XCTAssertThrowsError(try Plate(text: "AB//CD", designID: design.id, veteranDecalID: decal))
        }
        // Seven-slot designs expose an eighth position when a half-space is present.
        let extra = try DMVClient.fields(for: Plate(text: "ABC/DEFG"))
        XCTAssertEqual(extra["plateChar7"], "G")
        XCTAssertThrowsError(try Plate(text: "ABCD/EFGH"))
        XCTAssertThrowsError(try Plate(text: "ABC/DEF", designID: "Q"))
        let space = try DMVClient.fields(for: Plate(text: "HI MOM", designID: "Q"))
        XCTAssertEqual(space["plateChar10"], "")
        XCTAssertEqual(space["plateChar11"], "M")
        for symbol in KidsSymbol.allCases {
            let plate = try Plate(text: "AB\(symbol.character)CDEF", designID: "K")
            let fields = try DMVClient.fields(for: plate)
            XCTAssertEqual(fields["kidsPlate"], symbol.rawValue)
            XCTAssertEqual(fields["plateChar2"], ".")
            XCTAssertEqual(fields["plateChar6"], "F")
            XCTAssertEqual(fields["plateChar7"], "")
            _ = try Plate(text: "\(symbol.character)AB", designID: "K")
            _ = try Plate(text: "AB\(symbol.character)", designID: "K")
            XCTAssertThrowsError(try Plate(text: "AB\(symbol.character)CDEFG", designID: "K"))
            XCTAssertThrowsError(try Plate(text: "AB\(symbol.character)"))
        }
        for text in ["AB", "A♥", "AB♥★", "AB.CD", "AB//♥", "AB*♥"] {
            XCTAssertThrowsError(try Plate(text: text, designID: "K"))
        }
        XCTAssertThrowsError(try Plate(text: "ARMY", designID: "V"))
        XCTAssertThrowsError(try Plate(text: "ARMY", designID: "V", veteranDecalID: "FUTURE"))
        XCTAssertThrowsError(try Plate(text: "ARMY", veteranDecalID: "V61"))
    }

    func testSelectionPersistenceAndUnsupportedEntries() throws {
        let legacy = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","text":"EMIRA","availability":"available","lastAttempt":20,"lastSuccess":10,"error":"offline","unread":true}]"#.utf8)
        let migrated = try JSONDecoder().decode([Plate].self, from: legacy)[0]
        XCTAssertEqual(migrated.vehicleType, .automobile)
        XCTAssertEqual(migrated.designID, "R")
        XCTAssertEqual(migrated.id.uuidString, "00000000-0000-0000-0000-000000000001")
        XCTAssertEqual(migrated.availability, .available)
        XCTAssertEqual(migrated.lastAttempt, Date(timeIntervalSinceReferenceDate: 20))
        XCTAssertEqual(migrated.lastSuccess, Date(timeIntervalSinceReferenceDate: 10))
        XCTAssertEqual(migrated.error, "offline")
        XCTAssertTrue(migrated.unread)
        for plate in [migrated, try Plate(text: "HI♥MOM", vehicleType: .commercial, designID: "K"),
                      try Plate(text: "ARMY", designID: "V", veteranDecalID: "V61")] {
            let restored = try JSONDecoder().decode(Plate.self, from: JSONEncoder().encode(plate))
            XCTAssertTrue(restored.matchesSelection(of: plate))
            XCTAssertEqual(restored.id, plate.id)
            XCTAssertEqual(restored.veteranDecalID, plate.veteranDecalID)
            XCTAssertEqual(restored.lastAttempt, plate.lastAttempt)
            XCTAssertEqual(restored.lastSuccess, plate.lastSuccess)
            XCTAssertEqual(restored.availability, plate.availability)
            XCTAssertEqual(restored.error, plate.error)
            XCTAssertEqual(restored.unread, plate.unread)
        }
        let original = try Plate(text: " emira ")
        try XCTAssertTrue(original.matchesSelection(of: try Plate(text: "EMIRA")))
        try XCTAssertFalse(original.matchesSelection(of: try Plate(text: "EMIRA", vehicleType: .motorcycle)))
        try XCTAssertFalse(original.matchesSelection(of: try Plate(text: "EMIRA", designID: "Z")))
        // Decals are decorative; they do not create a separate plate configuration.
        try XCTAssertTrue(try Plate(text: "ARMY", designID: "V", veteranDecalID: "V61").matchesSelection(
            of: Plate(text: "ARMY", designID: "V", veteranDecalID: "V69")))
        for key in ["vehicleTypeID", "designID"] {
            var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
            json[key] = "FUTURE"
            let decoded = try JSONDecoder().decode(Plate.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertNotNil(decoded.selectionError)
            XCTAssertTrue(decoded.selectionLabel.contains("Unsupported"))
            XCTAssertThrowsError(try DMVClient.fields(for: decoded))
            let roundTrip = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as! [String: Any]
            XCTAssertEqual(roundTrip[key] as? String, "FUTURE")
            XCTAssertEqual(decoded.id, original.id)
        }
    }

    func testLegacyWatchlistMigration() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = folder.appendingPathComponent("PlateWatch/watchlist.json")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","text":"EXAMPLE","availability":"unknown","unread":false}]"#.utf8)
        try original.write(to: legacy)
        let destination = try LegacyMigration.importWatchlist(in: folder)
        XCTAssertEqual(try Data(contentsOf: destination), original)
        XCTAssertEqual(try Data(contentsOf: legacy), original)
        let replacement = try JSONEncoder().encode([Plate(text: "NEWONE")])
        try replacement.write(to: destination)
        _ = try LegacyMigration.importWatchlist(in: folder)
        XCTAssertEqual(try Data(contentsOf: destination), replacement)
    }
}

private final class DMVStub: URLProtocol {
    private static let lock = NSLock()
    private static var expected: [String: String] = [:]
    private static var recordedPaths: [String] = []
    static var paths: [String] {
        lock.lock(); defer { lock.unlock() }
        return recordedPaths
    }
    static func reset(expected: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        self.expected = expected
        recordedPaths = []
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let path = request.url!.lastPathComponent
        Self.lock.lock()
        Self.recordedPaths.append(path)
        let expected = Self.expected
        Self.lock.unlock()
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            body = data
        }
        let form = String(data: body ?? Data(), encoding: .utf8) ?? ""
        switch path {
        case "initPers.do": XCTAssertEqual(request.httpMethod, "GET")
        case "startPers.do":
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(form.contains("acknowledged=true"))
        case "checkPers.do":
            XCTAssertEqual(request.httpMethod, "POST")
            var components = URLComponents()
            components.percentEncodedQuery = form
            let actual = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(actual, expected)
        default: XCTFail("Unexpected endpoint: \(path)")
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((path == "checkPers.do" ? #"{"code":"UNAVAILABLE"}"# : "OK").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func XCTAssertTrue(_ condition: @autoclosure () throws -> Bool) rethrows { let value = try condition(); precondition(value) }
private func XCTAssertFalse(_ condition: @autoclosure () throws -> Bool) rethrows { let value = try condition(); precondition(!value) }
private func XCTAssertEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs == rhs, "Expected \(rhs), got \(lhs)") }
private func XCTAssertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T) { precondition(lhs != rhs) }
private func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
private func XCTAssertNotNil<T>(_ value: T?) { precondition(value != nil) }
private func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression() } catch { return }
    fatalError("Expected an error")
}
private func XCTFail(_ message: String) { fatalError(message) }

@main struct RunTests {
    static func main() async throws {
        let tests = PlateTests()
        try tests.testValidationAndNormalization()
        try tests.testConfigurableDeadlinesAndPreferences()
        try tests.testScheduleChangesDuringChecking()
        try tests.testCatalogAndRequestMatrix()
        try tests.testDesignValidationAndSymbols()
        try tests.testSelectionPersistenceAndUnsupportedEntries()
        try tests.testAlertsOnlyOnConfirmedTransitionsAndErrorsPreserveState()
        try tests.testDMVResponsesNeverGuessAvailability()
        tests.testFormEncodingPreservesSpacesAndHalfSpaces()
        try await tests.testNativeHandshakeAndPlateFields()
        try tests.testLegacyWatchlistMigration()
        print("PASS: validation, persistence, scheduling, alert transitions, response parsing, native request flow")
        try await tests.testLiveDMV()
    }
}
