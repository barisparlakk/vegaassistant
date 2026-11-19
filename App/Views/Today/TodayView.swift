import MorningKit
import SwiftUI

/// Today: Vega talks you through the briefing (`ConversationView`).
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.isGenerating {
                ConversationWaiting()
            } else {
                switch model.today {
                case .loading:
                    ConversationWaiting()
                case .empty:
                    VStack(alignment: .leading, spacing: 0) {
                        if let error = model.lastError {
                            ConsoleMessage(text: "The last run failed: \(error)", actionTitle: "Try again", keys: "⌘R", tone: DS.Color.failed, action: model.regenerate)
                        } else {
                            ConsoleMessage(text: "No briefing for today yet.", actionTitle: "Regenerate", keys: "⌘R", action: model.regenerate)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, DS.Space.pageSide - DS.Space.rowHorizontal)
                    .padding(.top, DS.Space.pageTop)
                case let .loaded(briefing):
                    ConversationView(briefing: briefing)
                }
            }
        }
        .transition(.opacity)
        .animation(DS.Motion.standard, value: model.isGenerating)
    }
}

// MARK: - Cursor

/// One keyboard cursor across every selectable row on the page.
enum ConsoleCursor: Hashable {
    case task(String)
    case overnight(String)
    case agenda(String)
    case attention(Int)
    case news(String)
}


#Preview("Today") {
    TodayView()
        .environment(AppModel.preview())
        .environment(\.accent, DS.Color.defaultAccent)
        .tint(DS.Color.defaultAccent)
        .frame(width: 1100, height: 1500)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("Today — light") {
    TodayView()
        .environment(AppModel.preview())
        .environment(\.accent, DS.Color.defaultAccent)
        .tint(DS.Color.defaultAccent)
        .frame(width: 1100, height: 1500)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.light)
}

#Preview("Today — loading") {
    TodayView()
        .environment(AppModel.preview(generating: true))
        .frame(width: 1100, height: 900)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}

#Preview("Today — empty") {
    TodayView()
        .environment(AppModel.preview(.empty))
        .frame(width: 1100, height: 300)
        .background(ConsoleBackdrop())
        .preferredColorScheme(.dark)
}
