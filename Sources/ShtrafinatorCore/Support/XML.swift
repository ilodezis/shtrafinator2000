import Foundation
#if canImport(FoundationXML)
@_exported import FoundationXML
#endif

/// Пространства имён OOXML, с которыми работает программа.
enum OOXML {
    static let word = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    static let sheet = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    static let officeRelationships = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    static let packageRelationships = "http://schemas.openxmlformats.org/package/2006/relationships"
}

extension XMLNode {
    /// Локальное имя без префикса: `w:sdt` → `sdt`, `row` → `row`.
    var bareName: String {
        if let local = localName, !local.isEmpty { return local }
        guard let name else { return "" }
        if let colon = name.firstIndex(of: ":") { return String(name[name.index(after: colon)...]) }
        return name
    }
}

extension XMLElement {
    /// Непосредственные дочерние элементы (без текстовых узлов и комментариев).
    var childElements: [XMLElement] {
        (children ?? []).compactMap { $0 as? XMLElement }
    }

    func childElements(named local: String) -> [XMLElement] {
        childElements.filter { $0.bareName == local }
    }

    func firstChild(named local: String) -> XMLElement? {
        childElements.first { $0.bareName == local }
    }

    /// Все потомки в порядке обхода документа (pre-order), как `lxml.iter()`.
    func descendants(named local: String) -> [XMLElement] {
        var result: [XMLElement] = []
        func walk(_ element: XMLElement) {
            for child in element.childElements {
                if child.bareName == local { result.append(child) }
                walk(child)
            }
        }
        walk(self)
        return result
    }

    /// Значение атрибута по локальному имени, независимо от префикса.
    func attributeValue(_ local: String) -> String? {
        for attr in attributes ?? [] where attr.bareName == local {
            return attr.stringValue
        }
        return nil
    }

    /// Весь текст элемента и его потомков, как `"".join(el.itertext())`.
    var allText: String { stringValue ?? "" }

    func setWordAttribute(_ local: String, _ value: String) {
        if let existing = (attributes ?? []).first(where: { $0.bareName == local }) {
            existing.stringValue = value
            return
        }
        addAttribute(Self.wordAttribute(local, value))
    }

    static func wordElement(_ local: String) -> XMLElement {
        XMLElement(name: "w:\(local)", uri: OOXML.word)
    }

    static func wordAttribute(_ local: String, _ value: String) -> XMLNode {
        // swiftlint:disable:next force_cast
        XMLNode.attribute(withName: "w:\(local)", uri: OOXML.word, stringValue: value) as! XMLNode
    }

    /// Индекс узла среди всех детей родителя (включая текстовые), для вставки/удаления.
    var indexInParent: Int? {
        guard let parent = parent else { return nil }
        return (parent.children ?? []).firstIndex { $0 === self }
    }
}

extension XMLDocument {
    static func parseOOXML(_ data: Data) throws -> XMLDocument {
        try XMLDocument(data: data, options: [.nodePreserveWhitespace])
    }

    /// Заменитель пробела для текстовых узлов из одних пробелов. Foundation на macOS выбрасывает
    /// такие узлы при разборе (даже с `.nodePreserveWhitespace`), и в Word слипались слова:
    /// `<w:t xml:space="preserve"> </w:t>` превращался в пустой run.
    static let spaceSentinel: Character = "\u{E000}"

    /// Разбор документа Word с сохранением пробельных текстовых узлов; парный метод — `ooxmlDataRestoringSpaces()`.
    static func parseOOXMLPreservingSpaces(_ data: Data) throws -> XMLDocument {
        guard let text = String(data: data, encoding: .utf8) else { return try parseOOXML(data) }
        var protected = ""
        protected.reserveCapacity(text.utf8.count)
        var rest = Substring(text)
        // Простой проход вместо regex с заменой: длина пробельной серии сохраняется точно.
        while let open = rest.firstIndex(of: ">") {
            protected += rest[...open]
            rest = rest[rest.index(after: open)...]
            let spaces = rest.prefix { $0 == " " }
            if !spaces.isEmpty, rest.dropFirst(spaces.count).first == "<" {
                protected += String(repeating: spaceSentinel, count: spaces.count)
                rest = rest.dropFirst(spaces.count)
            }
        }
        protected += rest
        return try parseOOXML(Data(protected.utf8))
    }

    func ooxmlDataRestoringSpaces() -> Data {
        let data = ooxmlData()
        guard let text = String(data: data, encoding: .utf8) else { return data }
        return Data(text.replacingOccurrences(of: String(Self.spaceSentinel), with: " ").utf8)
    }

    func ooxmlData() -> Data {
        characterEncoding = "UTF-8"
        isStandalone = true
        return xmlData(options: [.nodeCompactEmptyElement])
    }
}
