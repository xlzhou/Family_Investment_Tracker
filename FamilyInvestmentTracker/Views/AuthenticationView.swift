import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
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

                Text("Family Investment Tracker")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Secure access to your family's investment portfolio")
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
                    Text("Authenticated")
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
            Text("Set Up App Password")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                SecureField("Create password", text: $password)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textContentType(.newPassword)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Password Strength:")
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

                    Text("• Minimum 8 characters")
                        .font(.caption)
                        .foregroundColor(password.count >= 8 ? .green : .secondary)

                    Text("• Letters, numbers, and special characters")
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
                Text("Set Password")
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
            Text("Enter Password")
                .font(.headline)

            SecureField("Password", text: $password)
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
                Text("Unlock")
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
                        Text("Use \(authManager.getBiometricType())")
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
                Button("Forgot Password?") {
                    authManager.startPasswordRecovery()
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

            Text("Account Locked")
                .font(.headline)
                .foregroundColor(.red)

            Text("Too many failed attempts")
                .font(.body)
                .foregroundColor(.secondary)

            Text("Time remaining: \(authManager.getLockoutTimeRemainingString())")
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
                        Text("Use \(authManager.getBiometricType())")
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
        case 0: return "Too weak"
        case 1: return "Weak"
        case 2: return "Fair"
        case 3: return "Good"
        case 4: return "Strong"
        default: return "Too weak"
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