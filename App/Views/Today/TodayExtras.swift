import MarkdownUI
import MorningKit
import SwiftUI



/// `sources: sessions 4 · git 18 · calendar —`
struct SourcesLine: View {
    let briefing: Briefing

    var body: some View {
        let parts = briefing.diagnostics.map { report in
            "\(report.kind.shortName.lowercased()) \(report.status == .ok ? "\(report.itemCount)" : (report.status == .failed ? "failed" : "—"))"
        }
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text("Sources: " + parts.joined(separator: " · "))
            if !briefing.repairs.isEmpty {
                Text("Adjusted: " + briefing.repairs.joined(separator: " "))
            }
            Text("\(briefing.model) · \(briefing.attempts) attempt\(briefing.attempts == 1 ? "" : "s") · \(Format.duration(ms: briefing.durationMs))")
        }
        .font(DS.Font.metaSmall)
        .foregroundStyle(DS.Color.dim)
        .textSelection(.enabled)
    }
}

/// Claude's answer as text, when it didn't validate.
struct FallbackPanel: View {
    let briefing: Briefing

    var body: some View {
        Panel("Briefing", counts: "Shown as text after \(Format.plural(briefing.attempts, "attempt"))") {
            if case let .markdown(text) = briefing.content {
                Markdown(text)
                    .markdownTheme(.gitHub.text {
                        FontSize(13)
                        ForegroundColor(DS.Color.text)
                        BackgroundColor(nil)
                    })
                    .textSelection(.enabled)
                    .padding(DS.Space.l)
            }
        }
    }
}


#Preview("Fallback") {
    FallbackPanel(briefing: MockData.fallbackBriefing())
        .padding(DS.Space.xxl)
        .frame(width: 1040)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}
