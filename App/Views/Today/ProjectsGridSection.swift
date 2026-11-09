import MorningKit
import SwiftUI

/// Cards for recently active projects, with a 14-day commit sparkline.
struct ProjectsGridSection: View {
    let facts: BriefingFacts
    @State private var showsAll = false

    var body: some View {
        let active = facts.activeProjects
        let shown = showsAll ? facts.projects : active
        VStack(alignment: .leading, spacing: Spacing.m) {
            SectionHeader(title: "Projects", symbol: "square.grid.2x2", subtitle: "active in the last 14 days") {
                if facts.projects.count > active.count {
                    Button(showsAll ? "Active only" : "Show all \(facts.projects.count)") {
                        withAnimation(Motion.spring) { showsAll.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .font(Typography.captionEmphasis)
                }
            }
            if shown.isEmpty {
                Card {
                    Text("No repositories found. Add folders in Settings › Sources.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Metrics.projectCardMinWidth), spacing: Spacing.m)], spacing: Spacing.m) {
                    ForEach(shown) { project in
                        ProjectCard(project: project, attentionCount: facts.attention.filter { $0.projectID == project.id }.count)
                    }
                }
            }
        }
    }
}

struct ProjectCard: View {
    let project: ProjectFact
    var attentionCount = 0
    var isSelected = false
    var showsMenu = true
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                ProjectGlyph(id: project.id, name: project.name)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(project.name)
                        .font(Typography.cardTitle)
                        .lineLimit(1)
                    Text(project.branch ?? (project.kind == .folder ? "folder" : "—"))
                        .font(Typography.mono)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if showsMenu {
                    ProjectOpenMenu(project: project)
                        .opacity(isHovered ? 1 : 0)
                }
            }

            if project.kind == .repo {
                Sparkline(values: project.commitsLast14Days.isEmpty ? Array(repeating: 0, count: 14) : project.commitsLast14Days)
            } else {
                Spacer().frame(height: Metrics.sparklineHeight)
            }

            HStack(spacing: Spacing.s) {
                Text(project.lastActivityAt.map { Format.relative($0) } ?? "no activity")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
                if project.isDirty {
                    Image(systemName: "circle.fill")
                        .font(.system(size: Metrics.timelineNode * 0.75))
                        .foregroundStyle(Palette.medium)
                        .help("\(project.changedFiles + project.untrackedFiles) uncommitted files")
                        .accessibilityLabel("\(project.changedFiles + project.untrackedFiles) uncommitted files")
                }
                if project.ahead > 0 {
                    Label("\(project.ahead)", systemImage: "arrow.up")
                        .font(Typography.captionEmphasis)
                        .foregroundStyle(Palette.medium)
                        .help("Unpushed commits")
                }
                if attentionCount > 0 {
                    Label("\(attentionCount)", systemImage: "exclamationmark.bubble")
                        .font(Typography.captionEmphasis)
                        .foregroundStyle(Palette.textSecondary)
                        .help("Attention items")
                }
            }
            .labelStyle(.titleAndIcon)
        }
        .padding(Spacing.l)
        .background {
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .fill(isHovered ? Palette.surfaceRaised : Palette.surface)
                .shadow(color: Palette.shadow, radius: isHovered ? Spacing.m : Spacing.s, y: isHovered ? Spacing.xs : Spacing.xxs)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.stroke), lineWidth: isSelected ? Metrics.rule : Metrics.hairline)
        }
        .scaleEffect(isHovered ? 1.01 : 1)
        .onHover { hovering in withAnimation(Motion.snappy) { isHovered = hovering } }
    }
}

/// Collector status and validator notes, at the bottom of every briefing.
struct SourcesFooter: View {
    let briefing: Briefing

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            Divider()
            FlowLayout(spacing: Spacing.s) {
                ForEach(briefing.diagnostics) { report in
                    Pill(
                        text: report.status == .ok ? "\(report.kind.shortName) · \(report.itemCount)" : "\(report.kind.shortName) · \(report.status.rawValue)",
                        symbol: report.status == .ok ? "checkmark" : (report.status == .skipped ? "minus" : "xmark"),
                        tint: report.status == .failed ? Palette.high : Palette.textSecondary
                    )
                    .help(report.message ?? "\(report.kind.displayName): \(report.durationMs) ms")
                }
            }
            if !briefing.repairs.isEmpty {
                Text("Adjusted: " + briefing.repairs.joined(separator: " "))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }
}

/// Wrapping horizontal layout for pills.
struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let extra = rows[rows.count - 1].indices.isEmpty ? size.width : size.width + spacing
            if rows[rows.count - 1].width + extra > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            let isFirst = rows[rows.count - 1].indices.isEmpty
            rows[rows.count - 1].indices.append(index)
            rows[rows.count - 1].width += isFirst ? size.width : size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}

#Preview("Projects grid") {
    ScrollView {
        ProjectsGridSection(facts: MockData.briefing().facts)
            .padding(Spacing.xxl)
    }
    .frame(width: 900, height: 600)
    .tint(AccentChoice.sunrise.color)
}

#Preview("Sources footer") {
    SourcesFooter(briefing: MockData.briefing())
        .padding(Spacing.xxl)
        .frame(width: 900)
}
