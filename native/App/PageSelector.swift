import SwiftUI

struct PageSelector: View {
  let page: ForumPage
  let select: (Int) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  private var requestedPage: Int? {
    guard let number = Int(query.trimmingCharacters(in: .whitespacesAndNewlines)),
          (1...page.pageCount).contains(number) else { return nil }
    return number
  }
  // A forum may have over ten thousand pages. Keep the picker small and offer
  // direct numeric entry instead of allocating a row for every possible page.
  private var numbers: [Int] {
    if page.pageCount <= 30 { return Array(1...page.pageCount) }
    let nearby = Array(max(1, page.pageNumber - 5)...min(page.pageCount, page.pageNumber + 5))
    return Array(Set([1, page.pageCount] + nearby)).sorted()
  }
  var body: some View {
    NavigationStack {
      List {
        Section(AppText.format("Page 1–%@", String(describing: page.pageCount))) {
          HStack {
            TextField(AppText.text("Page number"), text: $query).keyboardType(.numberPad)
              .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button(AppText.text("Go")) { if let number = requestedPage { choose(number) } }
              .disabled(requestedPage == nil)
          }
        }
        Section(AppText.text("Nearby pages")) {
          ForEach(numbers, id: \.self) { number in
            Button { choose(number) } label: {
              HStack {
                Text(AppText.format("Page %@", String(describing: number))).monospacedDigit().foregroundStyle(.primary)
                Spacer()
                if number == page.pageNumber { Image(systemName: "checkmark").foregroundStyle(.blue) }
              }.contentShape(Rectangle())
            }
          }
        }
      }
      .navigationTitle(AppText.text("Go to page")).navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button(AppText.text("Cancel")) { dismiss() } } }
    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
  }
  private func choose(_ number: Int) {
    dismiss()
    if number != page.pageNumber { select(number) }
  }
}
