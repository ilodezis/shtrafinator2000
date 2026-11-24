import ShtrafinatorCore
import SwiftUI

struct GeneratorView: View {
    var body: some View {
        HStack(spacing: 0) {
            GeneratorSettingsPane()
                .frame(width: 400)
            Divider()
            GeneratorResultsPane()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Настройки

private struct GeneratorSettingsPane: View {
    @Environment(GeneratorModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    registrySection
                    outputSection
                    letterSection(model: model)
                }
                .padding(20)
            }

            Divider()
            generateBar
                .padding(16)
                .background(.bar)
        }
    }

    private var registrySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepHeader(number: 1, title: "Реестр штрафов") {
                if model.isInspecting {
                    ProgressView().controlSize(.small)
                } else if model.registryURL != nil {
                    Button("Перечитать") { model.inspect() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            DropZone(
                symbol: "tablecells",
                title: "Перетащите .xlsx сюда",
                subtitle: "или нажмите, чтобы выбрать файл",
                selectedURL: model.registryURL,
                badge: "XLSX",
                onPick: model.chooseRegistry,
                onDrop: model.setRegistry
            )

            if let error = model.inspectionError {
                ErrorBanner(title: "Не удалось прочитать реестр", message: error)
            } else if let inspection = model.inspection {
                InspectionCard(inspection: inspection)
            }
        }
    }

    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            StepHeader(number: 2, title: "Папка для документов") {
                if model.registryURL != nil {
                    Button("Рядом с реестром") { model.useRegistryFolder() }
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }

            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(Color.brand)
                    .font(.title3)
                Text(model.outputDirectory.map(Finder.displayPath) ?? "Не выбрана")
                    .font(.callout)
                    .foregroundStyle(model.outputDirectory == nil ? .secondary : .primary)
                    .lineLimit(2)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Выбрать…", action: model.chooseOutputDirectory)
            }
            .padding(12)
            .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator.opacity(0.6)))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, url.hasDirectoryPath else { return false }
                model.outputDirectory = url
                return true
            }
        }
    }

    private func letterSection(model: GeneratorModel) -> some View {
        @Bindable var model = model

        return VStack(alignment: .leading, spacing: 12) {
            StepHeader(number: 3, title: "Реквизиты письма")

            VStack(alignment: .leading, spacing: 6) {
                Text("Дата уведомления")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    DatePicker("Дата уведомления", selection: $model.letterDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                    Spacer()
                    Button("Сегодня", action: model.setToday)
                        .controlSize(.small)
                    Button("Конец месяца", action: model.setEndOfMonth)
                        .controlSize(.small)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Подписант (уполномоченное лицо)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextField("Подписант", text: $model.signatory, prompt: Text("Например, Иванов И. И."))
                    .textFieldStyle(.roundedBorder)
                Text(model.signatory.trimmingCharacters(in: .whitespaces).isEmpty
                     ? "Если оставить пустым, в документе будет заглушка для ручного ввода."
                     : "Запомнится до следующего запуска.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var generateBar: some View {
        Button(action: model.generate) {
            HStack(spacing: 8) {
                if model.phase == .generating {
                    ProgressView().controlSize(.small)
                    Text("Генерация…")
                } else {
                    Image(systemName: "wand.and.stars")
                    if let count = model.inspection?.validRowsCount, count > 0 {
                        Text("Сгенерировать уведомления (\(count))")
                    } else {
                        Text("Сгенерировать уведомления")
                    }
                }
            }
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.canGenerate)
        .keyboardShortcut(.return, modifiers: .command)
        .help("⌘↩")
    }
}

private struct InspectionCard: View {
    let inspection: RegistryInspection
    @State private var showsSamples = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Реестр проверен", systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                    Spacer()
                    Text("Лист «\(inspection.sheetName)»")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    MetricTile(
                        title: "К генерации",
                        value: "\(inspection.validRowsCount)",
                        detail: "из \(inspection.totalRows)",
                        tint: inspection.validRowsCount > 0 ? .green : .orange
                    )
                    MetricTile(title: "Сумма удержаний", value: inspection.totalFineSum.rubles)
                }

                if inspection.validRowsCount == 0 {
                    Label("Нет строк с решением «да» — генерировать нечего.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                FlowChips(items: [
                    ("Обязательные поля", .success),
                    (inspection.hasDirector ? "Директор" : "Директор — заглушка", inspection.hasDirector ? .accent : .neutral),
                    (inspection.hasOgrn ? "ОГРН" : "ОГРН — заглушка", inspection.hasOgrn ? .accent : .neutral),
                    (inspection.hasEmail ? "Email" : "Email — заглушка", inspection.hasEmail ? .accent : .neutral),
                ])

                if !inspection.samples.isEmpty {
                    DisclosureGroup(isExpanded: $showsSamples) {
                        VStack(spacing: 0) {
                            ForEach(inspection.samples) { sample in
                                HStack {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(sample.companyName)
                                            .lineLimit(1)
                                        Text("ИНН \(sample.inn)")
                                            .font(.caption2.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(sample.fine.rubles)
                                        .font(.callout.weight(.semibold).monospacedDigit())
                                }
                                .padding(.vertical, 6)
                                if sample.id != inspection.samples.last?.id { Divider() }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Первые \(inspection.samples.count) контрагентов")
                            .font(.callout)
                    }
                }
            }
        }
    }
}

/// Плашки, переносящиеся на новую строку.
private struct FlowChips: View {
    let items: [(String, Chip.Style)]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) { ForEach(items.prefix(2), id: \.0) { chip($0) } }
                HStack(spacing: 6) { ForEach(items.dropFirst(2), id: \.0) { chip($0) } }
            }
        }
    }

    private var chips: some View {
        ForEach(items, id: \.0) { chip($0) }
    }

    private func chip(_ item: (String, Chip.Style)) -> some View {
        Chip(
            text: item.0,
            symbol: item.1 == .neutral ? "minus" : "checkmark",
            style: item.1
        )
    }
}

// MARK: - Результаты

private struct GeneratorResultsPane: View {
    @Environment(GeneratorModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    statusDot
                    Text(model.statusText)
                        .font(.headline)
                        .lineLimit(2)
                    Spacer()
                    if model.phase == .finished, let directory = model.outputDirectory {
                        Button {
                            Finder.open(directory)
                        } label: {
                            Label("Открыть папку", systemImage: "folder")
                        }
                    }
                }

                if model.phase == .generating || model.phase == .finished {
                    ProgressStrip(current: model.progress.current, total: model.progress.total)
                }

                if !model.results.isEmpty {
                    Picker("Фильтр", selection: $model.filter) {
                        ForEach(GeneratorModel.ResultFilter.allCases) { filter in
                            Text("\(filter.title) · \(model.count(for: filter))").tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .padding(20)

            Divider()

            if model.results.isEmpty {
                emptyState
            } else if model.filteredResults.isEmpty {
                ContentUnavailableView("Здесь пусто", systemImage: "line.3.horizontal.decrease.circle",
                                       description: Text("В этой категории нет документов."))
            } else {
                List(model.filteredResults) { result in
                    ResultRow(result: result)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        let color: Color = switch model.phase {
        case .generating: .brand
        case .finished: model.errorCount > 0 ? .orange : .green
        case .failed: .red
        case .idle: .secondary.opacity(0.5)
        }
        Circle().fill(color).frame(width: 9, height: 9)
    }

    @ViewBuilder
    private var emptyState: some View {
        if case .failed(let message) = model.phase {
            ContentUnavailableView {
                Label("Генерация не удалась", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
        } else if model.phase == .generating {
            ContentUnavailableView {
                ProgressView().controlSize(.large)
            } description: {
                Text("Заполняем шаблоны…")
            }
        } else {
            ContentUnavailableView {
                Label("Документов пока нет", systemImage: "doc.on.doc")
            } description: {
                Text("Выберите реестр, проверьте папку и реквизиты и нажмите «Сгенерировать». Готовые файлы Word появятся здесь.")
            }
        }
    }
}

private struct ResultRow: View {
    let result: GenerationResult
    @State private var isHovering = false

    private var symbol: (String, Color) {
        if !result.success { return ("xmark.circle.fill", .red) }
        if !result.warnings.isEmpty { return ("exclamationmark.triangle.fill", .orange) }
        return ("checkmark.circle.fill", .green)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol.0)
                .foregroundStyle(symbol.1)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.filename)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let error = result.error {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                if !result.warnings.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(result.warnings, id: \.self) { warning in
                            Chip(text: warning, style: .warning)
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            if result.success {
                Button("Открыть") { Finder.open(result.fileURL) }
                    .controlSize(.small)
                    .opacity(isHovering ? 1 : 0)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture(count: 2) { if result.success { Finder.open(result.fileURL) } }
        .contextMenu {
            if result.success {
                Button("Открыть в Word") { Finder.open(result.fileURL) }
                Button("Показать в Finder") { Finder.reveal([result.fileURL]) }
            }
        }
    }
}

extension GeneratorModel.ResultFilter {
    var title: String {
        switch self {
        case .all: return "Все"
        case .ready: return "Готово"
        case .warnings: return "С замечаниями"
        case .errors: return "Ошибки"
        }
    }
}
