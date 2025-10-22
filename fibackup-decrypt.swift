//
//  fibackup-decrypt.swift
//  FamilyInvestmentTracker
//
//  Created by Kongkong on 2025/10/22.
//

import Foundation
import CryptoKit
import Compression

enum DecryptError: Error {
    case usage(String)
    case passwordMissing	
    case fileReadFailed
    case invalidFormat
    case unsupportedVersion
    case badPasswordOrCorrupt
}

struct BackupDecryptor {
    private let signature = Data("FIBACKUP".utf8)
    private let expectedVersion: UInt8 = 1
    private let hdrLengthSize = MemoryLayout<UInt32>.size
    private let hkdfInfo = Data("FamilyInvestmentBackup".utf8)

    func run() throws {
        let args = CommandLine.arguments
        guard args.count == 3 else {
            throw DecryptError.usage("Usage: fibackup-decrypt <input.fibackup> <output.json>")
        }

        let inputURL = URL(fileURLWithPath: args[1])
        let outputURL = URL(fileURLWithPath: args[2])

        print("Password: ", terminator: "")
        guard let password = readLine(), !password.isEmpty else {
            throw DecryptError.passwordMissing
        }

        let encrypted = try Data(contentsOf: inputURL)
        let jsonData = try decrypt(data: encrypted, password: password)
        try jsonData.write(to: outputURL, options: [.atomic])

        print("Decrypted JSON written to \(outputURL.path)")
    }

    private func decrypt(data: Data, password: String) throws -> Data {
        guard data.count > signature.count,
              data.prefix(signature.count) == signature else {
            throw DecryptError.invalidFormat
        }

        var offset = signature.count
        guard data.count > offset else { throw DecryptError.invalidFormat }
        let version = data[offset]
        offset += 1
        guard version == expectedVersion else { throw DecryptError.unsupportedVersion }

        guard data.count > offset else { throw DecryptError.invalidFormat }
        let saltLength = Int(data[offset])
        offset += 1

        guard data.count >= offset + saltLength + hdrLengthSize else { throw DecryptError.invalidFormat }
        let salt = data.subdata(in: offset ..< offset + saltLength)
        offset += saltLength

        let lengthData = data.subdata(in: offset ..< offset + hdrLengthSize)
        offset += hdrLengthSize
        let combinedLength = Int(UInt32(bigEndian: lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }))

        guard data.count >= offset + combinedLength else { throw DecryptError.invalidFormat }
        let combined = data.subdata(in: offset ..< offset + combinedLength)

        let key = deriveKey(password: password, salt: salt)

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combined)
            let decrypted = try AES.GCM.open(sealedBox, using: key)
            return try (decrypted as NSData).decompressed(using: .zlib) as Data
        } catch {
            throw DecryptError.badPasswordOrCorrupt
        }
    }

    private func deriveKey(password: String, salt: Data) -> SymmetricKey {
        let pwdKey = SymmetricKey(data: Data(password.utf8))
        return HKDF<SHA256>.deriveKey(
            inputKeyMaterial: pwdKey,
            salt: salt,
            info: hkdfInfo,
            outputByteCount: 32
        )
    }
}

do {
    try BackupDecryptor().run()
} catch DecryptError.usage(let text) {
    fputs("\(text)\n", stderr)
    exit(1)
} catch DecryptError.passwordMissing {
    fputs("Password is required.\n", stderr)
    exit(1)
} catch DecryptError.invalidFormat {
    fputs("Not a valid .fibackup file.\n", stderr)
    exit(1)
} catch DecryptError.unsupportedVersion {
    fputs("Backup version is newer than this tool understands.\n", stderr)
    exit(1)
} catch DecryptError.badPasswordOrCorrupt {
    fputs("Password incorrect or file is corrupted.\n", stderr)
    exit(1)
} catch {
    fputs("Failed: \(error)\n", stderr)
    exit(1)
}
