import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct AntremanWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
    }
}

private let amber = Color(red: 245 / 255, green: 166 / 255, blue: 35 / 255)
private let card = Color(red: 19 / 255, green: 20 / 255, blue: 23 / 255)
private let muted = Color(red: 139 / 255, green: 146 / 255, blue: 156 / 255)

struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestAttributes.self) { context in
            RestLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.labels.rest)
                    } icon: {
                        Image(systemName: "timer")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(amber)
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountdownText(context: context)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(context.isStale ? amber : .white)
                        .frame(maxWidth: 96, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.exercise)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.white)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 10) {
                        RestProgress(context: context)
                        RestButtons(context: context)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: "timer")
                    .foregroundStyle(amber)
            } compactTrailing: {
                CountdownText(context: context)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(amber)
                    .frame(maxWidth: 46)
            } minimal: {
                CountdownText(context: context)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(amber)
                    .frame(maxWidth: 34)
            }
            .keylineTint(amber)
        }
        .supplementalActivityFamilies([.small])
    }
}

/// Kalan sure. Sistem kendisi sayar — uygulama calismasa da saniye saniye iner.
struct CountdownText: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        if context.isStale {
            Image(systemName: "checkmark")
        } else {
            Text(timerInterval: context.state.range, countsDown: true, showsHours: false)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
    }
}

struct RestProgress: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        if context.isStale {
            Capsule().fill(amber).frame(height: 6)
        } else {
            ProgressView(timerInterval: context.state.range, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.linear)
            .tint(amber)
        }
    }
}

struct RestButtons: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        HStack(spacing: 10) {
            Button(intent: AddRestTimeIntent()) {
                Text(context.attributes.labels.add)
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(amber)
                    .background(Capsule().fill(amber.opacity(0.18)))
            }
            .buttonStyle(.plain)

            Button(intent: EndRestIntent()) {
                Text(context.attributes.labels.end)
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .foregroundStyle(.white)
                    .background(Capsule().fill(Color.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
        }
    }
}

struct RestLockScreenView: View {
    let context: ActivityViewContext<RestAttributes>
    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            watchView
        } else {
            phoneView
        }
    }

    /// Kilit ekrani / bildirim merkezi.
    private var phoneView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    Circle().fill(amber.opacity(0.18))
                    Image(systemName: context.isStale ? "checkmark" : "timer")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(amber)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.isStale ? context.attributes.labels.done : context.attributes.labels.rest)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(muted)
                    Text(context.state.exercise)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                CountdownText(context: context)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(context.isStale ? amber : .white)
                    .frame(maxWidth: 110, alignment: .trailing)
            }
            RestProgress(context: context)
            if !context.isStale {
                RestButtons(context: context)
            }
        }
        .padding(16)
    }

    /// Apple Watch Smart Stack (watchOS 11+): kucuk ve sade.
    private var watchView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(context.state.exercise)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(muted)
                .lineLimit(1)
            HStack {
                CountdownText(context: context)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(amber)
                Spacer(minLength: 0)
            }
            RestProgress(context: context)
        }
        .padding(8)
    }
}
