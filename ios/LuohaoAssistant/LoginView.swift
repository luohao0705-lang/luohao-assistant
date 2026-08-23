import SwiftUI

struct LoginView: View {
    @ObservedObject var state: AppState
    @State private var password = ""
    var body: some View {
        GeometryReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                Spacer(minLength: 32)
                VStack(alignment: .leading, spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("洛浩经营台")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("把现金、风险和下一步行动，放在同一个清晰的视角里。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.bottom, 32)

                VStack(alignment: .leading, spacing: 12) {
                    Text("登录你的经营数据")
                        .font(.headline)
                    SecureField("请输入访问密码", text: $password)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .onSubmit { signIn() }
                    Button(action: signIn) {
                        HStack {
                            Spacer()
                            if state.isLoading { ProgressView().tint(.white) }
                            else { Text("进入经营台").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.large)
                    .disabled(password.count < 8 || state.isLoading)
                    if let error = state.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(20)
                .background(.background, in: RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.06), radius: 16, y: 6)

                Spacer(minLength: 32)
                Text("数据仅供本人使用 · AI 的写入操作需要你的确认")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: proxy.size.height, alignment: .topLeading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private func signIn() {
        guard password.count >= 8 else { return }
        Task { await state.login(password: password) }
    }
}
