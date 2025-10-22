import SwiftUI

struct SecurityQuestionsManagementView: View {
    @ObservedObject var authManager: AuthenticationManager
    @Binding var isPresented: Bool

    @State private var currentPassword = ""
    @State private var isVerifyingPassword = false
    @State private var isPasswordVerified = false
    @State private var showingSetup = false
    @State private var showingRemoveAlert = false
    @State private var errorMessage: String?

    var hasSecurityQuestions: Bool {
        authManager.hasSecurityQuestionsSetup()
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                if !isPasswordVerified {
                    passwordVerificationView
                } else {
                    securityQuestionsManagementView
                }
            }
            .padding()
            .navigationTitle("Security Questions")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }
            }
        }
        .sheet(isPresented: $showingSetup) {
            SecurityQuestionsSetupView(
                authManager: authManager,
                isPresented: $showingSetup,
                onComplete: {
                    // Refresh the view after setup
                },
                isUpdating: hasSecurityQuestions
            )
        }
        .alert("Remove Security Questions?", isPresented: $showingRemoveAlert) {
            Button("Remove", role: .destructive) {
                removeSecurityQuestions()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to remove your security questions? You won't be able to recover your password using them.")
        }
    }

    private var passwordVerificationView: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)

                Text("Verify Your Password")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Enter your current password to manage security questions")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Password Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Current Password")
                    .font(.body)
                    .fontWeight(.medium)

                SecureField("Enter your password", text: $currentPassword)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.password)
                    .onSubmit {
                        verifyPassword()
                    }
            }

            // Error Message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            // Verify Button
            Button(action: verifyPassword) {
                HStack {
                    if isVerifyingPassword {
                        ProgressView()
                            .scaleEffect(0.8)
                            .tint(.white)
                    }
                    Text(isVerifyingPassword ? "Verifying..." : "Verify Password")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canVerify ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!canVerify || isVerifyingPassword)

            Spacer()
        }
    }

    private var securityQuestionsManagementView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: hasSecurityQuestions ? "checkmark.shield" : "plus.circle")
                    .font(.system(size: 50))
                    .foregroundColor(hasSecurityQuestions ? .green : .blue)

                Text(hasSecurityQuestions ? "Security Questions Active" : "Set Up Security Questions")
                    .font(.title2)
                    .fontWeight(.bold)

                Text(hasSecurityQuestions ?
                     "Your security questions are set up and ready to help you recover your password." :
                     "Set up security questions to help recover your password if you forget it.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                if hasSecurityQuestions {
                    // Current Status
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "questionmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Security questions configured")
                                .fontWeight(.medium)
                            Spacer()
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)

                        // Change Questions Button
                        Button(action: {
                            showingSetup = true
                        }) {
                            HStack {
                                Image(systemName: "pencil.circle")
                                Text("Change Security Questions")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }

                        // Remove Questions Button
                        Button(action: {
                            showingRemoveAlert = true
                        }) {
                            HStack {
                                Image(systemName: "trash.circle")
                                Text("Remove Security Questions")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                } else {
                    // Setup Button
                    Button(action: {
                        showingSetup = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                            Text("Set Up Security Questions")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }

                    // Info Box
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                            Text("Why set up security questions?")
                                .fontWeight(.medium)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• Recover your password if you forget it")
                            Text("• Alternative to biometric authentication")
                            Text("• Keep your data safe and accessible")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
            }

            Spacer()
        }
    }

    private var canVerify: Bool {
        !currentPassword.isEmpty && !isVerifyingPassword
    }

    private func verifyPassword() {
        isVerifyingPassword = true
        errorMessage = nil

        // Simulate a brief delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            // Use the existing authentication method to verify password
            let tempAuthManager = AuthenticationManager()
            tempAuthManager.authenticateWithAppPassword(currentPassword)

            if tempAuthManager.isAuthenticated {
                isPasswordVerified = true
                isVerifyingPassword = false
                currentPassword = "" // Clear password for security
            } else {
                errorMessage = "Incorrect password. Please try again."
                isVerifyingPassword = false
                currentPassword = ""
            }
        }
    }

    private func removeSecurityQuestions() {
        if authManager.securityQuestionManager.removeSecurityQuestions() {
            // Successfully removed
            // The view will automatically update since hasSecurityQuestions will now return false
        } else {
            errorMessage = "Failed to remove security questions. Please try again."
        }
    }
}

#Preview {
    SecurityQuestionsManagementView(
        authManager: AuthenticationManager(),
        isPresented: Binding.constant(true)
    )
}