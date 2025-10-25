import SwiftUI

struct SecurityQuestionsManagementView: View {
    @ObservedObject var authManager: AuthenticationManager
    @EnvironmentObject private var localizationManager: LocalizationManager
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
            .navigationTitle(localizationManager.localizedString(for: "securityQuestions.title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(localizationManager.localizedString(for: "securityQuestions.done")) {
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
        .alert(localizationManager.localizedString(for: "securityQuestions.removeAlert.title"), isPresented: $showingRemoveAlert) {
            Button(localizationManager.localizedString(for: "securityQuestions.removeAlert.remove"), role: .destructive) {
                removeSecurityQuestions()
            }
            Button(localizationManager.localizedString(for: "securityQuestions.removeAlert.cancel"), role: .cancel) { }
        } message: {
            Text(localizationManager.localizedString(for: "securityQuestions.removeAlert.message"))
        }
    }

    private var passwordVerificationView: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)

                Text(localizationManager.localizedString(for: "securityQuestions.verification.title"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(localizationManager.localizedString(for: "securityQuestions.verification.subtitle"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Password Input
            VStack(alignment: .leading, spacing: 8) {
                Text(localizationManager.localizedString(for: "securityQuestions.verification.currentPassword"))
                    .font(.body)
                    .fontWeight(.medium)

                SecureField(localizationManager.localizedString(for: "securityQuestions.verification.placeholder"), text: $currentPassword)
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
                    Text(isVerifyingPassword ? localizationManager.localizedString(for: "securityQuestions.verification.verifying") : localizationManager.localizedString(for: "securityQuestions.verification.verify"))
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

                Text(hasSecurityQuestions ? localizationManager.localizedString(for: "securityQuestions.management.activeTitle") : localizationManager.localizedString(for: "securityQuestions.management.setupTitle"))
                    .font(.title2)
                    .fontWeight(.bold)

                Text(hasSecurityQuestions ?
                     localizationManager.localizedString(for: "securityQuestions.management.activeSubtitle") :
                     localizationManager.localizedString(for: "securityQuestions.management.setupSubtitle"))
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
                            Text(localizationManager.localizedString(for: "securityQuestions.management.configured"))
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
                                Text(localizationManager.localizedString(for: "securityQuestions.management.changeQuestions"))
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
                                Text(localizationManager.localizedString(for: "securityQuestions.management.removeQuestions"))
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
                            Text(localizationManager.localizedString(for: "securityQuestions.management.setupQuestions"))
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
                            Text(localizationManager.localizedString(for: "securityQuestions.management.infoTitle"))
                                .fontWeight(.medium)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(localizationManager.localizedString(for: "securityQuestions.management.infoBenefit1"))
                            Text(localizationManager.localizedString(for: "securityQuestions.management.infoBenefit2"))
                            Text(localizationManager.localizedString(for: "securityQuestions.management.infoBenefit3"))
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
                errorMessage = localizationManager.localizedString(for: "securityQuestions.verification.error")
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
            errorMessage = localizationManager.localizedString(for: "securityQuestions.management.removeError")
        }
    }
}

#Preview {
    SecurityQuestionsManagementView(
        authManager: AuthenticationManager(),
        isPresented: Binding.constant(true)
    )
    .environmentObject(LocalizationManager.shared)
}