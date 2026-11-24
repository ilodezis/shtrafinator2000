/// Порт `difflib.SequenceMatcher(None, a, b).ratio()` — алгоритм Ратклиффа/Обершелпа,
/// чтобы нечёткое сопоставление названий давало те же оценки, что и раньше.
struct SequenceMatcher {
    private let a: [Unicode.Scalar]
    private let b: [Unicode.Scalar]
    private var b2j: [Unicode.Scalar: [Int]] = [:]

    init(_ a: String, _ b: String) {
        self.a = Array(a.unicodeScalars)
        self.b = Array(b.unicodeScalars)
        for (index, element) in self.b.enumerated() {
            b2j[element, default: []].append(index)
        }
        // autojunk: в длинных строках «популярные» символы исключаются из поиска, как в difflib.
        let n = self.b.count
        if n >= 200 {
            let threshold = n / 100 + 1
            b2j = b2j.filter { $0.value.count <= threshold }
        }
    }

    private func findLongestMatch(_ alo: Int, _ ahi: Int, _ blo: Int, _ bhi: Int) -> (i: Int, j: Int, size: Int) {
        var bestI = alo, bestJ = blo, bestSize = 0
        var j2len: [Int: Int] = [:]
        for i in alo..<ahi {
            var newJ2len: [Int: Int] = [:]
            for j in b2j[a[i]] ?? [] {
                if j < blo { continue }
                if j >= bhi { break }
                let k = (j2len[j - 1] ?? 0) + 1
                newJ2len[j] = k
                if k > bestSize {
                    bestI = i - k + 1
                    bestJ = j - k + 1
                    bestSize = k
                }
            }
            j2len = newJ2len
        }
        // Расширение совпадения на «популярные» символы (junk-набор пуст, isjunk=None).
        while bestI > alo, bestJ > blo, a[bestI - 1] == b[bestJ - 1] {
            bestI -= 1
            bestJ -= 1
            bestSize += 1
        }
        while bestI + bestSize < ahi, bestJ + bestSize < bhi, a[bestI + bestSize] == b[bestJ + bestSize] {
            bestSize += 1
        }
        return (bestI, bestJ, bestSize)
    }

    private func matchedCount() -> Int {
        var queue = [(0, a.count, 0, b.count)]
        var total = 0
        while let (alo, ahi, blo, bhi) = queue.popLast() {
            let (i, j, k) = findLongestMatch(alo, ahi, blo, bhi)
            guard k > 0 else { continue }
            total += k
            if alo < i, blo < j { queue.append((alo, i, blo, j)) }
            if i + k < ahi, j + k < bhi { queue.append((i + k, ahi, j + k, bhi)) }
        }
        return total
    }

    var ratio: Double {
        let length = a.count + b.count
        guard length > 0 else { return 1.0 }
        return 2.0 * Double(matchedCount()) / Double(length)
    }
}
