import MorningKit
import SwiftUI

/// One thing Vega says (or said), with its card. Shared by Today and History.
struct VegaLineView: View {
    let line: VegaLine
    let briefing: Briefing
    /// History shows past days: nothing to check off or start.
    var isReadOnly = false
    /// Today's lines dim the words she hasn't said yet; past days never follow the voice.
    var followsVoice = true
    @Binding var cursor: ConsoleCursor?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.m + DS.Space.xxs) {
            VegaCaption(line: line, followsVoice: followsVoice)
            attachment
        }
    }

    @ViewBuilder private var attachment: some View {
        let generated = briefing.structured
        switch line.attachment {
        case .none:
            EmptyView()
        case .focusTasks:
            if let generated {
                PriorityPanel(briefing: briefing, focus: generated.focus, headline: generated.headline, isReadOnly: isReadOnly, cursor: $cursor)
            }
        case .overnight:
            OvernightCard(facts: briefing.facts, summary: generated?.section(.overnight), cursor: $cursor)
        case .decisions:
            DecisionsCard(facts: briefing.facts, section: generated?.section(.attention), cursor: $cursor)
        case .agenda:
            AgendaCard(facts: briefing.facts, cursor: $cursor)
        case .news:
            NewsCard(briefingID: briefing.id, cursor: $cursor)
        case .fallback:
            FallbackPanel(briefing: briefing)
        }
    }
}

/// A line of Vega's text; while she's saying it, the part still to come is dimmed.
struct VegaCaption: View {
    @Environment(AppModel.self) private var model
    let line: VegaLine
    var followsVoice = true

    var body: some View {
        Text(text)
            .font(line.isOpening ? DS.Font.vegaOpening : DS.Font.vegaLine)
            .tracking(line.isOpening ? -0.3 : -0.1)
            .lineSpacing(line.isOpening ? 2 : 4)
            .foregroundStyle(DS.Color.heading)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private var text: AttributedString {
        var text = AttributedString(line.text)
        let voice = model.voice
        guard followsVoice, voice.currentLineID == line.id else { return text }
        let ns = line.text as NSString
        let upcoming = ns.substring(from: min(max(voice.spokenLength, 0), ns.length))
        if !upcoming.isEmpty, let range = text.range(of: upcoming, options: .backwards) {
            text[range].foregroundColor = DS.Color.dim
        }
        return text
    }
}
