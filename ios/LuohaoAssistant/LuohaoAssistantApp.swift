import SwiftUI

@main
struct LuohaoAssistantApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if state.isAuthenticated { DashboardView(state: state) }
                else { LoginView(state: state) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(uiColor: .systemGroupedBackground))
            .task { await state.restoreSession() }
        }
    }
}
