import SwiftUI

extension DemoMealKind {
  func color(dark: Bool) -> Color {
    // One shared chart palette keeps meal and macro colors consistent.
    // Light mode uses clean, luminous fills; labels retain semantic dark text.
    switch self {
    case .breakfast: return Color(hex: dark ? 0xE799A0 : 0xE96D88)
    case .lunch: return Color(hex: dark ? 0xDABD7A : 0xF0BD46)
    case .dinner: return Color(hex: dark ? 0x86C8AE : 0x56BFA0)
    case .snack: return Color(hex: dark ? 0x9AB7E3 : 0x72A9EC)
    }
  }
}
struct HomeEntrance: ViewModifier {
  let index: Int
  var reduced = false
  var token = ""
  @State private var progress = 0.0
  func body(content: Content) -> some View {
    content.opacity(progress).offset(y: reduced ? 0 : 9 * (1-progress))
      .modifier(HomeRevealWhenVisible(progress: $progress, token: "entrance|" + token,
        animation: .easeOut(duration: reduced ? 0.15 : 0.42),
        delay: .milliseconds(reduced ? 0 : 25 + min(max(index, 0), 6) * 45)))
  }
}
struct HomeIconButton: View {
  let symbol: String
  let label: String
  let action: () -> Void
  var body: some View {
    Button(action: action) { Image(systemName: symbol).font(.system(size: 14)).frame(width: 36, height: 36).contentShape(RoundedRectangle(cornerRadius: 9)) }
      .modifier(AppGlassButton(circle: true)).accessibilityLabel(label).help(label)
  }
}
struct HomeSectionHeading<Accessory: View>: View {
  let title: String
  let subtitle: String
  var help = ""
  @ViewBuilder var accessory: Accessory
  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .center, spacing: 16) {
        heading.fixedSize(horizontal: true, vertical: false)
        Spacer(minLength: 0)
        HStack(spacing: 14) { accessory }.fixedSize(horizontal: true, vertical: false)
      }
      VStack(alignment: .leading, spacing: 12) {
        heading
        HStack(spacing: 14) { Spacer(minLength: 0); accessory }
      }
    }
  }
  private var heading: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 7) {
        Text(title).font(.system(size: 20, weight: .medium)).tracking(-0.4)
        if !help.isEmpty { HomeHelpButton(title: title, message: help) }
      }
      if !subtitle.isEmpty { Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary) }
    }
  }
}
struct HomeRecordSheet: View {
  let record: HomeRecordDetail
  let palette: SetupPalette
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    VStack(alignment: .leading, spacing: 22) {
      HStack {
        VStack(alignment: .leading, spacing: 7) {
          Text(record.title).font(.system(size: 26, weight: .medium))
          Text(HomeFormat.date(record.date, pattern: "yyyy年M月d日") + "").font(.system(size: 12)).foregroundStyle(palette.secondary)
        }
        Spacer()
        HomeIconButton(symbol: "xmark", label: "关闭明细") { dismiss() }.keyboardShortcut(.cancelAction)
      }
      ScrollView {
        VStack(spacing: 0) {
          ForEach(record.rows) { row in
            HStack(alignment: .top, spacing: 24) {
              Text(row.title).foregroundStyle(palette.secondary).frame(maxWidth: .infinity, alignment: .leading)
              Text(row.value).multilineTextAlignment(.trailing).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .trailing)
            }.font(.system(size: 14)).padding(.vertical, 16)
            Divider().opacity(0.4)
          }
        }
      }
    }.padding(30).frame(width: 600, height: 470).environment(\.usesGlassControls, true).foregroundStyle(palette.foreground).background(palette.background)
  }
}

struct HomeAddButton: View {
  let label: String
  let palette: SetupPalette
  let action: () -> Void
  var body: some View {
    Button(action: action) { Image(systemName: "plus").font(.system(size: 14, weight: .medium)).frame(width: 36, height: 36) }
      .modifier(AppGlassButton(prominent: true, tint: .blue, circle: true)).accessibilityLabel(label).help(label)
  }
}
