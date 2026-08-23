import SwiftUI

struct LoginView: View {
    @ObservedObject var state: AppState
    @State private var password = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Operations assistant").font(.largeTitle.weight(.bold))
            Text("Sign in to review cash, debt and action plans.").foregroundStyle(.secondary)
            SecureField("Password", text: $password).textFieldStyle(.roundedBorder)
            Button("Sign in") { Task { await state.login(password: password) } }.buttonStyle(.borderedProminent).disabled(password.count < 8 || state.isLoading)
            if let error = state.errorMessage { Text(error).foregroundStyle(.red) }
            Spacer()
        }.padding(24)
    }
}
