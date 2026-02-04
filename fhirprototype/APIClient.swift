import Foundation

struct APIClient {
    let baseURL: URL
    private let session = URLSession.shared
    private let decoder = JSONDecoder()

    func smartAuthorize(iss: String, redirectUri: String, scope: String? = nil, aud: String? = nil) async throws -> SmartAuthorizeResponse {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/smart/authorize"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "iss", value: iss),
            URLQueryItem(name: "mode", value: "json"),
            URLQueryItem(name: "redirect_uri", value: redirectUri)
        ]
        if let scope { items.append(URLQueryItem(name: "scope", value: scope)) }
        if let aud { items.append(URLQueryItem(name: "aud", value: aud)) }
        components.queryItems = items

        let (data, response) = try await session.data(from: components.url!)
        try validate(response: response, data: data)
        return try decoder.decode(SmartAuthorizeResponse.self, from: data)
    }

    func smartExchange(code: String, iss: String, codeVerifier: String, redirectUri: String) async throws -> TokenResponse {
        var request = URLRequest(url: baseURL.appendingPathComponent("/api/smart/exchange"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = SmartExchangeRequest(
            code: code,
            iss: iss,
            code_verifier: codeVerifier,
            redirect_uri: redirectUri
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(TokenResponse.self, from: data)
    }

    func fetchPatient(iss: String, patientId: String, accessToken: String) async throws -> PatientResource {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/fhir/patient"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "iss", value: iss),
            URLQueryItem(name: "patient", value: patientId)
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validate(response: response, data: data)
        return try decoder.decode(PatientResource.self, from: data)
    }

    func resolveOrganizations(query: String) async throws -> [OrgMatch] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/epic/resolve"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]

        let (data, response) = try await session.data(from: components.url!)
        try validate(response: response, data: data)
        return try decodeOrgMatches(from: data)
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw AppError.httpError(status: http.statusCode, message: message)
        }
    }

    private func decodeOrgMatches(from data: Data) throws -> [OrgMatch] {
        if let array = try? decoder.decode([OrgMatch].self, from: data) {
            return array
        }
        let wrapper = try decoder.decode(OrgSearchWrapper.self, from: data)
        return wrapper.matches ?? wrapper.results ?? wrapper.organizations ?? wrapper.data ?? []
    }
}
