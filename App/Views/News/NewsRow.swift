import MorningKit
import SwiftUI

/// `01  Title · summary · relevance ············ source · 5h`
struct NewsRow: View {
    let index: Int
    let item: NewsItem
    let isRead: Bool
    let isSaved: Bool
    let isSelected: Bool
    var compact = false
    /// Hide the source · age column (narrow places like the menu bar).
    var showsMeta = true
    let open: () -> Void
    @State private var isHovered = false
    @Environment(\.accent) private var accent

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Space.m) {
                Text(String(format: "%02d", index))
                    .font(DS.Font.index)
                    .foregroundStyle(DS.Color.dim)
                    .frame(width: DS.Size.indexColumn, alignment: .leading)
                VStack(alignment: .leading, spacing: DS.Space.xs) {
                    Text(item.title)
                        .font(DS.Font.newsTitle)
                        .foregroundStyle(isRead ? DS.Color.muted : DS.Color.heading)
                        .lineLimit(compact ? 1 : 2)
                    Text(item.summary)
                        .font(DS.Font.summary)
                        .foregroundStyle(DS.Color.muted)
                        .lineLimit(compact ? 1 : 3)
                    if let relevance = item.relevance {
                        Text("↳ \(relevance)")
                            .font(DS.Font.metaSmall)
                            .foregroundStyle(DS.Color.accentInk(accent))
                            .lineLimit(compact ? 1 : 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsMeta {
                VStack(alignment: .trailing, spacing: DS.Space.xs) {
                    Text(meta)
                        .font(DS.Font.metaSmall)
                        .foregroundStyle(DS.Color.dim)
                        .lineLimit(1)
                    if isSaved {
                        Text("SAVED").font(DS.Font.tag).foregroundStyle(DS.Color.accentInk(accent))
                    }
                }
                }
            }
            .padding(.horizontal, DS.Space.rowHorizontal)
            .padding(.vertical, compact ? DS.Space.rowVertical : DS.Space.m)
            .opacity(isRead ? 0.6 : 1)
            .rowBackground(selected: isSelected, hovered: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(DS.Motion.fast) { isHovered = hovering } }
        .accessibilityLabel(item.title)
        .accessibilityValue([isRead ? "read" : nil, isSaved ? "saved" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint("Opens in the browser")
    }

    private var meta: String {
        let age = item.publishedAt.map { NewsAge.short($0) }
        return [item.source, age].compactMap { $0 }.joined(separator: " · ")
    }
}

enum NewsAge {
    /// `45m`, `5h`, `2d`
    static func short(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<3600: return "\(max(1, Int(seconds / 60)))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        default: return "\(Int(seconds / 86_400))d"
        }
    }
}

#Preview("News rows") {
    let items = MockData.news().allItems
    Panel("news.feed") {
        ForEach(Array(items.prefix(4).enumerated()), id: \.element.id) { index, item in
            if index > 0 { RowDivider() }
            NewsRow(index: index + 1, item: item, isRead: index == 2, isSaved: index == 0, isSelected: index == 1) {}
        }
    }
    .padding(DS.Space.xxl)
    .frame(width: 1000)
    .background(ConsoleBackdrop())
    .preferredColorScheme(.dark)
}
