import Foundation

/// Заполнение шаблона уведомления данными одной строки реестра.
public struct NoticeTemplate: Sendable {
    let data: Data

    public init(data: Data) {
        self.data = data
    }

    public init(contentsOf url: URL) throws {
        guard let data = try? Data(contentsOf: url) else { throw ShtrafinatorError.templateUnavailable }
        self.data = data
    }

    static let placeholderSignatory = "[Подписант не указан]"
    static let placeholderDirector = "[Руководитель не указан]"

    /// Руководитель в дательном падеже и признак того, что его пришлось заменить заглушкой.
    public static func director(for record: NoticeRecord) -> (name: String, missing: Bool) {
        if let explicit = record.director?.trimmed, !explicit.isEmpty {
            return (RussianText.declineToDative(explicit), false)
        }
        let name = record.companyName.trimmed
        if name.uppercased().hasPrefix("ИП ") {
            return (RussianText.declineToDative(String(name.dropFirst(3)).trimmed), false)
        }
        return (placeholderDirector, true)
    }

    /// Отступ (в dxa) после последнего абзаца, чтобы прижать подпись к низу первой страницы,
    /// не вылезая на вторую: 2800 для короткого письма, минус 260 за каждую лишнюю строку, минимум 100.
    public static func signatureSpacing(for record: NoticeRecord) -> Int {
        let name = record.companyName
        let director = director(for: record).name
        let email = record.email ?? ""
        let fine = (try? RussianText.formatFine(record.fine ?? 0)) ?? ""

        func extra(_ text: String, offset: Int, per: Int) -> Int {
            max(0, Int((Double(text.scalarCount - offset) / Double(per)).rounded(.down)))
        }

        let headerExtra = extra(name, offset: 1, per: 25) + extra(director, offset: 1, per: 25) + extra(email, offset: 1, per: 25)
        let bodyExtra = extra(name, offset: 20, per: 70) + extra(fine, offset: 55, per: 70)
        return max(100, 2800 - (headerExtra + bodyExtra) * 260)
    }

    /// Готовый .docx и список замечаний (что пришлось заменить заглушками).
    public func fill(_ record: NoticeRecord, letterDate: CalendarDate, signatory: String = "") throws -> (data: Data, warnings: [String]) {
        var warnings: [String] = []

        let signatoryText: String
        if signatory.trimmed.isEmpty {
            signatoryText = Self.placeholderSignatory
            warnings.append("Подписант не указан")
        } else {
            signatoryText = signatory.trimmed
        }

        let (director, directorMissing) = Self.director(for: record)
        if directorMissing { warnings.append("Руководитель не указан") }

        let fraudText: String
        if let share = record.fraudShare {
            fraudText = RussianText.formatFraudShare(share)
        } else {
            fraudText = "[% не указан]"
            warnings.append("% фрода не указан")
        }

        let periodText: String
        if let period = record.period {
            periodText = RussianText.formatPeriod(period)
        } else {
            periodText = "[Период не указан]"
            warnings.append("Период не распознан")
        }

        guard let fineValue = record.fine else { throw ShtrafinatorError.fineMissing }
        let fineText = try RussianText.formatFine(fineValue)

        let ogrnText: String
        if let ogrn = record.ogrn, !ogrn.isEmpty {
            ogrnText = ogrn
        } else {
            ogrnText = "[ОГРН не указан]"
            warnings.append("ОГРН не указан")
        }

        let emailText: String
        if let email = record.email, !email.isEmpty {
            emailText = email
        } else {
            emailText = "[Email не указан]"
            warnings.append("Email не указан")
        }

        var package = try ZipPackage(data: data)
        guard let documentData = package["word/document.xml"] else { throw ShtrafinatorError.templateUnavailable }
        let document = try XMLDocument.parseOOXMLPreservingSpaces(documentData)
        guard let root = document.rootElement() else { throw ShtrafinatorError.templateUnavailable }

        let sdts = root.descendants(named: "sdt")
        if sdts.count != 12 {
            warnings.append("Ожидалось 12 SDT, найдено \(sdts.count) — результат может быть некорректным")
        }

        // Поля шаблона (content controls) в порядке документа:
        //  0 дата · 1 руководитель (абзац) · 2 название в шапке (абзац) · 3 ОГРН · 4 ИНН
        //  5 email (внешний, содержит 6) · 7 название в тексте · 8 % фрода · 9 период · 10 штраф · 11 подпись
        let replacements: [Int: (block: Bool, text: String, bold: Bool)] = [
            0: (false, RussianText.formatLetterDate(letterDate), false),
            1: (true, director, true),
            2: (true, record.companyName, true),
            3: (false, ogrnText, false),
            4: (false, record.inn, false),
            5: (false, emailText, false),
            7: (false, record.companyName, false),
            8: (false, fraudText, false),
            9: (false, periodText, false),
            10: (false, fineText, false),
            11: (false, " ____________/\(signatoryText)", false),
        ]

        // С конца, чтобы замена внешнего поля не мешала индексам остальных.
        for index in replacements.keys.sorted(by: >) where index < sdts.count {
            let (block, text, bold) = replacements[index]!
            let sdt = sdts[index]
            guard let parent = sdt.parent as? XMLElement, let position = sdt.indexInParent else { continue }
            let replacement = block ? Self.makeParagraph(text, bold: bold) : Self.makeRun(text, bold: bold)
            parent.insertChild(replacement, at: position)
            parent.removeChild(at: position + 1)
        }

        Self.applySignatureSpacing(root: root, spacing: Self.signatureSpacing(for: record))
        package["word/document.xml"] = document.ooxmlDataRestoringSpaces()

        if let settingsData = package["word/settings.xml"],
           let settings = try? XMLDocument.parseOOXMLPreservingSpaces(settingsData),
           let settingsRoot = settings.rootElement() {
            for protection in settingsRoot.childElements(named: "documentProtection") {
                if let position = protection.indexInParent { settingsRoot.removeChild(at: position) }
            }
            package["word/settings.xml"] = settings.ooxmlDataRestoringSpaces()
        }

        return (try package.serialized(), warnings)
    }

    // MARK: - XML-строители

    private static func runProperties(bold: Bool) -> XMLElement {
        let rPr = XMLElement.wordElement("rPr")
        let fonts = XMLElement.wordElement("rFonts")
        fonts.setWordAttribute("ascii", "Candara")
        fonts.setWordAttribute("hAnsi", "Candara")
        fonts.setWordAttribute("cs", "Times New Roman")
        rPr.addChild(fonts)
        if bold { rPr.addChild(XMLElement.wordElement("b")) }
        let size = XMLElement.wordElement("sz")
        size.setWordAttribute("val", "22")
        rPr.addChild(size)
        let sizeCs = XMLElement.wordElement("szCs")
        sizeCs.setWordAttribute("val", "22")
        rPr.addChild(sizeCs)
        return rPr
    }

    static func makeRun(_ text: String, bold: Bool) -> XMLElement {
        let run = XMLElement.wordElement("r")
        run.addChild(runProperties(bold: bold))
        let t = XMLElement.wordElement("t")
        t.stringValue = text
        if let first = text.first, let last = text.last, first == " " || last == " " {
            // swiftlint:disable:next force_cast
            t.addAttribute(XMLNode.attribute(withName: "xml:space", stringValue: "preserve") as! XMLNode)
        }
        run.addChild(t)
        return run
    }

    static func makeParagraph(_ text: String, bold: Bool) -> XMLElement {
        let paragraph = XMLElement.wordElement("p")
        let pPr = XMLElement.wordElement("pPr")
        pPr.addChild(runProperties(bold: bold))
        paragraph.addChild(pPr)
        paragraph.addChild(makeRun(text, bold: bold))
        return paragraph
    }

    /// Элементы `w:pPr`, которые по схеме идут после `w:spacing`.
    private static let afterSpacing: Set<String> = [
        "ind", "contextualSpacing", "mirrorIndents", "suppressOverlap", "jc", "textDirection",
        "textAlignment", "textboxTightWrap", "outlineLvl", "divId", "cnfStyle", "rPr", "sectPr", "pPrChange",
    ]

    /// Ставит `w:spacing w:after` абзацу перед таблицей подписи. В шаблоне `spacing` стоял
    /// после `rPr`, что нарушает порядок схемы, — здесь он переносится на правильное место.
    static func applySignatureSpacing(root: XMLElement, spacing: Int) {
        guard let body = root.firstChild(named: "body") else { return }
        let elements = body.childElements
        guard let signatureTable = elements.last(where: { $0.bareName == "tbl" }),
              let tableIndex = elements.firstIndex(where: { $0 === signatureTable }),
              tableIndex > 0
        else { return }
        let paragraph = elements[tableIndex - 1]
        guard paragraph.bareName == "p" else { return }

        let pPr: XMLElement
        if let existing = paragraph.firstChild(named: "pPr") {
            pPr = existing
        } else {
            pPr = XMLElement.wordElement("pPr")
            paragraph.insertChild(pPr, at: 0)
        }

        let spacingElement: XMLElement
        if let existing = pPr.firstChild(named: "spacing"), let position = existing.indexInParent {
            pPr.removeChild(at: position)
            spacingElement = existing
        } else {
            spacingElement = XMLElement.wordElement("spacing")
        }
        spacingElement.setWordAttribute("after", String(spacing))

        let children = pPr.children ?? []
        let insertAt = children.firstIndex { ($0 as? XMLElement).map { afterSpacing.contains($0.bareName) } ?? false }
            ?? children.count
        pPr.insertChild(spacingElement, at: insertAt)
    }
}
