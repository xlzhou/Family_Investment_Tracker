import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var localizationManager: LocalizationManager
    @State private var password = ""
    @State private var showingSecurityQuestionsSetup = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // App Icon and Title
            VStack(spacing: 20) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 80))
                    .foregroundColor(.blue)

                localizationManager.text("app.title")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                localizationManager.text("app.subtitle")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()

            // Authentication Interface
            Group {
                switch authManager.authenticationState {
                case .needsPasscodeSetup:
                    PasswordSetupInterface()
                case .needsAuthentication:
                    PasswordEntryInterface()
                case .temporarilyLocked:
                    LockoutInterface()
                case .passwordRecovery:
                    PasswordRecoveryView(authManager: authManager)
                case .authenticated:
                    localizationManager.text("auth.status.authenticated")
                        .foregroundColor(.green)
                }
            }

            Spacer()
        }
        .padding()
        .onAppear {
            authManager.checkAuthenticationStatus()
        }
        .sheet(isPresented: $showingSecurityQuestionsSetup) {
            SecurityQuestionsSetupView(
                authManager: authManager,
                isPresented: $showingSecurityQuestionsSetup,
                onComplete: {
                    // Security questions setup completed, continue with normal flow
                }
            )
        }
    }

    @ViewBuilder
    private func PasswordSetupInterface() -> some View {
        VStack(spacing: 20) {
            localizationManager.text("auth.setupTitle")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                SecureField(localizationManager.localizedString(for: "auth.createPasswordPlaceholder"), text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.newPassword)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        localizationManager.text("auth.passwordStrength")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text(passwordStrengthText(password))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(passwordStrengthColor(password))
                    }

                    // Password strength bar
                    HStack(spacing: 2) {
                        ForEach(0..<4, id: \.self) { index in
                            Rectangle()
                                .fill(index < passwordStrengthLevel(password) ? passwordStrengthColor(password) : Color.gray.opacity(0.3))
                                .frame(height: 4)
                                .cornerRadius(2)
                        }
                    }

                    localizationManager.text("auth.passwordRequirement.length")
                        .font(.caption)
                        .foregroundColor(password.count >= 8 ? .green : .secondary)

                    localizationManager.text("auth.passwordRequirement.complexity")
                        .font(.caption)
                        .foregroundColor(containsRequiredCharacterTypes(password) ? .green : .secondary)
                }
            }

            Button(action: {
                if authManager.setAppPassword(password) {
                    password = ""
                    // Show security questions setup after password is set
                    showingSecurityQuestionsSetup = true
                }
            }) {
                localizationManager.text("auth.setPassword")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidPassword ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!isValidPassword)

            if let error = authManager.authenticationError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private func PasswordEntryInterface() -> some View {
        VStack(spacing: 20) {
            localizationManager.text("auth.enterPassword")
                .font(.headline)

            SecureField(localizationManager.localizedString(for: "auth.passwordPlaceholder"), text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textContentType(.password)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onSubmit {
                    authManager.authenticateWithAppPassword(password)
                    if !authManager.isAuthenticated {
                        password = ""
                    }
                }

            

            Button(action: {
                authManager.authenticateWithAppPassword(password)
                if !authManager.isAuthenticated {
                    password = ""
                }
            }) {
                localizationManager.text("auth.unlock")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidPassword ? Color.blue : Color.gray)
                    .cornerRadius(12)
            }
            .disabled(!isValidPassword)

            if let error = authManager.authenticationError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // Biometric Authentication Button
            if authManager.isBiometricAvailable() {
                Button(action: {
                    authManager.authenticateWithBiometrics()
                }) {
                    HStack {
                        Image(systemName: authManager.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                            .font(.title2)
                        Text(localizationManager.localizedString(for: "auth.biometric.use", arguments: authManager.getBiometricType()))
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
            }

            // Forgot Password Button
            // Always show during development/testing, or when recovery options are available
            if authManager.isBiometricAvailable() || authManager.hasSecurityQuestionsSetup() || true {
                Button {
                    authManager.startPasswordRecovery()
                } label: {
                    localizationManager.text("auth.forgotPassword")
                }
                .font(.body)
                .foregroundColor(.blue)
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 40)
    }

    @ViewBuilder
    private func LockoutInterface() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.red)

            localizationManager.text("auth.locked.title")
                .font(.headline)
                .foregroundColor(.red)

            localizationManager.text("auth.locked.subtitle")
                .font(.body)
                .foregroundColor(.secondary)

            Text(localizationManager.localizedString(for: "auth.locked.remaining", arguments: authManager.getLockoutTimeRemainingString()))
                .font(.body)
                .foregroundColor(.orange)

            // Biometric unlock still available during lockout
            if authManager.isBiometricAvailable() {
                Button(action: {
                    authManager.authenticateWithBiometrics()
                }) {
                    HStack {
                        Image(systemName: authManager.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                            .font(.title2)
                        Text(localizationManager.localizedString(for: "auth.biometric.use", arguments: authManager.getBiometricType()))
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            }
        }
    }

    private var isValidPassword: Bool {
        return password.count >= 8 && containsRequiredCharacterTypes(password)
    }

    private func containsRequiredCharacterTypes(_ password: String) -> Bool {
        let hasLetter = password.contains { $0.isLetter }
        let hasNumber = password.contains { $0.isNumber }
        let hasSpecial = password.contains { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }

        return hasLetter && (hasNumber || hasSpecial)
    }

    private func passwordStrengthLevel(_ password: String) -> Int {
        if password.isEmpty { return 0 }

        var score = 0

        // Length scoring
        if password.count >= 8 { score += 1 }
        if password.count >= 12 { score += 1 }

        // Character variety scoring
        let hasLower = password.contains { $0.isLowercase }
        let hasUpper = password.contains { $0.isUppercase }
        let hasNumber = password.contains { $0.isNumber }
        let hasSpecial = password.contains { "!@#$%^&*()_+-=[]{}|;:,.<>?".contains($0) }

        let characterTypes = [hasLower, hasUpper, hasNumber, hasSpecial].filter { $0 }.count

        if characterTypes >= 2 { score += 1 }
        if characterTypes >= 3 { score += 1 }

        return min(score, 4)
    }

    private func passwordStrengthText(_ password: String) -> String {
        switch passwordStrengthLevel(password) {
        case 0: return localizationManager.localizedString(for: "auth.passwordStrength.tooWeak")
        case 1: return localizationManager.localizedString(for: "auth.passwordStrength.weak")
        case 2: return localizationManager.localizedString(for: "auth.passwordStrength.fair")
        case 3: return localizationManager.localizedString(for: "auth.passwordStrength.good")
        case 4: return localizationManager.localizedString(for: "auth.passwordStrength.strong")
        default: return localizationManager.localizedString(for: "auth.passwordStrength.tooWeak")
        }
    }

    private func passwordStrengthColor(_ password: String) -> Color {
        switch passwordStrengthLevel(password) {
        case 0, 1: return .red
        case 2: return .orange
        case 3: return .yellow
        case 4: return .green
        default: return .red
        }
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(AuthenticationManager())
}
