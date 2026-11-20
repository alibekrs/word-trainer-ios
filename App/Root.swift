import SwiftUI
import UIKit

@main
struct WordTrainerApp: App {
    @State private var store = WordStore()
    @State private var progress = DayProgress()
    init() { Sound.ambient() }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(progress)
                .environment(Settings.shared)
                .environment(LessonPlayer.shared)
                .fontDesign(.rounded)
                .tint(.accentBlue)
        }
    }
}

struct RootView: View {
    @Environment(Settings.self) private var settings
    @Environment(DayProgress.self) private var progress
    @State private var tab = 0
    @State private var privacy = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Главная", systemImage: "house.fill", value: 0) { HomeView() }
            Tab("Слово дня", systemImage: "sun.max.fill", value: 1) { WordOfDayView() }
            Tab("Наборы", systemImage: "square.stack.3d.up.fill", value: 2) { SetsView() }
            Tab("Уроки", systemImage: "headphones", value: 3) { LessonsView() }
            Tab("Ещё", systemImage: "gearshape.fill", value: 4) { MoreView() }
        }
        .overlay { if privacy { PrivacyCover().transition(.opacity) } }
        // Only on real backgrounding: .inactive would flash the cover when Control Center opens.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if settings.hideInBackground { privacy = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            withAnimation(Motion.snappy) { privacy = false }
            progress.load()
        }
        .task { ThemeSwitcher.apply(settings.theme, from: nil) }
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            ScreenBackground()
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            Image(systemName: "lock.fill").font(.system(size: 44, weight: .semibold)).foregroundStyle(.secondary)
        }
    }
}

/// Big title + subtitle used at the top of each tab.
struct ScreenTitle: View {
    let title: String
    var subtitle: String? = nil
    var eyebrow: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let eyebrow { Text(eyebrow.uppercased()).font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(.secondary) }
            Text(title).font(.system(size: 34, weight: .black)).tracking(-0.5)
            if let subtitle { Text(subtitle).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}
