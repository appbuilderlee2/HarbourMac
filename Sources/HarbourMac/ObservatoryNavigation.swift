import SwiftUI

// Navigation only: command authorization remains in AppModel and the CLI bridge.
enum ObservatorySection: String, CaseIterable, Identifiable {
    case clean = "清理", software = "軟體", optimize = "最佳化", analyze = "分析", status = "狀態"
    var id: String { rawValue }
    var hotKey: KeyEquivalent {
        switch self { case .clean: return "1"; case .software: return "2"; case .optimize: return "3"; case .analyze: return "4"; case .status: return "5" }
    }
    var hotKeyLabel: String {
        switch self { case .clean: return "⌘1"; case .software: return "⌘2"; case .optimize: return "⌘3"; case .analyze: return "⌘4"; case .status: return "⌘5" }
    }
    var pages: [Page] {
        switch self {
        case .clean: return [.clean, .purge, .installer, .external]
        case .software: return [.uninstall, .updates, .login]
        case .optimize: return [.optimize]
        case .analyze: return [.disk]
        case .status: return [.status, .accessories, .fans]
        }
    }
    static func containing(_ page: Page) -> ObservatorySection? {
        allCases.first { $0.pages.contains(page) }
    }
}

struct ObservatoryNavigation: View {
    @ObservedObject var model: AppModel
    private var section: ObservatorySection? { ObservatorySection.containing(model.page ?? .clean) }
    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("HARBOUR").font(.caption.weight(.semibold)).tracking(2).frame(width: 100, alignment: .leading)
                Spacer(minLength: 12)
                HStack(spacing: 4) {
                    ForEach(ObservatorySection.allCases) { item in
                        Button { model.navigate(to: item) } label: {
                            Text(item.rawValue).font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .foregroundColor(section == item ? Color.black : Color.primary.opacity(0.65))
                                .background(Capsule().fill(section == item ? Color.white : Color.clear))
                        }.buttonStyle(.plain).accessibilityAddTraits(section == item ? .isSelected : [])
                            .keyboardShortcut(item.hotKey, modifiers: .command)
                            .help("\(item.rawValue)（\(item.hotKeyLabel)）")
                    }
                }.padding(5).background(Capsule().fill(Color.primary.opacity(0.07)))
                Spacer(minLength: 12)
                Menu {
                    ForEach([Page.history, .protection, .settings]) { page in
                        Button(page.rawValue) { model.navigate(to: page) }
                    }
                } label: { Image(systemName: "gearshape").accessibilityLabel("紀錄、保護清單與設定") }
                .menuStyle(BorderlessButtonMenuStyle()).frame(width: 100, alignment: .trailing)
            }
            if let section = section, section.pages.count > 1 {
                HStack(spacing: 6) {
                    ForEach(section.pages) { page in
                        Button { model.navigate(to: page) } label: {
                            Text(page.rawValue).font(.caption.weight(.medium))
                                .padding(.horizontal, 14).padding(.vertical, 7)
                                .background(Capsule().fill(model.page == page ? page.planetColor.opacity(0.22) : Color.clear))
                        }.buttonStyle(.plain).accessibilityAddTraits(model.page == page ? .isSelected : [])
                    }
                    Spacer()
                }
            }
        }.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 12)
            .disabled(!model.canNavigate)
    }
}

struct ObservatoryBackground: View {
    let page: Page
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LinearGradient(colors: [page.planetColor.opacity(scheme == .dark ? 0.19 : 0.07),
                                Color(nsColor: .windowBackgroundColor)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea().allowsHitTesting(false)
    }
}
