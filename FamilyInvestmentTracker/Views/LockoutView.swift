import SwiftUI

struct LockoutView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Warning Icon
            VStack(spacing: 20) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)

                Text(localizationManager.localizedString(for: "lockoutView.title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(localizationManager.localizedString(for: "lockoutView.subtitle"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Lockout Information
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text(localizationManager.localizedString(for: "lockoutView.timeRemaining"))
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(authManager.getLockoutTimeRemaining())
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.red)
                        .monospacedDigit()
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)

                VStack(spacing: 8) {
                    Text(localizationManager.localizedString(for: "lockoutView.failedAttempts"))
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("\(authManager.getFailedAttempts())")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
            }
            .padding(.horizontal, 40)

            // Security Information
            VStack(spacing: 15) {
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text(localizationManager.localizedString(for: "lockoutView.securityMessage"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SecurityInfoRow(attempts: "3-4", duration: localizationManager.localizedString(for: "lockoutView.duration.oneMinute"))
                    SecurityInfoRow(attempts: "5-6", duration: localizationManager.localizedString(for: "lockoutView.duration.fiveMinutes"))
                    SecurityInfoRow(attempts: "7+", duration: localizationManager.localizedString(for: "lockoutView.duration.fifteenMinutes"))
                }
                .padding()
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)
            }
            .padding(.horizontal, 40)

            // Biometric Authentication (if available)
            if authManager.isBiometricAvailable() {
                Button(action: {
                    authManager.authenticateWithBiometrics()
                }) {
                    HStack {
                        Image(systemName: authManager.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                            .font(.title2)
                        Text(String(format: localizationManager.localizedString(for: "lockoutView.tryBiometric"), authManager.getBiometricType()))
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

            Spacer()
        }
        .padding()
    }
}

struct SecurityInfoRow: View {
    let attempts: String
    let duration: String
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        HStack {
            Text("\(attempts) \(localizationManager.localizedString(for: "lockoutView.securityInfo.attempts"))")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(duration)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
    }
}

#Preview {
    LockoutView()
        .environmentObject(AuthenticationManager())
        .environmentObject(LocalizationManager())
}