import MorningKit
import SwiftUI

/// News settings: on/off, items per category, and the editable category list.
struct NewsSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingRow("enabled", detail: "One extra web-search run alongside each briefing (about a minute).") {
                Toggle("News enabled", isOn: Binding(
                    get: { model.settings.newsEnabled },
                    set: { value in model.updateSettings { $0.newsEnabled = value } }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            RowDivider()
            SettingRow("items per category") {
                Stepper(value: Binding(
                    get: { model.settings.newsItemsPerCategory },
                    set: { value in model.updateSettings { $0.newsItemsPerCategory = value } }
                ), in: 1...10) {
                    Text("\(model.settings.newsItemsPerCategory)")
                        .font(DS.Font.meta)
                        .foregroundStyle(DS.Color.text)
                }
            }
            RowDivider()
            ForEach(Array(model.settings.newsTopics.enumerated()), id: \.element.id) { index, topic in
                TopicEditor(index: index, topic: topic)
                RowDivider()
            }
            HStack(spacing: DS.Space.s) {
                Button("+ add category") {
                    model.updateSettings { settings in
                        let id = "topic-\(Int(Date.now.timeIntervalSince1970))"
                        settings.newsTopics.append(NewsTopic(id: id, label: "new", query: "What to look for"))
                    }
                }
                .buttonStyle(.consoleOutline)
                Button("reset to defaults") {
                    model.updateSettings { $0.newsTopics = NewsTopic.defaults }
                }
                .buttonStyle(.consoleGhost)
                Spacer()
            }
            .padding(.horizontal, DS.Space.rowHorizontal)
            .padding(.vertical, DS.Space.m)
        }
    }
}

/// One category: lowercase label + what to look for, with remove and reorder.
private struct TopicEditor: View {
    @Environment(AppModel.self) private var model
    let index: Int
    let topic: NewsTopic

    var body: some View {
        HStack(alignment: .top, spacing: DS.Space.m) {
            TextField("label", text: binding(\.label))
                .textFieldStyle(.plain)
                .font(DS.Font.meta)
                .foregroundStyle(DS.Color.heading)
                .frame(width: DS.Size.projectColumn)
            TextField("what to look for", text: binding(\.query), axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.Font.small)
                .foregroundStyle(DS.Color.muted)
                .lineLimit(1...3)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: DS.Space.xxs) {
                IconButton(symbol: "chevron.up", help: "Move up") { move(-1) }
                    .disabled(index == 0)
                IconButton(symbol: "chevron.down", help: "Move down") { move(1) }
                    .disabled(index == model.settings.newsTopics.count - 1)
                IconButton(symbol: "xmark", help: "Remove category") {
                    model.updateSettings { $0.newsTopics.removeAll { $0.id == topic.id } }
                }
            }
        }
        .padding(.horizontal, DS.Space.rowHorizontal)
        .padding(.vertical, DS.Space.rowVertical)
    }

    private func binding(_ keyPath: WritableKeyPath<NewsTopic, String>) -> Binding<String> {
        Binding {
            topic[keyPath: keyPath]
        } set: { value in
            model.updateSettings { settings in
                guard let position = settings.newsTopics.firstIndex(where: { $0.id == topic.id }) else { return }
                settings.newsTopics[position][keyPath: keyPath] = value
            }
        }
    }

    private func move(_ step: Int) {
        model.updateSettings { settings in
            guard let from = settings.newsTopics.firstIndex(where: { $0.id == topic.id }) else { return }
            let to = min(max(from + step, 0), settings.newsTopics.count - 1)
            settings.newsTopics.swapAt(from, to)
        }
    }
}

/// `label ········· control` with an optional dim explanation — the Settings row layout.
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder var control: Control

    init(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: DS.Space.l) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title)
                    .font(DS.Font.meta)
                    .foregroundStyle(DS.Color.text)
                if let detail {
                    Text(detail)
                        .font(DS.Font.small)
                        .foregroundStyle(DS.Color.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(minWidth: DS.Size.settingsLabelWidth, alignment: .leading)
            Spacer(minLength: DS.Space.l)
            control
        }
        .padding(.horizontal, DS.Space.rowHorizontal)
        .padding(.vertical, DS.Space.rowVertical + DS.Space.xxs)
    }
}

#Preview("News settings") {
    Panel("news") {
        NewsSettingsSection()
    }
    .padding(DS.Space.xxl)
    .frame(width: 900)
    .background(ConsoleBackdrop())
    .environment(AppModel.preview())
    .preferredColorScheme(.dark)
}
