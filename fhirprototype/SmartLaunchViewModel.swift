import Foundation

@MainActor
final class SmartLaunchViewModel: ObservableObject {
    @Published var orgQuery: String = ""
    @Published var orgResults: [OrgMatch] = []
    @Published var patient: PatientResource?
    @Published var isSearching = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = APIClient(baseURL: Config.backendBaseURL)
    private let credentialStore = CredentialStore()
    private let authSession = AuthSessionManager()

    func handleDeepLink(_ url: URL) {
        _ = url
    }

    func searchOrganizations() async {
        let query = orgQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            orgResults = []
            return
        }

        errorMessage = nil
        isSearching = true
        defer { isSearching = false }

        do {
            orgResults = try await api.resolveOrganizations(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startFlow(iss: String) async {
        guard !isLoading else { return }

        errorMessage = nil
        patient = nil
        isLoading = true
        defer { isLoading = false }

        do {
            let auth = try await api.smartAuthorize(
                iss: iss,
                redirectUri: Config.redirectURI
            )

            credentialStore.saveState(auth.state)
            credentialStore.saveCodeVerifier(auth.code_verifier)

            guard let authURL = URL(string: auth.authorization_url) else {
                throw AppError.invalidURL
            }

            let callbackURL = try await authSession.authenticate(
                url: authURL,
                callbackScheme: Config.callbackScheme
            )

            let callback = try OAuthCallback(url: callbackURL)

            guard let storedState = credentialStore.loadState(),
                  storedState == callback.state else {
                throw AppError.stateMismatch
            }

            guard let verifier = credentialStore.loadCodeVerifier() else {
                throw AppError.missingVerifier
            }

            let token = try await api.smartExchange(
                code: callback.code,
                iss: auth.iss,
                codeVerifier: verifier,
                redirectUri: Config.redirectURI
            )

            guard let patientId = token.patient else {
                throw AppError.missingPatient
            }

            let fhirBase = token.fhir_base ?? auth.iss
            let patient = try await api.fetchPatient(
                iss: fhirBase,
                patientId: patientId,
                accessToken: token.access_token
            )

            self.patient = patient
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
