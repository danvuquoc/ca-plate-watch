import Foundation

/// California personalized plate availability client. Each lookup gets a private cookie session.
public struct DMVClient {
    private let session: URLSession
    private let base = URL(string: "https://www.dmv.ca.gov/wasapp/ipp2/")!

    public init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 45
        configuration.httpShouldSetCookies = true
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36",
            "Accept": "application/json, text/javascript, */*; q=0.01",
            "X-Requested-With": "XMLHttpRequest",
            "Referer": "https://www.dmv.ca.gov/wasapp/ipp2/startPers.do",
            "Origin": "https://www.dmv.ca.gov"
        ]
        self.session = session ?? URLSession(configuration: configuration)
    }

    public func check(_ text: String) async throws -> Availability {
        try await check(Plate(text: text))
    }

    public func check(_ plate: Plate) async throws -> Availability {
        defer { session.finishTasksAndInvalidate() }
        let fields = try Self.fields(for: plate)
        _ = try await request("initPers.do")
        _ = try await request("startPers.do", fields: ["acknowledged": "true", "_acknowledged": "on"])
        let data = try await request("checkPers.do", fields: fields)
        return try Self.parse(data)
    }

    public static func fields(for plate: Plate) throws -> [String: String] {
        try plate.validateSelection()
        guard let design = plate.design else { throw CheckError.message("Unsupported plate design.") }
        let chars = Array(plate.text)
        var fields = ["plateType": design.id, "plateName": design.name, "plateNameLow": design.name.lowercased(),
                      "plateLength": String(design.length), "vehicleType": plate.vehicleTypeID,
                      "kidsPlate": chars.compactMap(KidsSymbol.matching).first?.rawValue ?? "",
                      "vetDecalCd": plate.veteranDecalID ?? "",
                      "vetDecalDesc": plate.veteranDecalID.flatMap { VeteranDecal.decal(id: $0)?.name } ?? ""]
        // The DMV submits both input groups; six-character designs start at index 8.
        for index in 0..<14 { fields["plateChar\(index)"] = "" }
        let start = design.length == 6 ? 8 : 0
        for (offset, character) in chars.enumerated() {
            fields["plateChar\(start + offset)"] = KidsSymbol.matching(character) != nil ? "." : (character == " " ? "" : String(character))
        }
        return fields
    }

    private func request(_ path: String, fields: [String: String]? = nil) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponent(path))
        if let fields {
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formEncode(fields).data(using: .utf8)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let finalURL = http.url, finalURL.host == base.host,
              finalURL.path.hasPrefix(base.path) else {
            throw CheckError.message("DMV rejected or redirected the check. It may be down or require a browser verification. Will retry at the next scheduled check.")
        }
        return data
    }

    public static func formEncode(_ fields: [String: String]) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return fields.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&")
    }

    public static func parse(_ data: Data) throws -> Availability {
        // HTML can include both success/error phrases in scripts and templates.
        // Only explicit structured result codes are reliable enough to notify.
        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = payload["code"] as? String else {
            throw CheckError.message("DMV returned an unrecognized page, possibly a verification challenge. Availability is unknown.")
        }
        switch code.uppercased() {
        case "AVAILABLE": return .available
        case "UNAVAILABLE", "NOT_AVAILABLE": return .unavailable
        default: throw CheckError.message("DMV could not determine availability (\(code.prefix(80))). Will retry at the next scheduled check.")
        }
    }
}
