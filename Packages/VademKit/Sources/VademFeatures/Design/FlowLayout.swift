import SwiftUI

/// A layout that places its subviews left to right and wraps them onto new lines when they do not fit.
/// A subview wider than the available width gets that width, so its text can wrap onto several lines.
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 12
    var verticalSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let frames = arrange(maxWidth: proposal.width ?? .infinity, subviews: subviews)
        let width = frames.map(\.maxX).max() ?? 0
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = arrange(maxWidth: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    // Her öğenin çerçevesi: satıra sığmayan öğe alt satıra geçer; satır içinde dikey ortalanır.
    private func arrange(maxWidth: CGFloat, subviews: Subviews) -> [CGRect] {
        var frames: [CGRect] = []
        var row: [Int] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        func finishRow() {
            for index in row {
                frames[index].origin.y = y + (rowHeight - frames[index].height) / 2
            }
            y += rowHeight + verticalSpacing
            row = []
            x = 0
            rowHeight = 0
        }

        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            // Tek başına satıra sığmayan öğe genişlikle sınırlanır; metni birden çok satıra kırılır.
            if size.width > maxWidth {
                size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            if !row.isEmpty, x + horizontalSpacing + size.width > maxWidth {
                finishRow()
            }
            if !row.isEmpty { x += horizontalSpacing }
            frames.append(CGRect(origin: CGPoint(x: x, y: 0), size: size))
            row.append(frames.count - 1)
            x += size.width
            rowHeight = max(rowHeight, size.height)
        }
        if !row.isEmpty {
            finishRow()
        }
        return frames
    }
}
