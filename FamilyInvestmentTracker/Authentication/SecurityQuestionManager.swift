import Foundation
import Security
import CryptoKit

struct SecurityQuestion {
    let id: String
    let question: String
    let hashedAnswer: Data
    let salt: Data

    init(id: String, question: String, answer: String) {
        self.id = id
        self.question = question

        // Generate salt for this answer
        var salt = Data(count: 32)
        let result = salt.withUnsafeMutableBytes { mutableBytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, mutableBytes.bindMemory(to: UInt8.self).baseAddress!)
        }

        if result != errSecSuccess {
            // Fallback to UUID if SecRandomCopyBytes fails
            salt = UUID().uuidString.data(using: .utf8)!
        }

        self.salt = salt

        // Hash the answer with salt
        let answerData = answer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines).data(using: .utf8)!
        let combined = answerData + salt
        let digest = SHA256.hash(data: combined)
        self.hashedAnswer = Data(digest)
    }

    // Initialize from stored data
    init(id: String, question: String, hashedAnswer: Data, salt: Data) {
        self.id = id
        self.question = question
        self.hashedAnswer = hashedAnswer
        self.salt = salt
    }

    func verifyAnswer(_ answer: String) -> Bool {
        let normalizedAnswer = answer.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let answerData = normalizedAnswer.data(using: .utf8)!
        let combined = answerData + salt
        let digest = SHA256.hash(data: combined)
        return Data(digest) == hashedAnswer
    }
}

class SecurityQuestionManager: ObservableObject {
    private let service = "com.familyinvestmenttracker.keychain"
    private let questionsKey = "security_questions"
    private let questionsSetupKey = "security_questions_setup"

    // Predefined security questions
    static let availableQuestions = [
        "What was the name of your first pet?",
        "What is your mother's maiden name?",
        "What was the name of your first school?",
        "What city were you born in?",
        "What was the make of your first car?",
        "What is your favorite book?",
        "What was your childhood nickname?",
        "What street did you grow up on?",
        "What is your favorite food?",
        "What was the name of your best friend in high school?"
    ]

    init() {}

    // MARK: - Setup Security Questions

    func setupSecurityQuestions(_ questions: [(question: String, answer: String)]) -> Bool {
        guard questions.count >= 2 else { return false }

        var securityQuestions: [SecurityQuestion] = []

        for (index, questionData) in questions.enumerated() {
            let securityQuestion = SecurityQuestion(
                id: "question_\(index)",
                question: questionData.question,
                answer: questionData.answer
            )
            securityQuestions.append(securityQuestion)
        }

        if storeSecurityQuestions(securityQuestions) {
            markSecurityQuestionsSetup()
            return true
        }

        return false
    }

    // MARK: - Verification

    func verifySecurityQuestions(_ answers: [(questionId: String, answer: String)]) -> Bool {
        guard let storedQuestions = getSecurityQuestions() else { return false }

        // Need to answer at least 2 questions correctly
        var correctAnswers = 0

        for answerData in answers {
            if let question = storedQuestions.first(where: { $0.id == answerData.questionId }) {
                if question.verifyAnswer(answerData.answer) {
                    correctAnswers += 1
                }
            }
        }

        return correctAnswers >= 2
    }

    // MARK: - Retrieval

    func getSecurityQuestions() -> [SecurityQuestion]? {
        guard let data = retrieveFromKeychain(key: questionsKey) else { return nil }

        do {
            let decoder = JSONDecoder()
            let questionsData = try decoder.decode([SecurityQuestionData].self, from: data)

            return questionsData.map { questionData in
                SecurityQuestion(
                    id: questionData.id,
                    question: questionData.question,
                    hashedAnswer: questionData.hashedAnswer,
                    salt: questionData.salt
                )
            }
        } catch {
            print("🔒 Failed to decode security questions: \(error)")
            return nil
        }
    }

    func hasSecurityQuestionsSetup() -> Bool {
        return retrieveFromKeychain(key: questionsSetupKey) != nil
    }

    func removeSecurityQuestions() -> Bool {
        let questionsRemoved = deleteFromKeychain(key: questionsKey)
        let setupRemoved = deleteFromKeychain(key: questionsSetupKey)
        return questionsRemoved && setupRemoved
    }

    // MARK: - Private Methods

    private func storeSecurityQuestions(_ questions: [SecurityQuestion]) -> Bool {
        let questionsData = questions.map { question in
            SecurityQuestionData(
                id: question.id,
                question: question.question,
                hashedAnswer: question.hashedAnswer,
                salt: question.salt
            )
        }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(questionsData)
            return storeInKeychain(key: questionsKey, data: data)
        } catch {
            print("🔒 Failed to encode security questions: \(error)")
            return false
        }
    }

    private func markSecurityQuestionsSetup() {
        let setupData = "true".data(using: .utf8)!
        _ = storeInKeychain(key: questionsSetupKey, data: setupData)
    }

    // MARK: - Keychain Operations

    private func storeInKeychain(key: String, data: Data) -> Bool {
        _ = deleteFromKeychain(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    private func retrieveFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data {
            return data
        }

        return nil
    }

    private func deleteFromKeychain(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

// MARK: - Codable Data Structures

private struct SecurityQuestionData: Codable {
    let id: String
    let question: String
    let hashedAnswer: Data
    let salt: Data
}