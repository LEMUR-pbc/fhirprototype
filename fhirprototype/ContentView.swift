//
//  ContentView.swift
//  fhirprototype
//
//  Created by Lemur Mini 1 on 2/4/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: SmartLaunchViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("SMART on FHIR")
                    .font(.largeTitle.bold())
                Text("Standalone patient launch")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Organization")
                        .font(.headline)
                    HStack {
                        TextField("Search organizations", text: $viewModel.orgQuery)
                            .textInputAutocapitalization(.words)
                            .disableAutocorrection(true)
                            .submitLabel(.search)
                            .onSubmit {
                                Task { await viewModel.searchOrganizations() }
                            }
                        Button("Search") {
                            Task { await viewModel.searchOrganizations() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.orgQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSearching)
                    }

                    if viewModel.isSearching {
                        ProgressView("Searching...")
                    }

                    if !viewModel.orgResults.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.orgResults) { org in
                                Button {
                                    if let iss = org.resolvedIss {
                                        Task { await viewModel.startFlow(iss: iss) }
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(org.displayName)
                                            .font(.subheadline.bold())
                                        if let iss = org.resolvedIss {
                                            Text(iss)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.bordered)
                                .disabled(org.resolvedIss == nil)
                            }
                        }
                    }
                }

                Divider()

                Text("Quick Picks")
                    .font(.headline)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(Config.quickPicks) { pick in
                        Button(pick.name) {
                            Task { await viewModel.startFlow(iss: pick.iss) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if viewModel.isLoading {
                    ProgressView("Launching...")
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }

                if let patient = viewModel.patient {
                    PatientCardView(patient: patient)
                }

                if viewModel.isLoadingConditions {
                    ProgressView("Loading conditions...")
                }

                if let conditionsError = viewModel.conditionsError {
                    Text("Conditions error: \(conditionsError)")
                        .foregroundColor(.red)
                }

                if !viewModel.conditions.isEmpty {
                    ConditionsListView(conditions: viewModel.conditions)
                }
            }
            .padding()
        }
    }
}

struct PatientCardView: View {
    let patient: PatientResource

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Patient")
                .font(.headline)
            Text(patient.displayName)
                .font(.title2.bold())

            Text("Gender: \(patient.gender ?? "Unknown")")
            Text("Birth Date: \(patient.birthDate ?? "Unknown")")

            if !patient.identifierDisplay.isEmpty {
                Text("Identifiers")
                    .font(.headline)
                ForEach(patient.identifierDisplay, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

struct ConditionsListView: View {
    let conditions: [ConditionResource]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Conditions")
                .font(.headline)

            ForEach(Array(conditions.enumerated()), id: \.offset) { _, condition in
                VStack(alignment: .leading, spacing: 4) {
                    Text(condition.displayTitle)
                        .font(.subheadline.bold())

                    if let status = condition.displayStatus {
                        Text("Status: \(status)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let onset = condition.displayOnset {
                        Text("Onset: \(onset)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
            }
        }
    }
}

#Preview {
    ContentView(viewModel: SmartLaunchViewModel())
}
