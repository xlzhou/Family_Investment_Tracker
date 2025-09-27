import SwiftUI

struct LockoutView: View {
    @EnvironmentObject var authManager: AuthenticationManager

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Warning Icon
            VStack(spacing: 20) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.red)

                Text("Account Temporarily Locked")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text("Too many failed passcode attempts")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Lockout Information
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Time Remaining")
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
                    Text("Failed Attempts")
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
                    Text("Your data is protected by security lockout")
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SecurityInfoRow(attempts: "3-4", duration: "1 minute")
                    SecurityInfoRow(attempts: "5-6", duration: "5 minutes")
                    SecurityInfoRow(attempts: "7+", duration: "15 minutes")
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
                        Text("Try \(authManager.getBiometricType())")
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

    var body: some View {
        HStack {
            Text("\(attempts) attempts:")
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
}