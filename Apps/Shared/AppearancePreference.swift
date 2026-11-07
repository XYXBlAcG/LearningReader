import SwiftUI

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AppearancePicker: View {
    @AppStorage("appearance") private var appearance = AppearancePreference.system
    var body: some View {
        Picker("外观", selection: $appearance) {
            ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
        }
    }
}
