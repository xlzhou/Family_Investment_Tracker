import SwiftUI

struct SecurityQuestionsSetupView: View {
    @ObservedObject var authManager: AuthenticationManager
    @Binding var isPresented: Bool
    let onComplete: () -> Void
    let isUpdating: Bool

    @EnvironmentObject private var localizationManager: LocalizationManager

    @State private var selectedQuestions: [String] = ["", ""]
    @State private var answers: [String] = ["", ""]
    @State private var isSettingUp = false
    @State private var showingSkipAlert = false

    private let requiredQuestions = 2

    init(authManager: AuthenticationManager, isPresented: Binding<Bool>, onComplete: @escaping () -> Void, isUpdating: Bool = false) {
        self.authManager = authManager
        self._isPresented = isPresented
        self.onComplete = onComplete
        self.isUpdating = isUpdating
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Header (Compact)
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(.blue)

                    Text(isUpdating ? "Update Security Questions" : "Security Questions")
                        .font(.title3)
                        .fontWeight(.bold)

                    Text(isUpdating ?
                         "Update your security questions. These will replace your current questions." :
                         "Set up security questions to help recover your passcode if you forget it")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }

                // Progress Indicator (Compact)
                HStack {
                    Text("Progress: \(completedQuestions) of \(requiredQuestions)")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    // Progress Bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .frame(width: geometry.size.width, height: 3)
                                .opacity(0.3)
                                .foregroundColor(.gray)

                            Rectangle()
                                .frame(width: min(CGFloat(completedQuestions) / CGFloat(requiredQuestions) * geometry.size.width, geometry.size.width), height: 3)
                                .foregroundColor(.blue)
                                .animation(.easeInOut(duration: 0.3), value: completedQuestions)
                        }
                        .cornerRadius(1.5)
                    }
                    .frame(height: 3)
                }
                .padding(.horizontal)

                // Scrollable Questions Area (Expanded)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(0..<requiredQuestions, id: \.self) { index in
                                SecurityQuestionSetupField(
                                    questionNumber: index + 1,
                                    selectedQuestion: $selectedQuestions[index],
                                    answer: $answers[index],
                                    isCompleted: isQuestionCompleted(index),
                                    localizationManager: localizationManager
                                )
                                .id("question_\(index)")
                            }

                            // Add some bottom padding to ensure the last question is fully visible
                            Spacer()
                                .frame(height: 40)
                        }
                    }
                    .padding(.horizontal)
                    .onReceive(NotificationCenter.default.publisher(for: .scrollToNextQuestion)) { notification in
                        if let currentQuestion = notification.object as? Int {
                            let nextQuestionIndex = currentQuestion // currentQuestion is already 1-based, next is 0-based
                            withAnimation(.easeInOut(duration: 0.6)) {
                                proxy.scrollTo("question_\(nextQuestionIndex)", anchor: .top)
                            }
                        }
                    }
                }

                // Error Message
                if let error = authManager.authenticationError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(spacing: 12) {
                    // Setup Button
                    Button(action: setupSecurityQuestions) {
                        HStack {
                            if isSettingUp {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text(isSettingUp ?
                                 (isUpdating ? "Updating..." : "Setting up...") :
                                 (isUpdating ? "Update Security Questions" : "Set Up Security Questions"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(canSetup ? Color.blue : Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(!canSetup || isSettingUp)

                    // Skip Button (only show during initial setup)
                    if !isUpdating {
                        Button("Skip for Now") {
                            showingSkipAlert = true
                        }
                        .font(.body)
                        .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle(isUpdating ? "Update Questions" : "Security Setup")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
            }
        }
        .alert("Skip Security Questions?", isPresented: $showingSkipAlert) {
            Button("Skip", role: .destructive) {
                isPresented = false
                onComplete()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You won't be able to recover your passcode if you forget it. You can set up security questions later in Settings.")
        }
    }

    private var canSetup: Bool {
        !isSettingUp &&
        selectedQuestions.allSatisfy { !$0.isEmpty } &&
        answers.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } &&
        Set(selectedQuestions).count == selectedQuestions.count // No duplicate questions
    }

    private var completedQuestions: Int {
        var count = 0
        for index in 0..<requiredQuestions {
            if isQuestionCompleted(index) {
                count += 1
            }
        }
        return count
    }

    private func isQuestionCompleted(_ index: Int) -> Bool {
        return !selectedQuestions[index].isEmpty &&
               !answers[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func setupSecurityQuestions() {
        isSettingUp = true

        // Convert localized questions to localization keys before storing
        let questionsAndAnswers = zip(selectedQuestions, answers).compactMap { (localizedQuestion, answer) -> (question: String, answer: String)? in
            if let key = SecurityQuestionManager.getLocalizationKey(for: localizedQuestion, localizationManager: localizationManager) {
                return (question: key, answer: answer)
            }
            return nil
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if authManager.securityQuestionManager.setupSecurityQuestions(questionsAndAnswers) {
                isSettingUp = false
                isPresented = false
                onComplete()
            } else {
                isSettingUp = false
                authManager.authenticationError = "Failed to set up security questions"
            }
        }
    }

}

struct SecurityQuestionSetupField: View {
    let questionNumber: Int
    @Binding var selectedQuestion: String
    @Binding var answer: String
    let isCompleted: Bool
    let localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Security Question \(questionNumber)")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                if isCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.title3)
                }
            }

            // Question Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Question")
                    .font(.body)
                    .fontWeight(.medium)

                Menu {
                    ForEach(SecurityQuestionManager.getLocalizedQuestions(localizationManager: localizationManager), id: \.self) { question in
                        Button(question) {
                            selectedQuestion = question
                        }
                    }
                } label: {
                    HStack {
                        Text(selectedQuestion.isEmpty ? "Select a question..." : selectedQuestion)
                            .foregroundColor(selectedQuestion.isEmpty ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }

            // Answer Field
            VStack(alignment: .leading, spacing: 8) {
                Text("Answer")
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    TextField("Your answer", text: $answer)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)

                    // Next Question Arrow (only show when this question is completed but not the last one)
                    if isCompleted && questionNumber < 2 {
                        Button(action: {
                            // Post notification to scroll to next question
                            NotificationCenter.default.post(name: .scrollToNextQuestion, object: questionNumber)
                        }) {
                            VStack(spacing: 2) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                Text("Next")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundColor(.blue)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .animation(.easeInOut(duration: 0.3), value: isCompleted)
                    }
                }

                Text("Remember: answers are case-insensitive")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(isCompleted ? Color.green.opacity(0.1) : Color(.systemGray6).opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isCompleted ? Color.green : Color.clear, lineWidth: 2)
        )
        .cornerRadius(12)
    }
}

#Preview {
    SecurityQuestionsSetupView(
        authManager: AuthenticationManager(),
        isPresented: Binding.constant(true),
        onComplete: {},
        isUpdating: false
    )
    .environmentObject(LocalizationManager.shared)
}

// MARK: - Notification Extension
extension Notification.Name {
    static let scrollToNextQuestion = Notification.Name("scrollToNextQuestion")
}
