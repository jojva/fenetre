import SwiftUI

/// The list of windows. Selection is driven entirely by the hotkey (the panel
/// never takes focus), so this view just reflects `model.selected`.
struct OverlayContentView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(Array(model.windows.enumerated()), id: \.element.id) { index, window in
                        RowView(window: window, isSelected: index == model.selected)
                    }
                }
                .padding(8)
            }
            .onChange(of: model.selected) { _, newValue in
                guard model.windows.indices.contains(newValue) else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(model.windows[newValue].id, anchor: .center)
                }
            }
        }
    }
}

/// One window row: app icon, then app name over window title.
struct RowView: View {
    let window: WindowInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(window.appName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .lineLimit(1)
                Text(window.title.isEmpty ? "Untitled" : window.title)
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var icon: some View {
        if let nsImage = window.icon {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 36, height: 36)
        } else {
            Image(systemName: "macwindow")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .frame(width: 36, height: 36)
                .foregroundStyle(.secondary)
        }
    }
}
