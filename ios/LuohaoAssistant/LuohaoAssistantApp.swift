import SwiftUI

@main
struct LuohaoAssistantApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                Group {
                    if state.isAuthenticated { AppShellView(state: state) }
                    else { LoginView(state: state) }
                }
            }
            .task { await state.restoreSession() }
        }
    }
}
