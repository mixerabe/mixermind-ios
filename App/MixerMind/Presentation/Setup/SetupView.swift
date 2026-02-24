import SwiftUI

struct SetupView: View {
    @State private var viewModel = SetupViewModel()
    var onConnected: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("remindr")
                .font(.largeTitle.bold())

            Text("Set up your Supabase project")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Setup Mode", selection: $viewModel.isManualMode) {
                Text("Set up for me").tag(false)
                Text("I have a project").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            if viewModel.isManualMode {
                manualModeView
            } else {
                autoModeView
            }

            Button {
                SupabaseManager.shared.configure(
                    url: Constants.publicSupabaseURL,
                    key: Constants.publicSupabaseKey
                )
                onConnected()
            } label: {
                Text("Continue in Public (Testing)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .alert("Project Already Exists", isPresented: $viewModel.showAlreadyExistsAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A project named \"\(viewModel.existingProjectName)\" already exists. Use \"I have a project\" to connect manually.")
        }
    }

    // MARK: - Auto Setup

    private var autoModeView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Supabase Access Token")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("sbp_...", text: $viewModel.accessToken)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            if viewModel.isSettingUp {
                VStack(spacing: 8) {
                    ProgressView()
                    Text(viewModel.setupProgress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                Task {
                    let result = await viewModel.setupProject()
                    if result == .created { onConnected() }
                }
            } label: {
                Text("Set Up")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.accessToken.isEmpty || viewModel.isSettingUp)
            .padding(.horizontal)

            Text("Paste your personal access token from\nsupabase.com/dashboard/account/tokens")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Manual Connect

    private var manualModeView: some View {
        VStack(spacing: 12) {
            TextField("Supabase URL", text: $viewModel.supabaseURL)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)

            TextField("Publishable Key", text: $viewModel.supabaseKey)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task {
                    let success = await viewModel.manualConnect()
                    if success { onConnected() }
                }
            } label: {
                if viewModel.isConnecting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    Text("Connect")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.supabaseURL.isEmpty || viewModel.supabaseKey.isEmpty || viewModel.isConnecting)
        }
        .padding(.horizontal)
    }
}
