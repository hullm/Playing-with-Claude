import Foundation

/// Errors surfaced to the UI. Each case maps to a distinct recovery path.
enum APIError: LocalizedError, Equatable {
    case notConfigured                 // no token stored yet
    case unauthorized                  // 401 — token bad/expired, prompt re-paste
    case conflict(String)              // 409 — submit blocked / future work / locked
    case http(status: Int, message: String?)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No access token set."
        case .unauthorized:
            return "Your access token was rejected. Paste a fresh one from Settings → API access."
        case .conflict(let message):
            return message
        case .http(let status, let message):
            return message ?? "Request failed (HTTP \(status))."
        case .decoding(let detail):
            return "Couldn't read the server's response. \(detail)"
        case .transport(let detail):
            return detail
        }
    }
}

/// Async REST client for the Time Sheets API.
struct APIClient {
    let baseURL: URL
    let token: String
    var session: URLSession = .shared

    // MARK: Endpoints

    func me() async throws -> Me {
        try await get("me")
    }

    func periods() async throws -> [Period] {
        let response: PeriodsResponse = try await get("periods")
        return response.periods
    }

    func defaults() async throws -> WorkdayDefaults {
        try await get("me/defaults")
    }

    /// PUT the user's default workday hours; returns the saved defaults.
    func updateDefaults(regStart: String, regEnd: String) async throws -> WorkdayDefaults {
        try await send("me/defaults", method: "PUT",
                       body: DefaultsUpdate(regStart: regStart, regEnd: regEnd))
    }

    func timesheet(periodID: Int) async throws -> Timesheet {
        try await get("timesheet/\(periodID)")
    }

    /// PUT a single day's edits; returns the refreshed card.
    func updateDay(periodID: Int, update: DayUpdate) async throws -> Timesheet {
        try await send("timesheet/\(periodID)/day", method: "PUT", body: update)
    }

    /// Sign & submit. Returns the refreshed timesheet on success; throws
    /// `.conflict` with the server's message on 409.
    @discardableResult
    func submit(periodID: Int) async throws -> Timesheet {
        try await send("timesheet/\(periodID)/submit", method: "POST", body: EmptyBody())
    }

    // MARK: Plumbing

    private struct EmptyBody: Encodable {}

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await perform(request(path, method: "GET"))
    }

    private func send<T: Decodable, B: Encodable>(_ path: String, method: String, body: B) async throws -> T {
        var req = request(path, method: method)
        if !(body is EmptyBody) {
            req.httpBody = try JSONEncoder().encode(body)
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return try await perform(req)
    }

    private func request(_ path: String, method: String) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Unexpected non-HTTP response.")
        }

        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decoding(String(describing: error))
            }
        case 401:
            throw APIError.unauthorized
        case 409, 422:
            // Locked sheet or no-early-submit rule; the server explains why.
            throw APIError.conflict(serverMessage(from: data)
                ?? "This timesheet can't be edited or submitted right now.")
        default:
            throw APIError.http(status: http.statusCode, message: serverMessage(from: data))
        }
    }

    private func serverMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.text
    }
}
