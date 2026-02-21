import SwiftUI

/// A table view with horizontal scroll and zebra-striped rows.
struct TableView: View {
    let headers: [String]
    let rows: [[String]]

    private let cellMinWidth: CGFloat = 100
    private let cellPadding: CGFloat = Spacing.sm

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
                        Text(header)
                            .font(Typography.tag)
                            .foregroundStyle(Color.folio.textPrimary)
                            .frame(minWidth: cellMinWidth, alignment: .leading)
                            .padding(.horizontal, cellPadding)
                            .padding(.vertical, Spacing.xs)

                        if index < headers.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(Color.folio.tagBackground)

                Divider()

                // Body rows with zebra stripes
                ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                    HStack(spacing: 0) {
                        ForEach(Array(row.enumerated()), id: \.offset) { colIndex, cell in
                            Text(cell)
                                .font(Typography.body)
                                .foregroundStyle(Color.folio.textPrimary)
                                .frame(minWidth: cellMinWidth, alignment: .leading)
                                .padding(.horizontal, cellPadding)
                                .padding(.vertical, Spacing.xs)

                            if colIndex < row.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(rowIndex.isMultiple(of: 2)
                        ? Color.folio.cardBackground
                        : Color.folio.background)

                    if rowIndex < rows.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(Color.folio.separator, lineWidth: 1)
        )
    }
}

#Preview {
    TableView(
        headers: ["Language", "Type", "Year"],
        rows: [
            ["Swift", "Compiled", "2014"],
            ["Kotlin", "Compiled", "2011"],
            ["Python", "Interpreted", "1991"],
            ["JavaScript", "Interpreted", "1995"],
        ]
    )
    .padding()
}
