import SwiftUI

struct PasscodeSettingsView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingChangePasscode = false
    @State private var showingRemovePasscode = false

    var body: some View {
        NavigationView {
            List {
                // Security Status Section
                Section(header: Text("Security Status")) {
                    HStack {
                        Image(systemName: "lock.shield.fill")
                            .foregroundColor(.green)
                        VStack(alignment: .leading) {
                            Text("App Passcode")
                                .font(.headline)
                            Text("Enabled")
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
                                Text("Available")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            Spacer()
                        }
                    }
                }

                // Security Actions Section
                Section(header: Text("Passcode Management")) {
                    Button(action: {
                        showingChangePasscode = true
                    }) {
                        HStack {
                            Image(systemName: "key.horizontal")
                                .foregroundColor(.blue)
                            Text("Change Passcode")
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
                            Text("Remove Passcode")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                    .foregroundColor(.red)
                }

                // Security Information Section
                Section(header: Text("Security Information")) {
                    let failedAttempts = authManager.getFailedAttempts()
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundColor(failedAttempts > 0 ? .orange : .gray)
                        Text("Failed Attempts")
                        Spacer()
                        Text("\(failedAttempts)")
                            .foregroundColor(failedAttempts > 0 ? .orange : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Security Policy")
                                .font(.headline)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• 3-4 failed attempts: 1 minute lockout")
                            Text("• 5-6 failed attempts: 5 minute lockout")
                            Text("• 7+ failed attempts: 15 minute lockout")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading, 25)
                    }
                    .padding(.vertical, 5)
                }
            }
            .navigationTitle("Passcode Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
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
            .navigationTitle("Change Passcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case .current: return "Current Passcode"
        case .new: return "New Passcode"
        case .confirm: return "Confirm Passcode"
        }
    }

    private var stepDescription: String {
        switch step {
        case .current: return "Enter your current passcode"
        case .new: return "Enter your new passcode (4-6 digits)"
        case .confirm: return "Confirm your new passcode"
        }
    }

    private var stepPlaceholder: String {
        switch step {
        case .current: return "Current Passcode"
        case .new: return "New Passcode"
        case .confirm: return "Confirm Passcode"
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
        case .current: return "Continue"
        case .new: return "Continue"
        case .confirm: return "Change Passcode"
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
                error = "Incorrect current passcode"
            }

        case .new:
            step = .confirm
            error = nil

        case .confirm:
            // Change passcode
            if authManager.changeAppPasscode(currentPasscode: currentPasscode, newPasscode: newPasscode) {
                dismiss()
            } else {
                error = authManager.authenticationError ?? "Failed to change passcode"
            }
        }
    }
}

struct RemovePasscodeView: View {
    @EnvironmentObject var authManager: AuthenticationManager
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

                    Text("Remove Passcode")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Enter your current passcode to remove app security")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 20) {
                    SecureField("Current Passcode", text: $currentPasscode)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .keyboardType(.numberPad)

                    if let error = error {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }

                    VStack(spacing: 10) {
                        Button(action: removePasscode) {
                            Text("Remove Passcode")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(isValid ? Color.red : Color.gray)
                                .cornerRadius(12)
                        }
                        .disabled(!isValid)

                        Text("Warning: Removing passcode will make your data less secure")
                            .font(.caption)
                            .foregroundColor(.orange)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 40)

                Spacer()
            }
            .navigationTitle("Remove Passcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
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
            error = authManager.authenticationError ?? "Failed to remove passcode"
        }
    }
}

#Preview {
    PasscodeSettingsView()
        .environmentObject(AuthenticationManager())
}