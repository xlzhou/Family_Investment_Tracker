import SwiftUI

struct PasscodeEntryView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @State private var passcode = ""
    @State private var isShaking = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Header
            VStack(spacing: 20) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)

                Text("Enter Passcode")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Enter your app passcode to continue")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Passcode Dots Display
            HStack(spacing: 20) {
                ForEach(0..<6, id: \.self) { index in
                    Circle()
                        .fill(index < passcode.count ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 15, height: 15)
                        .scaleEffect(index < passcode.count ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 0.1), value: passcode.count)
                }
            }
            .modifier(ShakeEffect(shakes: isShaking ? 3 : 0))

            // Passcode Input (Hidden)
            SecureField("", text: $passcode)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .opacity(0)
                .frame(height: 0)
                .onChange(of: passcode) { _, newValue in
                    // Limit to 6 digits
                    if newValue.count > 6 {
                        passcode = String(newValue.prefix(6))
                    }

                    // Auto-submit when 6 digits entered
                    if passcode.count == 6 {
                        authenticateWithPasscode()
                    }
                }

            Spacer()

            // Keypad
            VStack(spacing: 15) {
                // Number rows
                ForEach(0..<3) { row in
                    HStack(spacing: 20) {
                        ForEach(1..<4) { col in
                            let number = row * 3 + col
                            KeypadButton(number: "\(number)") {
                                if passcode.count < 6 {
                                    passcode += "\(number)"
                                }
                            }
                        }
                    }
                }

                // Bottom row with 0 and backspace
                HStack(spacing: 20) {
                    // Empty space
                    Color.clear
                        .frame(width: 75, height: 75)

                    // Zero
                    KeypadButton(number: "0") {
                        if passcode.count < 6 {
                            passcode += "0"
                        }
                    }

                    // Backspace
                    Button(action: {
                        if !passcode.isEmpty {
                            passcode.removeLast()
                        }
                    }) {
                        Image(systemName: "delete.left")
                            .font(.title2)
                            .foregroundColor(.primary)
                            .frame(width: 75, height: 75)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(Circle())
                    }
                }
            }

            // Biometric Authentication Button
            if authManager.isBiometricAvailable() {
                Button(action: {
                    authManager.authenticateWithBiometrics()
                }) {
                    HStack {
                        Image(systemName: authManager.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                            .font(.title3)
                        Text("Use \(authManager.getBiometricType())")
                            .font(.body)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(25)
                }
            }

            // Error Message
            if let error = authManager.authenticationError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Failed Attempts Counter
            let failedAttempts = authManager.getFailedAttempts()
            if failedAttempts > 0 {
                Text("Failed attempts: \(failedAttempts)")
                    .foregroundColor(.orange)
                    .font(.caption)
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // Clear any previous passcode entry
            passcode = ""
        }
    }

    private func authenticateWithPasscode() {
        authManager.authenticateWithAppPasscode(passcode)

        if !authManager.isAuthenticated {
            // Shake animation for wrong passcode
            withAnimation(.default) {
                isShaking = true
            }

            // Clear passcode after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                passcode = ""
                isShaking = false
            }
        }
    }
}

struct KeypadButton: View {
    let number: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(number)
                .font(.title)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .frame(width: 75, height: 75)
                .background(Color.gray.opacity(0.1))
                .clipShape(Circle())
        }
        .buttonStyle(KeypadButtonStyle())
    }
}

struct KeypadButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct ShakeEffect: ViewModifier {
    let shakes: Int

    func body(content: Content) -> some View {
        content
            .offset(x: shakes != 0 ? (shakes % 2 == 0 ? -5 : 5) : 0)
            .animation(.easeInOut(duration: 0.1).repeatCount(shakes, autoreverses: true), value: shakes)
    }
}

#Preview {
    PasscodeEntryView()
        .environmentObject(AuthenticationManager())
}