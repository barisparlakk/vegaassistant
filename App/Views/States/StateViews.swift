import MarkdownUI
import MorningKit
import SwiftUI

// MARK: - Empty

struct EmptyStateView: View {
    @Environment(AppModel.self) private var model
    let action: () -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            ZStack {
                Circle()
                    .fill(.tint.opacity(0.12))
                    .frame(width: Metrics.emptyStateIcon * 1.6, height: Metrics.emptyStateIcon * 1.6)
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: Metrics.emptyStateIcon * 0.6))
                    .foregroundStyle(.tint)
                    .symbolRenderingMode(.hierarchical)
            }
            VStack(spacing: Spacing.s) {
                Text("No briefing yet")
                    .font(Typography.greeting)
                Text("Morning reads last night's Claude sessions, commits, calendar and GitHub, then asks Claude what deserves your attention today.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: Metrics.readableTextWidth * 0.75)
            }
            Button(action: action) {
                Label("Generate today's briefing", systemImage: "sparkles")
                    .padding(.horizontal, Spacing.s)
            }
            .glassButtonStyle(prominent: true)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            Text("After this, a new briefing arrives every day at \(String(format: "%02d:%02d", model.settings.briefingHour, model.settings.briefingMinute)).")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BriefingBackdrop())
    }
}

// MARK: - Errors

struct ErrorStateView: View {
    @Environment(AppModel.self) private var model
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Spacing.l) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Metrics.emptyStateIcon * 0.6))
                .foregroundStyle(Palette.medium)
                .symbolRenderingMode(.hierarchical)
            Text("The briefing couldn't be generated")
                .font(Typography.greeting)
            Text(message)
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Metrics.readableTextWidth * 0.8)
                .textSelection(.enabled)
            HStack(spacing: Spacing.m) {
                Button("Try again", systemImage: "arrow.clockwise", action: retry)
                    .glassButtonStyle(prominent: true)
                Button("Open Settings", systemImage: "gearshape") { model.selection = .settings }
                    .glassButtonStyle()
            }
            .controlSize(.large)
        }
        .padding(Spacing.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BriefingBackdrop())
    }
}

/// Shown above an existing briefing when the latest regeneration failed.
struct ErrorBanner: View {
    @Environment(AppModel.self) private var model
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.medium)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Couldn't regenerate — showing the last briefing")
                    .font(Typography.bodyEmphasis)
                Text(message)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Retry", action: retry)
                .glassButtonStyle()
            Button {
                withAnimation(Motion.spring) { model.lastError = nil }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(Spacing.l)
        .cardSurface(fill: Palette.medium.opacity(0.1))
    }
}

/// Shown when the newest briefing is from an earlier day (e.g. the Mac was off at 07:00).
struct StaleBanner: View {
    let briefing: Briefing
    let generate: () -> Void

    var body: some View {
        let day = (Briefing.date(forID: briefing.id) ?? briefing.generatedAt).formatted(.dateTime.weekday(.wide))
        HStack(spacing: Spacing.m) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("This is \(day)'s briefing")
                    .font(Typography.bodyEmphasis)
                Text("Today's hasn't been generated yet.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button("Generate today's", systemImage: "sparkles", action: generate)
                .glassButtonStyle(prominent: true)
        }
        .padding(Spacing.l)
        .cardSurface(fill: Palette.surfaceRaised)
    }
}

// MARK: - Generating

/// Live progress over a shimmering skeleton of the briefing to come.
struct GeneratingView: View {
    let progress: GenerationProgress

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                GenerationProgressCard(progress: progress)
                SkeletonSections()
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: Metrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(BriefingBackdrop())
    }
}

struct GenerationProgressCard: View {
    let progress: GenerationProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            HStack(spacing: Spacing.m) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text("Preparing your briefing")
                        .font(Typography.cardTitle)
                    Text(progress.phase)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .contentTransition(.opacity)
                }
                Spacer()
                TimelineView(.periodic(from: progress.startedAt, by: 1)) { context in
                    Text("\(Int(context.date.timeIntervalSince(progress.startedAt))) s")
                        .font(Typography.numeric)
                        .foregroundStyle(Palette.textTertiary)
                        .contentTransition(.numericText())
                }
            }
            FlowLayout(spacing: Spacing.s) {
                ForEach(progress.steps) { step in
                    StepChip(step: step)
                }
            }
            ProgressView(value: progress.completedFraction)
                .progressViewStyle(.linear)
                .animation(Motion.spring, value: progress.completedFraction)
        }
        .padding(Spacing.xl)
        .glassSurface(in: RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
    }
}

struct StepChip: View {
    let step: GenerationProgress.Step

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Group {
                switch step.state {
                case .pending: Image(systemName: step.symbol).foregroundStyle(Palette.textTertiary)
                case .running:
                    Image(systemName: step.symbol)
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse, options: .repeating)
                case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.success)
                case .skipped: Image(systemName: "minus.circle").foregroundStyle(Palette.textTertiary)
                case .failed: Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.high)
                }
            }
            .frame(width: Metrics.iconSmall, height: Metrics.iconSmall)
            .transition(.scale.combined(with: .opacity))
            Text(step.title)
                .foregroundStyle(step.state == .pending ? Palette.textTertiary : Palette.textPrimary)
            if let detail = step.detail {
                Text(detail).foregroundStyle(Palette.textTertiary).monospacedDigit()
            }
        }
        .font(Typography.captionEmphasis)
        .padding(.horizontal, Spacing.s)
        .padding(.vertical, Spacing.xs)
        .background(Palette.surfaceSunken, in: Capsule())
        .animation(Motion.snappy, value: step.state)
    }
}

// MARK: - Skeleton

/// Placeholder shaped like the real briefing, shown while loading or generating.
struct SkeletonBriefing: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: Spacing.m) {
                    SkeletonLine(width: 160, height: Metrics.shimmerLine * 0.8)
                    SkeletonLine(width: 340, height: Metrics.shimmerLine * 2.4)
                    SkeletonLine(width: 520, height: Metrics.shimmerLine * 1.4)
                }
                .shimmering()
                SkeletonSections()
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: Metrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .background(BriefingBackdrop())
    }
}

struct SkeletonSections: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxl) {
            Card(padding: Spacing.xl, radius: Radius.xl) {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    HStack(spacing: Spacing.m) {
                        RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                            .fill(Palette.surfaceSunken)
                            .frame(width: Metrics.glyphLarge, height: Metrics.glyphLarge)
                        VStack(alignment: .leading, spacing: Spacing.s) {
                            SkeletonLine(width: 60, height: Metrics.shimmerLine * 0.7)
                            SkeletonLine(width: 180, height: Metrics.shimmerLine * 1.6)
                        }
                    }
                    SkeletonLine()
                    SkeletonLine(width: 420)
                    ForEach(0..<3, id: \.self) { _ in
                        HStack(spacing: Spacing.m) {
                            Circle().fill(Palette.surfaceSunken).frame(width: Metrics.checkbox, height: Metrics.checkbox)
                            SkeletonLine(width: 300)
                            Spacer()
                            SkeletonLine(width: 56)
                        }
                    }
                }
            }
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: Spacing.m) {
                    SkeletonLine(width: 120, height: Metrics.shimmerLine * 1.2)
                    Card {
                        VStack(alignment: .leading, spacing: Spacing.m) {
                            ForEach(0..<3, id: \.self) { index in
                                HStack(spacing: Spacing.m) {
                                    SkeletonLine(width: Metrics.timelineGutter)
                                    SkeletonLine(width: CGFloat(380 - index * 60))
                                }
                            }
                        }
                    }
                }
            }
        }
        .shimmering()
        .accessibilityLabel("Loading")
    }
}

// MARK: - Fallback

/// Claude's answer as Markdown, when it didn't validate as a structured briefing.
struct FallbackBriefingView: View {
    let briefing: Briefing

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.s) {
                Image(systemName: "doc.plaintext")
                    .foregroundStyle(Palette.medium)
                Text("Shown as text — Claude's answer didn't match the expected format after \(Format.plural(briefing.attempts, "attempt")).")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            Card(padding: Spacing.xl) {
                if case let .markdown(text) = briefing.content {
                    Markdown(text)
                        .markdownTheme(.gitHub.text { FontSize(13) })
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Previews

#Preview("Empty") {
    TodayView()
        .environment(AppModel.preview(.empty))
        .tint(AccentChoice.sunrise.color)
        .frame(width: 900, height: 640)
}

#Preview("Error") {
    TodayView()
        .environment({ let model = AppModel.preview(.empty); model.lastError = ClaudeError.notLoggedIn("OAuth session expired").errorDescription; return model }())
        .tint(AccentChoice.sunrise.color)
        .frame(width: 900, height: 640)
}

#Preview("Error banner") {
    TodayView()
        .environment(AppModel.preview(.failing))
        .tint(AccentChoice.sunrise.color)
        .frame(width: 900, height: 900)
}

#Preview("Generating") {
    GeneratingView(progress: .preview)
        .tint(AccentChoice.sunrise.color)
        .frame(width: 900, height: 900)
}

#Preview("Loading skeleton") {
    SkeletonBriefing()
        .frame(width: 900, height: 800)
}

#Preview("Fallback") {
    ScrollView {
        FallbackBriefingView(briefing: MockData.fallbackBriefing())
            .padding(Spacing.xxl)
    }
    .frame(width: 900, height: 800)
}
