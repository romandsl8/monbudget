import SwiftUI
import SwiftData

@main
struct MonBudgetApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: BudgetEntry.self)
    }
}

enum AppTab: Hashable {
    case dashboard, entries, settings
}

/// Racine : barre d'onglets sur écran étroit (téléphone plié),
/// barre latérale quand la largeur est « regular » (téléphone déplié / iPad).
struct RootView: View {
    @State private var selection: AppTab = .dashboard
    @State private var showSetup = false
    private var account = AccountSettings()

    var body: some View {
        TabView(selection: $selection) {
            Tab("Solde", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.dashboard) {
                NavigationStack { DashboardView() }
            }
            Tab("Opérations", systemImage: "arrow.left.arrow.right", value: AppTab.entries) {
                EntriesView()
            }
            Tab("Réglages", systemImage: "gearshape", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onAppear {
            if !account.isConfigured { showSetup = true }
        }
        .sheet(isPresented: $showSetup) {
            NavigationStack { SettingsView(isOnboarding: true) }
                .interactiveDismissDisabled()
        }
    }
}
