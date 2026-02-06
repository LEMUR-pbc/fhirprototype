import Foundation

struct QuickPick: Identifiable {
    let id = UUID()
    let name: String
    let iss: String
}

struct SmartAuthorizeResponse: Decodable {
    let authorization_url: String
    let state: String
    let code_verifier: String
    let iss: String
    let redirect_uri: String
}

struct SmartExchangeRequest: Encodable {
    let code: String
    let iss: String
    let code_verifier: String
    let redirect_uri: String
    let client_id: String? = nil
}

struct TokenResponse: Decodable {
    let access_token: String
    let token_type: String?
    let scope: String?
    let expires_in: Int?
    let refresh_token: String?
    let id_token: String?
    let patient: String?
    let fhir_base: String?
}

struct OrgSearchWrapper: Decodable {
    let matches: [OrgMatch]?
    let results: [OrgMatch]?
    let organizations: [OrgMatch]?
    let data: [OrgMatch]?
}

struct OrgMatch: Decodable, Identifiable {
    let id = UUID()
    let name: String?
    let iss: String?
    let fhir_base: String?
    let url: String?
    let org: String?
    let organization: String?
    let brand: String?

    var displayName: String {
        name ?? organization ?? org ?? brand ?? "Unknown Organization"
    }

    var resolvedIss: String? {
        iss ?? fhir_base ?? url
    }
}

struct PatientResource: Decodable {
    let name: [HumanName]?
    let gender: String?
    let birthDate: String?
    let identifier: [FHIRIdentifier]?

    var displayName: String {
        guard let first = name?.first else { return "Unknown" }
        if let text = first.text, !text.isEmpty { return text }

        let given = first.given?.joined(separator: " ") ?? ""
        let family = first.family ?? ""
        let full = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? "Unknown" : full
    }

    var identifierDisplay: [String] {
        identifier?.compactMap { id in
            guard let value = id.value, !value.isEmpty else { return nil }
            if let system = id.system, !system.isEmpty {
                return "\(system): \(value)"
            }
            return value
        } ?? []
    }
}

struct HumanName: Decodable {
    let text: String?
    let family: String?
    let given: [String]?
}

struct FHIRIdentifier: Decodable {
    let system: String?
    let value: String?
}

struct Bundle<T: Decodable>: Decodable {
    let entry: [BundleEntry<T>]?
}

struct BundleEntry<T: Decodable>: Decodable {
    let resource: T?
}

struct ConditionResource: Decodable {
    let id: String?
    let clinicalStatus: CodeableConcept?
    let verificationStatus: CodeableConcept?
    let category: [CodeableConcept]?
    let code: CodeableConcept?
    let onsetDateTime: String?
    let recordedDate: String?

    var displayTitle: String {
        code?.displayText ?? "Condition"
    }

    var displayStatus: String? {
        clinicalStatus?.displayText ?? verificationStatus?.displayText
    }

    var displayOnset: String? {
        onsetDateTime ?? recordedDate
    }
}

struct CodeableConcept: Decodable {
    let text: String?
    let coding: [Coding]?

    var displayText: String? {
        if let text, !text.isEmpty { return text }
        if let coding = coding?.first {
            return coding.display ?? coding.code
        }
        return nil
    }
}

struct Coding: Decodable {
    let system: String?
    let code: String?
    let display: String?
}

struct OAuthCallback {
    let code: String
    let state: String

    init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AppError.invalidURL
        }
        let items = components.queryItems ?? []
        let code = items.first { $0.name == "code" }?.value ?? ""
        let state = items.first { $0.name == "state" }?.value ?? ""

        guard !code.isEmpty else { throw AppError.missingCode }
        guard !state.isEmpty else { throw AppError.missingState }

        self.code = code
        self.state = state
    }
}

enum AppError: LocalizedError {
    case invalidURL
    case authSessionFailed
    case missingCallback
    case missingCode
    case missingState
    case stateMismatch
    case missingVerifier
    case missingPatient
    case invalidHTMLCapture
    case fhirOperationOutcome(String)
    case unexpectedFHIRResponse(String)
    case httpError(status: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .authSessionFailed:
            return "Failed to start web authentication session."
        case .missingCallback:
            return "Missing OAuth callback."
        case .missingCode:
            return "Missing authorization code."
        case .missingState:
            return "Missing OAuth state."
        case .stateMismatch:
            return "State mismatch. Please try again."
        case .missingVerifier:
            return "Missing code verifier."
        case .missingPatient:
            return "Token response did not include a patient."
        case .invalidHTMLCapture:
            return "Unable to capture HTML content."
        case .fhirOperationOutcome(let message):
            return "FHIR error: \(message)"
        case .unexpectedFHIRResponse(let message):
            return "Unexpected FHIR response: \(message)"
        case .httpError(let status, let message):
            if let message, !message.isEmpty {
                return "Server error (\(status)): \(message)"
            }
            return "Server error (\(status))."
        }
    }
}

struct OperationOutcome: Decodable {
    let issue: [OperationOutcomeIssue]?
}

struct OperationOutcomeIssue: Decodable {
    let severity: String?
    let code: String?
    let details: CodeableConcept?
    let diagnostics: String?
}
