import SwiftUI

struct MasonryLayout: Layout {
    var columns: Int = 2
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var columnHeights = Array(repeating: CGFloat.zero, count: columns)

        for subview in subviews {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })!.offset
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            columnHeights[shortestColumn] += size.height + spacing
        }

        let maxHeight = columnHeights.max() ?? 0
        return CGSize(width: width, height: max(maxHeight - spacing, 0))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columnWidth = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var columnHeights = Array(repeating: CGFloat.zero, count: columns)

        for subview in subviews {
            let shortestColumn = columnHeights.enumerated().min(by: { $0.element < $1.element })!.offset
            let x = bounds.minX + CGFloat(shortestColumn) * (columnWidth + spacing)
            let y = bounds.minY + columnHeights[shortestColumn]
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))

            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: columnWidth, height: size.height))
            columnHeights[shortestColumn] += size.height + spacing
        }
    }
}
