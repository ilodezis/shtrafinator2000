import SwiftUI

/// Заголовок шага: номер в кружке, название и необязательное действие справа.
struct StepHeader<Accessory: View>: View {
    let number: Int
    let title: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(spacing: 8) {
            Text("\(number)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.brand))
            Text(title)
                .font(.headline)
            Spacer(minLength: 8)
            accessory
        }
    }
}

extension StepHeader where Accessory == EmptyView {
    init(number: Int, title: String) {
        self.init(number: number, title: title) { EmptyView() }
    }
}

/// Карточка с мягким фоном и тонкой рамкой.
struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.separator.opacity(0.6))
            )
    }
}

/// Зона «перетащите сюда или нажмите»: принимает файлы/папки, подсвечивается при наведении.
struct DropZone: View {
    let symbol: String
    let title: String
    let subtitle: String
    var selectedURL: URL?
    var badge: String?
    let onPick: () -> Void
    let onDrop: (URL) -> Void

    @State private var isTargeted = false
    @State private var isHovering = false

    var body: some View {
        Button(action: onPick) {
            HStack(spacing: 12) {
                Image(systemName: selectedURL == nil ? symbol : "checkmark.circle.fill")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(selectedURL == nil ? Color.secondary : Color.green)
                    .frame(width: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedURL?.lastPathComponent ?? title)
                        .font(.body.weight(selectedURL == nil ? .regular : .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(selectedURL.map { Finder.displayPath($0.deletingLastPathComponent()) } ?? subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 4)
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold).monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isTargeted ? Color.brand.opacity(0.10) : Color.primary.opacity(isHovering ? 0.05 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isTargeted ? Color.brand : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: selectedURL == nil ? [5, 4] : [])
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            onDrop(url)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.easeOut(duration: 0.15), value: isTargeted)
    }
}

/// Плашка-метка: «✓ ОГРН», «Распознано» и т. п.
struct Chip: View {
    enum Style { case success, neutral, warning, danger, accent }

    let text: String
    var symbol: String?
    var style: Style = .neutral

    private var color: Color {
        switch style {
        case .success: return .green
        case .neutral: return .secondary
        case .warning: return .orange
        case .danger: return .red
        case .accent: return .brand
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .foregroundStyle(color)
        .background(color.opacity(0.12), in: Capsule())
    }
}

/// Крупная цифра с подписью.
struct MetricTile: View {
    let title: String
    let value: String
    var detail: String?
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .tracking(0.5)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

/// Сообщение об ошибке в карточке.
struct ErrorBanner: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.red.opacity(0.25)))
    }
}

/// Полоса прогресса с подписью «3 / 10 · 30%».
struct ProgressStrip: View {
    let current: Int
    let total: Int
    var caption: String?

    private var fraction: Double { total > 0 ? min(1, Double(current) / Double(total)) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .animation(.easeOut(duration: 0.2), value: fraction)
            HStack {
                if let caption {
                    Text(caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("\(current) / \(total) · \(Int((fraction * 100).rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
