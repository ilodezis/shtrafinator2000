import Foundation

/// Что удалось вытащить из текста скана.
public struct CompanyInfo: Equatable, Sendable {
    public enum Method: String, Sendable {
        case none, body, header, headerBeforeInn = "header_pre_inn", error
    }

    public var companyName = ""
    public var inn = ""
    public var ogrn = ""
    public var method: Method = .none
    public var confidence = 0.0
}

public enum CompanyRecognition {
    private static let legalForms = ["ООО", "ИП", "АО", "ПАО", "ЗАО"]

    private static let innPattern = Pattern(#"ИНН\D{0,4}(\d{10}|\d{12})"#, caseInsensitive: true)
    private static let ogrnPattern = Pattern(#"ОГРН(?:ИП)?\D{0,4}(\d{13}|\d{15})"#, caseInsensitive: true)
    private static let bodyPattern = Pattern(
        #"Между\s+([^\n\r\(]+?)\s*\(далее\s*[–—\-]?\s*[«"']?Предприяти"#, caseInsensitive: true
    )
    private static let trailingPunctuation = Pattern(#"[\s\.\,]+$"#)
    private static let legalLine = Pattern(#"^(?:(?:ООО|ИП|АО|ПАО|ЗАО)\s+[«"']?[А-ЯЁа-яёA-Za-z0-9\s\.\-–—]+[»"']?)"#)
    private static let requisites = Pattern("ОГРН|ИНН", caseInsensitive: true)

    /// Ключевые слова, по которым видно, что у PDF есть нормальный текстовый слой и OCR не нужен.
    static let textLayerKeywords = ["Между", "ИНН", "Предприятие", "Уведомление", "штраф", "ООО", "ИП"]

    /// Сам агрегатор (CloudPayments) в шапке письма — не контрагент.
    private static func isAggregator(_ name: String) -> Bool {
        let upper = name.uppercased()
        return upper.contains("КЛАУДПЭЙМЕНТС") || upper.contains("CLOUDPAYMENTS")
    }

    public static func hasUsableTextLayer(_ lines: [String]) -> Bool {
        let combined = lines.joined(separator: " ")
        return textLayerKeywords.contains { combined.contains($0) }
    }

    /// Название компании, ИНН и ОГРН из строк текста уведомления.
    public static func parse(_ lines: [String]) -> CompanyInfo {
        let fullText = lines.joined(separator: " ")
        var info = CompanyInfo()

        if let inn = innPattern.firstMatch(in: fullText)?[1] { info.inn = inn }
        if let ogrn = ogrnPattern.firstMatch(in: fullText)?[1] { info.ogrn = ogrn }

        // 1. Тело письма: «Между <КОМПАНИЯ> (далее – «Предприятие»)…»
        if let raw = bodyPattern.firstMatch(in: fullText)?[1] {
            let candidate = trailingPunctuation.replacingMatches(in: raw.trimmed, with: "")
            if candidate.count >= 3 {
                info.companyName = candidate
                info.method = .body
                let formal = (legalForms + ["Общество"]).contains { candidate.hasPrefix($0) }
                info.confidence = formal ? 0.95 : 0.85
                return info
            }
        }

        // 2. Строка шапки, начинающаяся с организационно-правовой формы.
        for line in lines {
            guard let candidate = legalLine.firstMatch(in: line.trimmed)?[0]?.trimmed else { continue }
            if !isAggregator(candidate) {
                info.companyName = candidate
                info.method = .header
                info.confidence = 0.80
                return info
            }
        }

        // 3. Строка прямо перед ОГРН/ИНН.
        for (index, line) in lines.enumerated() where index > 0 && requisites.matches(line) {
            let previous = lines[index - 1].trimmed
            if legalForms.contains(where: previous.hasPrefix) && !isAggregator(previous) {
                info.companyName = previous
                info.method = .headerBeforeInn
                info.confidence = 0.75
                return info
            }
        }
        return info
    }

    static func normalizeForMatch(_ name: String) -> String {
        var s = name.lowercased()
        for ch in "«»\"“”'`.,_-()" { s = s.replacingOccurrences(of: String(ch), with: " ") }
        return Pattern(#"\s+"#).replacingMatches(in: s, with: " ").trimmed
    }

    /// Лучший кандидат (имя готового .docx) для распознанного названия, если похожесть ≥ 0.75.
    public static func bestCandidate(for extracted: String, among candidates: [String]) -> String? {
        let normalized = normalizeForMatch(extracted)
        guard !normalized.isEmpty else { return nil }

        var best: String?
        var bestScore = 0.0
        for candidate in candidates {
            let normalizedCandidate = normalizeForMatch(candidate)
            if normalizedCandidate == normalized { return candidate }

            if normalized.scalarCount >= 5,
               normalizedCandidate.contains(normalized) || normalized.contains(normalizedCandidate) {
                let score = Double(normalized.scalarCount) / Double(max(normalizedCandidate.scalarCount, 1))
                if score > bestScore {
                    bestScore = score
                    best = candidate
                }
            }

            if !normalizedCandidate.isEmpty {
                let similarity = SequenceMatcher(normalized, normalizedCandidate).ratio
                if similarity > bestScore {
                    bestScore = similarity
                    best = candidate
                }
            }
        }
        return bestScore >= 0.75 ? best : nil
    }
}
