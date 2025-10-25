import SwiftUI

struct PasscodeSettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingChangePasscode = false
    @State private var showingRemovePasscode = false

    var body: some View {
        NavigationView {
            List {
                // Security Status Section
                Section(header: Text(localizationManager.localizedString(for: "passcodeSettings.securityStatus"))) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text(localizationManager.localizedString(for: "passcodeSettings.appPasscode"))
                                .font(.headline)
                            Text(localizationManager.localizedString(for: "passcodeSettings.enabled"))
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        Spacer()
                    }

                    if authManager.isBiometricAvailable() {
                        HStack {
                            Image(systemName: authManager.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(authManager.getBiometricType())
                                    .font(.headline)
                                Text(localizationManager.localizedString(for: "passcodeSettings.available"))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                        }
                    }
                }

                // Security Actions Section
                Section(header: Text(localizationManager.localizedString(for: "passcodeSettings.passcodeManagement"))) {
                    Button(action: {
                        showingChangePasscode = true
                    }) {
                        HStack {
                            Image(systemName: "key.horizontal")
                                .foregroundColor(.blue)
                            Text(localizationManager.localizedString(for: "passcodeSettings.changePasscode"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }

                    Button(action: {
                        showingRemovePasscode = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text(localizationManager.localizedString(for: "passcodeSettings.removePasscode"))
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.red)
                }

                // Security Information Section
                Section(header: Text(localizationManager.localizedString(for: "passcodeSettings.securityInformation"))) {
                    let failedAttempts = authManager.getFailedAttempts()
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(failedAttempts > 0 ? .orange : .gray)
                        Text(localizationManager.localizedString(for: "passcodeSettings.failedAttempts"))
                        Spacer()
                        Text("\(failedAttempts)")
                            .foregroundColor(failedAttempts > 0 ? .orange : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text(localizationManager.localizedString(for: "passcodeSettings.securityPolicy"))
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(localizationManager.localizedString(for: "passcodeSettings.lockoutPolicy1"))
                            Text(localizationManager.localizedString(for: "passcodeSettings.lockoutPolicy2"))
                            Text(localizationManager.localizedString(for: "passcodeSettings.lockoutPolicy3"))
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 25)
                    }
                    .padding(.vertical, 5)
                }
            }
            .navigationTitle(localizationManager.localizedString(for: "passcodeSettings.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localizationManager.localizedString(for: "passcodeSettings.done")) {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingChangePasscode) {
            ChangePasscodeView()
        }
        .sheet(isPresented: $showingRemovePasscode) {
            RemovePasscodeView()
        }
    }
}

struct ChangePasscodeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @State private var currentPasscode = ""
    @State private var newPasscode = ""
    @State private var confirmPasscode = ""
    @State private var step: ChangePasscodeStep = .current
    @State private var error: String?

    enum ChangePasscodeStep {
        case current, new, confirm
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "key.horizontal")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)

                    Text(stepTitle)
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(stepDescription)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 20) {
                    SecureField(stepPlaceholder, text: stepBinding)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)
                        .onSubmit {
                            handleStepSubmission()
                        }

                    if let error = error {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    Button(action: handleStepSubmission) {
                        Text(stepButtonTitle)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isStepValid ? Color.blue : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!isStepValid)
                }
                .padding(.horizontal, 40)

                Spacer()
            }
            .navigationTitle(localizationManager.localizedString(for: "changePasscode.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localizationManager.localizedString(for: "changePasscode.cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .current: return localizationManager.localizedString(for: "changePasscode.currentPasscode")
        case .new: return localizationManager.localizedString(for: "changePasscode.newPasscode")
        case .confirm: return localizationManager.localizedString(for: "changePasscode.confirmPasscode")
        }
    }

    private var stepDescription: String {
        switch step {
        case .current: return localizationManager.localizedString(for: "changePasscode.enterCurrent")
        case .new: return localizationManager.localizedString(for: "changePasscode.enterNew")
        case .confirm: return localizationManager.localizedString(for: "changePasscode.confirmNew")
        }
    }

    private var stepPlaceholder: String {
        switch step {
        case .current: return localizationManager.localizedString(for: "changePasscode.currentPasscode")
        case .new: return localizationManager.localizedString(for: "changePasscode.newPasscode")
        case .confirm: return localizationManager.localizedString(for: "changePasscode.confirmPasscode")
        }
    }

    private var stepBinding: Binding<String> {
        switch step {
        case .current: return $currentPasscode
        case .new: return $newPasscode
        case .confirm: return $confirmPasscode
        }
    }

    private var stepButtonTitle: String {
        switch step {
        case .current: return localizationManager.localizedString(for: "changePasscode.continue")
        case .new: return localizationManager.localizedString(for: "changePasscode.continue")
        case .confirm: return localizationManager.localizedString(for: "changePasscode.changeButton")
        }
    }

    private var isStepValid: Bool {
        switch step {
        case .current:
            return currentPasscode.count >= 4 && currentPasscode.count <= 6
        case .new:
            return newPasscode.count >= 4 && newPasscode.count <= 6 && newPasscode.allSatisfy { $0.isNumber }
        case .confirm:
            return confirmPasscode == newPasscode && !confirmPasscode.isEmpty
        }
    }

    private func handleStepSubmission() {
        guard isStepValid else { return }

        switch step {
        case .current:
            // Verify current passcode
            if KeychainService.shared.verifyPasscode(currentPasscode) {
                step = .new
                error = nil
            } else {
                error = localizationManager.localizedString(for: "changePasscode.errorIncorrect")
            }

        case .new:
            step = .confirm
            error = nil

        case .confirm:
            // Change passcode
            if authManager.changeAppPasscode(currentPasscode: currentPasscode, newPasscode: newPasscode) {
                dismiss()
            } else {
                error = authManager.authenticationError ?? localizationManager.localizedString(for: "changePasscode.errorFailed")
            }
        }
    }
}

struct RemovePasscodeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @State private var currentPasscode = ""
    @State private var error: String?

    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                Spacer()

                VStack(spacing: 20) {
                    Image(systemName: "trash.circle")
                        .font(.system(size: 60))
                        .foregroundColor(.red)

                    Text(localizationManager.localizedString(for: "removePasscode.title"))
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text(localizationManager.localizedString(for: "removePasscode.subtitle"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 20) {
                    SecureField(localizationManager.localizedString(for: "removePasscode.currentPasscode"), text: $currentPasscode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)

                    if let error = error {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    VStack(spacing: 10) {
                        Button(action: removePasscode) {
                            Text(localizationManager.localizedString(for: "removePasscode.removeButton"))
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isValid ? Color.red : Color.gray)
                                .cornerRadius(12)
                        }
                        .disabled(!isValid)

                        Text(localizationManager.localizedString(for: "removePasscode.warning"))
                            .font(.caption)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
            }
            .navigationTitle(localizationManager.localizedString(for: "removePasscode.navigationTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localizationManager.localizedString(for: "removePasscode.cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var isValid: Bool {
        return currentPasscode.count >= 4 && currentPasscode.count <= 6
    }

    private func removePasscode() {
        if authManager.removeAppPasscode(currentPasscode: currentPasscode) {
            dismiss()
        } else {
            error = authManager.authenticationError ?? localizationManager.localizedString(for: "removePasscode.errorFailed")
        }
    }
}

#Preview {
    PasscodeSettingsView()
        .environmentObject(AuthenticationManager())
        .environmentObject(LocalizationManager.shared)
}