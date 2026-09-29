import SwiftUI

struct PageSelector: View {
  let page: ForumPage
  let select: (Int) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  private var numbers: [Int] {
    let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty { return Array(1...page.pageCount) }
    guard let number = Int(value), (1...page.pageCount).contains(number) else { return [] }
    return [number]
  }
  var body: some View {
    NavigationStack {
      ScrollViewReader { proxy in
        List {
          ForEach(numbers, id: \.self) { number in
            Button {
              dismiss()
              if number != page.pageNumber { select(number) }
            } label: {
              HStack {
                Text("Page \(number)").monospacedDigit().foregroundStyle(.primary)
                Spacer()
                if number == page.pageNumber { Image(systemName: "checkmark").foregroundStyle(.blue) }
              }.contentShape(Rectangle())
            }.id(number)
          }
        }
        .overlay { if numbers.isEmpty { ContentUnavailableView("Choose a page from 1 to \(page.pageCount)", systemImage: "number") } }
        .searchable(text: $query, prompt: "Page number (1–\(page.pageCount))")
        .onAppear { proxy.scrollTo(page.pageNumber, anchor: .center) }
      }
      .navigationTitle("Go to page").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
    }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
  }
}
