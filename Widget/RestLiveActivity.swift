import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct AntremanWidgetBundle: WidgetBundle {
    var body: some Widget {
        RestLiveActivity()
        TestWidget()
    }
}

// MARK: - Teshis: sade ana ekran widget'i
// Bu gorunuyorsa widget eklentisi telefonda calisiyor demektir.
struct TestEntry: TimelineEntry { let date: Date }

struct TestProvider: TimelineProvider {
    func placeholder(in context: Context) -> TestEntry { TestEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (TestEntry) -> Void) { completion(TestEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TestEntry>) -> Void) {
        completion(Timeline(entries: [TestEntry(date: .now)], policy: .never))
    }
}

struct TestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AntremanTest", provider: TestProvider()) { entry in
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "dumbbell.fill").foregroundStyle(amber)
                Text("Widget çalışıyor").font(.headline).foregroundStyle(.white)
                Text(entry.date, style: .time).font(.caption).foregroundStyle(muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(card, for: .widget)
        }
        .configurationDisplayName("Antrenman test")
        .description("Widget eklentisinin çalıştığını gösterir.")
        .supportedFamilies([.systemSmall])
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
                CountdownText(context: context)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(amber)
                    .frame(width: 44, alignment: .leading)
            } compactTrailing: {
                BatteryProgress(context: context)
            } minimal: {
                CountdownText(context: context)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(amber)
                    .frame(width: 32)
            }
            .keylineTint(amber)
        }
    }
}

/// Kalan sure. Sistem kendisi sayar — uygulama calismasa da saniye saniye iner.
struct CountdownText: View {
    let context: ActivityViewContext<RestAttributes>

    var body: some View {
        if context.isStale {
            Image(systemName: "checkmark")
        } else {
            // showsHours: false — yoksa sistem "0:00:20" icin yer ayirip "0:..." diye kesiyor.
            Text(timerInterval: context.state.range, countsDown: true, showsHours: false)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// "Enerji sarji": dinlendikce pil kirmizidan yesile dolar.
/// Sistem sayaci (ProgressView timerInterval) maske olarak kullaniliyor — boylece
/// uygulama calismadan, pil harcamadan iOS kendisi doldurur.
struct BatteryProgress: View {
    let context: ActivityViewContext<RestAttributes>
    private let red = Color(red: 248 / 255, green: 113 / 255, blue: 113 / 255)
    private let green = Color(red: 74 / 255, green: 222 / 255, blue: 128 / 255)
    private let shell = Color(red: 86 / 255, green: 92 / 255, blue: 102 / 255)

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack {
                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                    .stroke(shell, lineWidth: 1.6)
                fill
                    .padding(3)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white.opacity(context.isStale ? 0 : 0.9))
            }
            .frame(width: 30, height: 15)
            RoundedRectangle(cornerRadius: 1.2)
                .fill(shell)
                .frame(width: 2.5, height: 6)
        }
    }

    @ViewBuilder private var fill: some View {
        let gradient = LinearGradient(colors: [red, amber, green], startPoint: .leading, endPoint: .trailing)
        if context.isStale {
            RoundedRectangle(cornerRadius: 2).fill(green)
        } else {
            gradient
                .mask(
                    ProgressView(timerInterval: context.state.range, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(.white)
                    .scaleEffect(x: 1, y: 3.2, anchor: .center)
                )
                .clipShape(RoundedRectangle(cornerRadius: 2))
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

    var body: some View {
        phoneView
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
