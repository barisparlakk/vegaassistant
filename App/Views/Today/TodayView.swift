import MorningKit
import SwiftUI

/// The Today screen: picks the right state, then lays out the briefing.
struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let generation = model.generation {
                GeneratingView(progress: generation)
                    .transition(.opacity)
            } else {
                switch model.today {
                case .loading:
                    SkeletonBriefing().transition(.opacity)
                case .empty:
                    if let error = model.lastError {
                        ErrorStateView(message: error, retry: model.regenerate)
                    } else {
                        EmptyStateView(action: model.regenerate)
                    }
                case let .loaded(briefing):
                    BriefingView(briefing: briefing, isToday: true)
                        .transition(.opacity)
                }
            }
        }
        .animation(Motion.spring, value: model.isGenerating)
        .navigationTitle("Today")
    }
}

/// A full briefing, used by Today and History.
struct BriefingView: View {
    @Environment(AppModel.self) private var model
    let briefing: Briefing
    var isToday: Bool

    @Namespace private var focusNamespace
    @State private var isFocusExpanded = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xxl) {
                    if isToday, let error = model.lastError {
                        ErrorBanner(message: error, retry: model.regenerate)
                            .reveal(0)
                    } else if isToday, model.isTodayStale {
                        StaleBanner(briefing: briefing, generate: model.regenerate)
                            .reveal(0)
                    }
                    HeroHeader(briefing: briefing, isToday: isToday)
                        .reveal(0)

                    if let generated = briefing.structured {
                        FocusCard(
                            briefing: briefing,
                            focus: generated.focus,
                            namespace: focusNamespace,
                            isExpanded: $isFocusExpanded
                        )
                        .reveal(1)
                        OvernightSection(facts: briefing.facts, summary: generated.section(.overnight))
                            .reveal(2)
                        AgendaSection(briefing: briefing, summary: generated.section(.agenda), isToday: isToday)
                            .reveal(3)
                        AttentionSection(facts: briefing.facts, section: generated.section(.attention))
                            .reveal(4)
                        if !generated.nextTasks.isEmpty {
                            NextTasksSection(tasks: generated.nextTasks, facts: briefing.facts)
                                .reveal(5)
                        }
                    } else {
                        FallbackBriefingView(briefing: briefing)
                            .reveal(1)
                    }
                    ProjectsGridSection(facts: briefing.facts)
                        .reveal(6)
                    SourcesFooter(briefing: briefing)
                        .reveal(7)
                }
                .padding(.horizontal, Spacing.xxl)
                .padding(.vertical, Spacing.xxl)
                .frame(maxWidth: Metrics.contentMaxWidth)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)
            .background(BriefingBackdrop())
            .blur(radius: isFocusExpanded ? Spacing.s : 0)
            .allowsHitTesting(!isFocusExpanded)

            if isFocusExpanded, let generated = briefing.structured {
                FocusDetailOverlay(
                    briefing: briefing,
                    focus: generated.focus,
                    namespace: focusNamespace,
                    isExpanded: $isFocusExpanded
                )
                .zIndex(1)
            }
        }
        .animation(Motion.spring, value: isFocusExpanded)
    }
}

/// Soft accent glow at the top of the canvas.
struct BriefingBackdrop: View {
    var body: some View {
        ZStack(alignment: .top) {
            Palette.canvas
            Rectangle()
                .fill(.tint.opacity(0.10))
                .frame(height: Metrics.backdropGlowHeight)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Entrance animation

private struct Reveal: ViewModifier {
    let index: Int
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : Spacing.m)
            .onAppear {
                withAnimation(Motion.stagger(index)) { isVisible = true }
            }
    }
}

extension View {
    /// Fades and lifts a section in, staggered by its position.
    func reveal(_ index: Int) -> some View { modifier(Reveal(index: index)) }
}

#Preview("Today") {
    TodayView()
        .environment(AppModel.preview())
        .tint(AccentChoice.sunrise.color)
        .frame(width: 980, height: 1400)
}

#Preview("Today — dark") {
    TodayView()
        .environment(AppModel.preview())
        .tint(AccentChoice.indigo.color)
        .frame(width: 980, height: 1400)
        .preferredColorScheme(.dark)
}
