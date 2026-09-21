import Foundation
import CAPlateWatchCore

final class PlateTests {
    func testValidationAndNormalization() throws {
        XCTAssertEqual(try Plate(text: " hi/mom ").text, "HI/MOM")
        for text in ["A", "TOOLONG8", "HI♥", "ÉMIRA", "   ", "///"] {
            XCTAssertThrowsError(try Plate(text: text))
        }
    }

    func testSixHourDeadlineSurvivesPersistenceAndSleep() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        var plate = try Plate(text: "EMIRA")
        XCTAssertTrue(plate.isDue(at: now))
        plate.record(.success(.unavailable), at: now)
        let restored = try JSONDecoder().decode(Plate.self, from: JSONEncoder().encode(plate))
        XCTAssertFalse(restored.isDue(at: now.addingTimeInterval(Plate.interval - 1)))
        XCTAssertTrue(restored.isDue(at: now.addingTimeInterval(Plate.interval)))
        XCTAssertTrue(restored.isDue(at: now.addingTimeInterval(3 * Plate.interval)))
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
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DMVStub.self]
        let result = try await DMVClient(session: URLSession(configuration: configuration)).check("HI/MOM")
        XCTAssertEqual(result, .unavailable)
    }

    func testLiveDMV() async throws {
        guard ProcessInfo.processInfo.environment["CA_PLATE_WATCH_LIVE_TEST"] == "1" else {
            print("SKIP live DMV lookup (set CA_PLATE_WATCH_LIVE_TEST=1 to enable)")
            return
        }
        let result = try await DMVClient().check("EMIRA")
        print("Live DMV result for EMIRA: \(result.rawValue)")
        XCTAssertNotEqual(result, .unknown)
    }

    func testLegacyWatchlistMigration() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = folder.appendingPathComponent("PlateWatch/watchlist.json")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = try JSONEncoder().encode([Plate(text: "EXAMPLE")])
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
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let path = request.url!.lastPathComponent
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
            XCTAssertTrue(form.contains("plateChar2=%2F"))
            XCTAssertTrue(form.contains("plateChar6="))
            XCTAssertTrue(form.contains("plateType=R"))
            XCTAssertTrue(form.contains("vehicleType=AUTO"))
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
        try tests.testSixHourDeadlineSurvivesPersistenceAndSleep()
        try tests.testAlertsOnlyOnConfirmedTransitionsAndErrorsPreserveState()
        try tests.testDMVResponsesNeverGuessAvailability()
        tests.testFormEncodingPreservesSpacesAndHalfSpaces()
        try await tests.testNativeHandshakeAndPlateFields()
        try tests.testLegacyWatchlistMigration()
        print("PASS: validation, persistence, scheduling, alert transitions, response parsing, native request flow")
        try await tests.testLiveDMV()
    }
}
