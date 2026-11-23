import Foundation
import SwiftUI

enum PinKind: String, Codable, Sendable {
    case url
    case email
    case snippet

    static func detect(from rawValue: String) -> PinKind {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\n") else { return .snippet }

        // Email detection
        if trimmed.contains("@"),
           !trimmed.contains(" "),
           !trimmed.contains("/"),
           trimmed.split(separator: "@").count == 2,
           let domain = trimmed.split(separator: "@").last,
           domain.contains(".") {
            return .email
        }

        // URL detection
        let lower = trimmed.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return .url
        }
        if !trimmed.contains(" "),
           trimmed.contains("."),
           let firstPart = trimmed.split(separator: "/").first,
           firstPart.contains("."),
           let tld = firstPart.split(separator: ".").last,
           tld.count >= 2 && tld.count <= 10 && tld.allSatisfy({ $0.isLetter }) {
            return .url
        }

        return .snippet
    }
}

enum WhisperAccent: String, Codable, CaseIterable, Sendable, Identifiable {
    case sky
    case violet
    case emerald
    case amber
    case rose
    case slate

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .sky:     return Color(red: 0.22, green: 0.74, blue: 0.97)
        case .violet:  return Color(red: 0.65, green: 0.55, blue: 0.98)
        case .emerald: return Color(red: 0.20, green: 0.83, blue: 0.60)
        case .amber:   return Color(red: 0.98, green: 0.57, blue: 0.24)
        case .rose:    return Color(red: 0.96, green: 0.45, blue: 0.71)
        case .slate:   return Color(red: 0.58, green: 0.64, blue: 0.72)
        }
    }

    var label: String {
        rawValue.capitalized
    }

    static func defaultAccent(for kind: PinKind) -> WhisperAccent {
        switch kind {
        case .url:     return .sky
        case .email:   return .violet
        case .snippet: return .amber
        }
    }
}

struct PinItem: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var label: String
    var value: String
    var accent: WhisperAccent
    var createdAt: Date

    init(
        id: UUID = UUID(),
        label: String,
        value: String,
        accent: WhisperAccent? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = value
        let detected = PinKind.detect(from: value)
        self.accent = accent ?? WhisperAccent.defaultAccent(for: detected)
        self.createdAt = createdAt
    }

    var kind: PinKind {
        PinKind.detect(from: value)
    }

    var openableURL: URL? {
        guard kind == .url else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return URL(string: trimmed)
        }
        return URL(string: "https://\(trimmed)")
    }

    /// Clean single-line preview for the Whisper peek footer.
    var singleLinePreview: String {
        value
            .replacingOccurrences(of: "\r\n", with: " ↵ ")
            .replacingOccurrences(of: "\n", with: " ↵ ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
