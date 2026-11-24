import SwiftUI

struct RulesView: View {
    @Environment(\.dismiss) private var dismiss

    private let rules: [(symbol: String, title: String, body: String)] = [
        ("line.3.horizontal.decrease.circle", "Отбор контрагентов",
         "Обрабатываются только строки листа «Для соп-я» (или листа, в названии которого есть «соп»), у которых в колонке «Решение» написано «да» в любом регистре. Остальные строки пропускаются."),
        ("tablecells", "Колонки реестра",
         "Обязательные: отчётный период, ИНН, ЮЛ, фрод в рублях, штраф, решение, % фрода. Директор, ОГРН и почта — необязательные: если их нет, в документ попадёт редактируемая заглушка."),
        ("textformat.abc", "Склонение имени руководителя",
         "Для ИП ФИО берётся из названия («ИП Иванов Иван Иванович»), для остальных — из колонки «Директор» («Руководитель», «Гендир», «ФИО»). Имя ставится в дательный падеж: «Иванову Ивану Ивановичу». Инициалы не склоняются."),
        ("rublesign.circle", "Сумма штрафа",
         "Сумма округляется до целых рублей и записывается цифрами и прописью. Текстовые значения вроде «30 000» тоже понимаются."),
        ("lock.open", "Свободное редактирование",
         "Из всех созданных документов Word снимается защита от редактирования — любые поля можно поправить вручную."),
        ("signature", "Подпись",
         "Внизу каждого документа ставится подпись указанного уполномоченного лица. Последнее введённое имя запоминается."),
        ("doc.viewfinder", "Переименование сканов",
         "Программа читает первую страницу каждого PDF (при необходимости через распознавание текста), находит компанию и предлагает имя по файлам Word рядом. Существующие файлы никогда не перезаписываются."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let logo = AppResources.logo {
                    Image(nsImage: logo)
                        .resizable()
                        .frame(width: 32, height: 32)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Регламент и правила")
                        .font(.title2.weight(.bold))
                    Text("Как Штрафинатор обрабатывает реестр и сканы")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)

            Divider()

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(rules, id: \.title) { rule in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: rule.symbol)
                                .font(.title2)
                                .foregroundStyle(Color.brand)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.title).font(.headline)
                                Text(rule.body)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(14)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()
                Button("Понятно") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 640)
    }
}
