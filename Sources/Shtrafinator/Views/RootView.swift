import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            Sidebar(selection: $model.section)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            Group {
                switch model.section {
                case .notices: GeneratorView()
                case .scans: ScansView()
                }
            }
            .navigationTitle(model.section.title)
            .navigationSubtitle(model.section.subtitle)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.showsRules = true
                    } label: {
                        Label("Регламент и правила", systemImage: "questionmark.circle")
                    }
                    .help("Как программа обрабатывает реестр и сканы")
                }
            }
        }
        .sheet(isPresented: $model.showsRules) {
            RulesView()
        }
    }
}

private struct Sidebar: View {
    @Binding var selection: AppSection

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(get: { selection }, set: { if let value = $0 { selection = value } })) {
                Section("Инструменты") {
                    ForEach(AppSection.allCases) { section in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(section.title)
                                Text(section.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: section.symbol)
                        }
                        .padding(.vertical, 3)
                        .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()
            BrandFooter()
                .padding(12)
        }
    }
}

private struct BrandFooter: View {
    var body: some View {
        HStack(spacing: 10) {
            if let logo = AppResources.logo {
                Image(nsImage: logo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 28, height: 28)
            }
            HStack(spacing: 4) {
                Text("Штрафинатор")
                    .font(.callout.weight(.bold))
                Text("2000")
                    .font(.callout.weight(.bold).monospaced())
                    .foregroundStyle(Color.brand)
            }
            Spacer(minLength: 0)
        }
    }
}
