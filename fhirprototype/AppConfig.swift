import Foundation

enum Config {
    static let backendBaseURL = URL(string: "https://fhirbackend-ptloh.ondigitalocean.app")!
    static let redirectURI = "myapp://oauth-callback"
    static let callbackScheme = "myapp"

    static let sandboxIss = "https://fhir.epic.com/interconnect-fhir-oauth/api/FHIR/R4"
    static let dukeIss = "https://health-apis.duke.edu/FHIR/api/FHIR/R4"
    static let uclaIss = "https://arrprox.mednet.ucla.edu/FHIRPRD/api/FHIR/R4"
    static let sandboxUsername = "fhirjason"
    static let sandboxPassword = "epicepic1"

    static let quickPicks: [QuickPick] = [
        QuickPick(name: "Sandbox", iss: sandboxIss),
        QuickPick(name: "Duke", iss: dukeIss),
        QuickPick(name: "UCLA", iss: uclaIss)
    ]
}
