import SwiftUI

struct LoginView: View {
    @ObservedObject var state: AppState
    @State private var password = ""
    @FocusState private var passwordFocused: Bool

    private var hasPINInput: Bool {
        !password.isEmpty
    }

    var body: some View {
        ZStack {
            LuohaoDesign.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    brandHeader
                    loginForm
                    privacyNote
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 22)
                .padding(.top, 34)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
        }
        .onTapGesture { passwordFocused = false }
    }

    private var brandHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.and.chart.xyaxis")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.orange)
                    .frame(width: 44, height: 44)
                    .background(LuohaoDesign.accentTint, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                Text("经营助理")
                    .font(.headline.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("先看清现金，\n再决定下一步。")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("把现金、风险和事项放在同一个清晰的经营视角里。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("进入你的经营数据")
                    .font(.title3.weight(.semibold))
                Text("数据只属于你，AI 的写入操作需要你的确认。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            SecureField("输入8位数字", text: $password)
                .font(.body)
                .textContentType(.password)
                .keyboardType(.numberPad)
                .submitLabel(.go)
                .focused($passwordFocused)
                .padding(.horizontal, 14)
                .frame(minHeight: 48)
                .background(LuohaoDesign.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(passwordFocused ? Color.orange.opacity(0.8) : LuohaoDesign.hairline, lineWidth: passwordFocused ? 1.5 : 1)
                }
                .onSubmit { signIn() }
                .onChange(of: password) { _, newValue in
                    let digits = newValue.utf8
                        .filter { $0 >= 48 && $0 <= 57 }
                        .prefix(8)
                    let normalized = String(decoding: digits, as: UTF8.self)
                    if normalized != newValue { password = normalized }
                }

            HStack(spacing: 7) {
                ForEach(0..<8, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(index < password.count ? Color.orange : Color.primary.opacity(0.08))
                        .frame(maxWidth: .infinity)
                        .frame(height: 5)
                }
            }
            .accessibilityHidden(true)

            Button(action: signIn) {
                PrimaryActionLabel(title: "进入经营台", systemImage: "arrow.right", isLoading: state.isLoading)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            .disabled(!hasPINInput || state.isLoading)

            if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .surfaceCard(padding: 20, radius: 18)
    }

    private var privacyNote: some View {
        Label("仅限本人使用 · 所有写入都需要确认", systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private func signIn() {
        guard hasPINInput else { return }
        passwordFocused = false
        Task { await state.login(password: password) }
    }
}
