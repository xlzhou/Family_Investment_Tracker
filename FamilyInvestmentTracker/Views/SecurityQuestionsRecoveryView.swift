import SwiftUI

struct SecurityQuestionsRecoveryView: View {
    @ObservedObject var authManager: AuthenticationManager
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Binding var isPresented: Bool
    let onSuccess: () -> Void

    @State private var answers: [String] = []
    @State private var securityQuestions: [SecurityQuestion] = []
    @State private var isVerifying = false

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)

                    Text(localizationManager.localizedString(for: "securityQuestionsRecovery.title"))
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(localizationManager.localizedString(for: "securityQuestionsRecovery.subtitle"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }

                if securityQuestions.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text(localizationManager.localizedString(for: "securityQuestionsRecovery.loading"))
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            ForEach(Array(securityQuestions.enumerated()), id: \.offset) { index, question in
                                SecurityQuestionAnswerField(
                                    question: question.localizedQuestion(localizationManager: localizationManager),
                                    answer: $answers[index]
                                )
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Error Message
                    if let error = authManager.authenticationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Verify Button
                    Button(action: verifyAnswers) {
                        HStack {
                            if isVerifying {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text(isVerifying ? localizationManager.localizedString(for: "securityQuestionsRecovery.verifying") : localizationManager.localizedString(for: "securityQuestionsRecovery.verifyAnswers"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canVerify ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canVerify || isVerifying)
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .navigationTitle(localizationManager.localizedString(for: "securityQuestionsRecovery.navigationTitle"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(localizationManager.localizedString(for: "securityQuestionsRecovery.cancel")) {
                        isPresented = false
                    }
                }
            }
        }
        .onAppear {
            loadSecurityQuestions()
        }
    }

    private var canVerify: Bool {
        !isVerifying && answers.count == securityQuestions.count && answers.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func loadSecurityQuestions() {
        if let questions = authManager.getSecurityQuestionsForRecovery() {
            securityQuestions = questions
            answers = Array(repeating: "", count: questions.count)
        }
    }

    private func verifyAnswers() {
        isVerifying = true

        let questionAnswers = securityQuestions.enumerated().map { index, question in
            (questionId: question.id, answer: answers[index])
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if authManager.recoverPasswordWithSecurityQuestions(questionAnswers) {
                isVerifying = false
                isPresented = false
                onSuccess()
            } else {
                isVerifying = false
            }
        }
    }
}

struct SecurityQuestionAnswerField: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    let question: String
    @Binding var answer: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(question)
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            TextField(localizationManager.localizedString(for: "securityQuestionsRecovery.answerPlaceholder"), text: $answer)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SecurityQuestionsRecoveryView(
        authManager: AuthenticationManager(),
        isPresented: Binding.constant(true),
        onSuccess: {}
    )
    .environmentObject(LocalizationManager.shared)
}