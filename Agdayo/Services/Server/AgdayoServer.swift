import CoreLocation
import FirebaseAuth
import Foundation

/// Agdayo's own server (the Cloudflare Worker in `worker/`). It holds the
/// Google key and answers with Google routes. Only accounts on the server's
/// allowlist get through, so the address is fine to keep in the repo.
enum AgdayoServer {
    static let baseURL = URL(string: "https://agdayo.albertcorpmail.workers.dev")!

    enum ServerError: LocalizedError {
        case signedOut
        case notAllowed
        case server(String)

        var errorDescription: String? {
            switch self {
            case .signedOut: return "Sign in to see transit steps."
            case .notAllowed: return "This account can't use the Agdayo server."
            case .server(let message): return message
            }
        }
    }

    /// A transit route from Google, or nil when Google has no route (often no
    /// transit data in that city). `arriveBy` asks for a route that gets
    /// there by that time.
    static func transitRoute(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D, arriveBy: Date?) async throws -> ServerRoute? {
        var body: [String: Any] = [
            "origin": ["latitude": origin.latitude, "longitude": origin.longitude],
            "destination": ["latitude": destination.latitude, "longitude": destination.longitude],
            "mode": "transit",
        ]
        // Google only has timetables for roughly the coming weeks; a past
        // time is meaningless, so plan for now in that case.
        if let arriveBy, arriveBy > .now {
            body["arrivalTime"] = ISO8601DateFormatter().string(from: arriveBy)
        }
        let data = try await post("/v1/route", body: body)
        return try decoder.decode(RouteResponse.self, from: data).route
    }

    private struct RouteResponse: Decodable {
        let route: ServerRoute?
    }

    private struct ErrorResponse: Decodable {
        let error: String
    }

    private static func post(_ path: String, body: [String: Any]) async throws -> Data {
        guard let user = Auth.auth().currentUser else { throw ServerError.signedOut }
        let token = try await user.getIDToken()
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 403 { throw ServerError.notAllowed }
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            throw ServerError.server(message ?? "The Agdayo server answered \(status).")
        }
        return data
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { container in
            let text = try container.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "Bad date: \(text)"))
        }
        return decoder
    }()

    /// ISO 8601 with or without fractional seconds. Google can send up to
    /// nine digits, which ISO8601DateFormatter rejects, so they're dropped.
    static func parseDate(_ text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}

/// Mirrors `RouteResult` in worker/src/google.ts.
struct ServerRoute: Decodable {
    let mode: String
    let durationSeconds: Double
    let distanceMeters: Double
    let fare: Fare?
    let steps: [Step]
    /// True when Google had no timetable for the requested time and planned for now instead.
    let timeAdjusted: Bool
    let fetchedAt: Date

    struct Fare: Decodable {
        let currency: String
        let amount: Double
        let text: String?
    }

    struct Step: Decodable {
        /// "walk", "transit", "drive" or "bicycle".
        let kind: String
        let durationSeconds: Double
        let distanceMeters: Double
        let instruction: String?
        let transit: TransitLeg?
    }

    struct TransitLeg: Decodable {
        let lineName: String
        let lineShortName: String?
        let vehicle: String
        let color: String?
        let textColor: String?
        let headsign: String?
        let departureStop: String
        let arrivalStop: String
        let departureTime: Date?
        let arrivalTime: Date?
        let stopCount: Int?
    }

    /// When the first train or bus leaves, for a "Leave by" headline.
    var firstDeparture: Date? { steps.lazy.compactMap { $0.transit?.departureTime }.first }
}
