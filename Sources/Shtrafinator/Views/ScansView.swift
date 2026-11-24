import ShtrafinatorCore
import SwiftUI

struct ScansView: View {
    @Environment(ScansModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(20)
            Divider()
            content
            if !model.items.isEmpty {
                Divider()
                footer
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                DropZone(
                    symbol: "folder.badge.questionmark",
                    title: "Перетащите папку со сканами",
                    subtitle: "или нажмите, чтобы выбрать",
                    selectedURL: model.folder,
                    badge: "PDF",
                    onPick: model.chooseFolder,
                    onDrop: model.setFolder
                )

                VStack(alignment: .trailing, spacing: 8) {
                    Button(action: model.analyze) {
                        Label(model.items.isEmpty ? "Распознать" : "Распознать заново", systemImage: "text.viewfinder")
                            .frame(minWidth: 150)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.folder == nil || model.phase != .idle)

                    if model.suggestedScansFolder != nil {
                        Button("Подпапка «сканы»", action: model.useSuggestedFolder)
                            .buttonStyle(.link)
                            .font(.caption)
                            .help("Папка «сканы» внутри папки с уведомлениями")
                    }
                }
            }

            if model.phase == .analyzing {
                ProgressStrip(
                    current: model.progress.current,
                    total: model.progress.total,
                    caption: model.progress.filename.isEmpty ? "Поиск PDF…" : "Распознавание: \(model.progress.filename)"
                )
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                    Text("Название компании ищется в абзаце «Между …» или в шапке письма и сверяется с файлами Word рядом. Всё обрабатывается на этом Mac.")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.items.isEmpty {
            if model.phase == .analyzing {
                ContentUnavailableView {
                    ProgressView().controlSize(.large)
                } description: {
                    Text("Распознаём сканы…")
                }
            } else {
                ContentUnavailableView {
                    Label(model.folder == nil ? "Папка не выбрана" : "Сканов нет", systemImage: "doc.viewfinder")
                } description: {
                    Text(model.folder == nil
                         ? "Выберите папку, куда принтер или почта сохранили отсканированные уведомления."
                         : model.statusText)
                }
            }
        } else {
            ScanTable()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Chip(text: "Распознано: \(model.recognizedCount)", symbol: "checkmark", style: .success)
            if model.manualCount > 0 {
                Chip(text: "Вручную: \(model.manualCount)", symbol: "hand.raised", style: .warning)
            }
            if let last = model.lastRename {
                Text(last.failed == 0 ? "Переименовано: \(last.renamed)" : "Переименовано: \(last.renamed), ошибок: \(last.failed)")
                    .font(.callout)
                    .foregroundStyle(last.failed == 0 ? Color.green : Color.orange)
            }
            Spacer()
            if let folder = model.folder {
                Button {
                    Finder.open(folder)
                } label: {
                    Label("Открыть папку", systemImage: "folder")
                }
            }
            Button(action: model.applyRenames) {
                if model.phase == .renaming {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Переименовать (\(model.pendingRenames))", systemImage: "arrow.right.doc.on.clipboard")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.pendingRenames == 0 || model.phase != .idle)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }
}

private struct ScanTable: View {
    @Environment(ScansModel.self) private var model
    @State private var selection = Set<ScanItem.ID>()

    var body: some View {
        Table(model.items, selection: $selection) {
            TableColumn("Скан") { item in
                Text(item.originalName)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(item.fileURL.path)
            }
            .width(min: 140, ideal: 200)

            TableColumn("Контрагент") { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.companyName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if item.inn != "—" {
                        Text("ИНН \(item.inn)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 160, ideal: 240)

            TableColumn("Новое имя") { item in
                VStack(alignment: .leading, spacing: 2) {
                    TextField(
                        "Имя файла",
                        text: Binding(
                            get: { model.proposedName(for: item.id) },
                            set: { model.setProposedName($0, for: item.id) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.callout)
                    if let error = model.renameErrors[item.id] {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .width(min: 200, ideal: 320)

            TableColumn("Статус") { item in
                StatusChip(item: item)
            }
            .width(min: 110, ideal: 130)
        }
        .contextMenu(forSelectionType: ScanItem.ID.self) { ids in
            let urls = model.items.filter { ids.contains($0.id) }.map(\.fileURL)
            Button("Открыть") { urls.forEach(Finder.open) }
            Button("Показать в Finder") { Finder.reveal(urls) }
        } primaryAction: { ids in
            model.items.filter { ids.contains($0.id) }.map(\.fileURL).forEach(Finder.open)
        }
    }
}

private struct StatusChip: View {
    let item: ScanItem

    var body: some View {
        switch item.status {
        case .matched:
            Chip(text: "Распознано", symbol: "checkmark", style: .success)
                .help("Способ: \(item.method.title), уверенность \(Int((item.confidence * 100).rounded()))%")
        case .unrecognized:
            Chip(text: "Вручную", symbol: "hand.raised", style: .warning)
                .help("Название не найдено — введите имя файла вручную")
        case .error:
            Chip(text: "Ошибка", symbol: "xmark", style: .danger)
                .help(item.error ?? "Не удалось прочитать файл")
        }
    }
}

extension CompanyInfo.Method {
    var title: String {
        switch self {
        case .body: return "абзац «Между …»"
        case .header: return "шапка письма"
        case .headerBeforeInn: return "строка перед ИНН/ОГРН"
        case .none: return "не найдено"
        case .error: return "ошибка"
        }
    }
}
