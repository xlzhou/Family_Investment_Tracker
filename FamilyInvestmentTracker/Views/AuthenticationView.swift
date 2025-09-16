import SwiftUI

struct AuthenticationView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    
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
            
            // Authentication Buttons
            VStack(spacing: 20) {
                Button(action: {
                    authManager.authenticateWithBiometrics()
                }) {
                    HStack {
                        Image(systemName: authManager.getBiometricType() == "Face ID" ? "faceid" : "touchid")
                            .font(.title2)
                        Text("Unlock with \(authManager.getBiometricType())")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
                
                Button(action: {
                    authManager.authenticateWithPasscode()
                }) {
                    HStack {
                        Image(systemName: "key.fill")
                            .font(.title2)
                        Text("Use Passcode")
                            .font(.headline)
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                .padding(.horizontal, 40)
            }
            
            // Error Message
            if let error = authManager.authenticationError {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
    }
}

#Preview {
    AuthenticationView()
        .environmentObject(AuthenticationManager())
}