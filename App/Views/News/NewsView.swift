import SwiftUI

/// Placeholder until the news feed lands.
struct NewsView: View {
    var body: some View {
        VStack(alignment: .leading) {
            Panel("news.feed") {
                ConsoleMessage(text: "news arrives with the next briefing")
            }
            Spacer()
        }
        .padding(.horizontal, DS.Space.pageSide)
        .padding(.top, DS.Space.pageTop)
    }
}
