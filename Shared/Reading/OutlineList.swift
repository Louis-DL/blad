import SwiftUI

/// The headings of a page, to jump through a long note. Shown in a popover on the Mac
/// and in a sheet on iPhone.
struct OutlineList: View {
    let headings: [Heading]
    let onPick: (Heading) -> Void

    var body: some View {
        if headings.isEmpty {
            VStack(spacing: 6) {
                Text("Nog geen kopjes")
                    .font(.headline)
                Text("Begin een regel met # voor een kopje.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(headings) { heading in
                        Button {
                            onPick(heading)
                        } label: {
                            Text(heading.title)
                                .font(.system(size: heading.level == 1 ? 14 : 13, weight: heading.level == 1 ? .semibold : .regular))
                                .foregroundStyle(heading.level <= 2 ? .primary : .secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .padding(.leading, CGFloat(heading.level - 1) * 14)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
    }
}
