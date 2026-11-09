import MorningKit
import SwiftUI

/// Date, greeting, the model's one-line headline and the day at a glance.
struct HeroHeader: View {
    let briefing: Briefing
    var isToday: Bool

    var body: some View {
        let facts = briefing.facts
        let date = Briefing.date(forID: briefing.id) ?? briefing.generatedAt
        VStack(alignment: .leading, spacing: Spacing.s) {
            Text(Format.overline(date))
                .font(Typography.overline)
                .foregroundStyle(.tint)
                .tracking(1.2)

            Text(isToday ? Format.greeting() : "Briefing")
                .font(Typography.greeting)

            Text(headline)
                .font(Typography.headline)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: Metrics.readableTextWidth, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            HStack(spacing: Spacing.s) {
                Pill(text: Format.plural(facts.sessions.count, "session"), symbol: "sparkles", tint: Palette.claude)
                Pill(text: Format.plural(facts.commits.count, "commit"), symbol: "point.3.connected.trianglepath.dotted", tint: Palette.commit)
                if !facts.events.isEmpty {
                    Pill(text: Format.plural(facts.events.filter { !$0.isAllDay }.count, "event"), symbol: "calendar")
                }
                let urgent = facts.attention.filter { $0.severity == .high }.count
                if urgent > 0 {
                    Pill(text: "\(urgent) urgent", symbol: "exclamationmark.triangle.fill", tint: Palette.high)
                }
                Spacer(minLength: Spacing.s)
                Text(generatedLine)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.top, Spacing.xs)
        }
    }

    private var headline: String {
        switch briefing.content {
        case let .structured(generated): generated.headline
        case .markdown: "Claude's answer is shown as text below."
        }
    }

    private var generatedLine: String {
        let verb = briefing.trigger == .scheduled ? "Generated" : "Regenerated"
        let seconds = Double(briefing.durationMs) / 1000
        return "\(verb) \(Format.time(briefing.generatedAt)) · \(briefing.model) · \(String(format: "%.0f", seconds)) s"
    }
}

#Preview {
    HeroHeader(briefing: MockData.briefing(), isToday: true)
        .padding(Spacing.xxl)
        .frame(width: 900)
        .tint(AccentChoice.sunrise.color)
}
