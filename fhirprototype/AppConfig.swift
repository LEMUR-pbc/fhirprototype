import Foundation

enum Config {
    static let backendBaseURL = URL(string: "https://fhirbackend-ptloh.ondigitalocean.app")!
    static let redirectURI = "myapp://oauth-callback"
    static let callbackScheme = "myapp"

    static let quickPicks: [QuickPick] = [
        QuickPick(name: "Sandbox", iss: "https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4"),
        QuickPick(name: "Duke", iss: "https://health-apis.duke.edu/FHIR/api/FHIR/R4"),
        QuickPick(name: "UCLA", iss: "https://arrprox.mednet.ucla.edu/FHIRPRD/api/FHIR/R4")
    ]
}
