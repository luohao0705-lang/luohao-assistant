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
            .task { await state.restoreSession() }
        }
    }
}
