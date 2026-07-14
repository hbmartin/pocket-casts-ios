import SwiftUI
import PocketCastsUtils

struct BetaMenu: View {
    @EnvironmentObject private var theme: Theme
    @State private var searchText = ""
    @State private var resetTrigger = false
    @State private var showingMetricKitPayloads = false

    var body: some View {
        List {
            Section("Diagnostics") {
                Button("MetricKit Payloads") {
                    showingMetricKitPayloads = true
                }
            }
            Section("Feature Flags") {
                ForEach(filteredFeatures, id: \.self) { feature in
                    Toggle(isOn: feature.isOn) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(describing: feature))
                            Text(feature.betaDescription)
                                .font(.footnote)
                                .foregroundStyle(AppTheme.color(for: .primaryText02, theme: theme))
                        }
                    }
                    .onTapGesture { }
                }
            }
        }
        .id(resetTrigger)
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: L10n.search)
        .sheet(isPresented: $showingMetricKitPayloads) {
            NavigationStack {
                MetricKitPayloadsView()
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Reset") {
                    resetOverrides()
                }
            }
        }
    }

    private var filteredFeatures: [FeatureFlag] {
        if searchText.isEmpty {
            FeatureFlag.allCases
        } else {
            FeatureFlag.allCases.filter { feature in
                String(describing: feature).localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    private func resetOverrides() {
        FeatureFlagOverrideStore().resetOverrides()
        resetTrigger.toggle()
        Toast.show("Feature flag overrides reset")
    }
}

private extension FeatureFlag {
    var isOn: Binding<Bool> {
        return Binding<Bool>(
            get: {
                return enabled
            },
            set: { enabled in
                try? FeatureFlagOverrideStore().override(self, withValue: enabled)
            }
        )
    }
}

struct BetaMenu_Previews: PreviewProvider {
    static var previews: some View {
        BetaMenu()
            .environmentObject(Theme.sharedTheme)
    }
}
