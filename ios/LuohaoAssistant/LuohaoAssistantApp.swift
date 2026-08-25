import SwiftUI

@main
struct LuohaoAssistantApp: App {
    @StateObject private var state = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                Group {
                    if state.isAuthenticated { AppShellView(state: state) }
                    else if state.biometricLocked { BiometricLockView(state: state) }
                    else { LoginView(state: state) }
                }
            }
            .task { await state.restoreSession() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    state.lockForBackground()
                case .active:
                    guard state.biometricLocked else { return }
                    Task { await state.unlockForForeground() }
                default:
                    break
                }
            }
        }
    }
}

private struct BiometricLockView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            LuohaoDesign.canvas.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "faceid")
                    .font(.system(size: 48, weight: .medium))
                    .foregroundStyle(.orange)
                Text("需要面容 ID 验证")
                    .font(.title2.weight(.semibold))
                Text("每次重新进入经营助理，都需要先验证身份。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    Task { await state.unlockForForeground() }
                } label: {
                    Label("重新验证", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.large)
                .disabled(state.isLoading)
            }
            .frame(maxWidth: 340)
            .padding(24)
        }
        .task {
            await state.unlockForForeground()
        }
    }
}
