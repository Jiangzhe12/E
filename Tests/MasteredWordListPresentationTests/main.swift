import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError(message)
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!

let today = Date(timeIntervalSince1970: 1_718_582_400)
let yesterday = today.addingTimeInterval(-86_400)

let items = [
    MasteredWordListItem(
        word: "relate",
        masteredAt: today.addingTimeInterval(3600),
        phonetic: "/ri'leit/",
        translation: "vt. 讲述；使互相关联",
        definition: "v. give an account of",
        nextReviewDue: today.addingTimeInterval(86_400),
        isGraduated: false
    ),
    MasteredWordListItem(
        word: "abandon",
        masteredAt: yesterday,
        phonetic: nil,
        translation: "vt. 放弃",
        definition: nil,
        nextReviewDue: nil,
        isGraduated: true
    )
]

let todayItems = MasteredWordListPresentation.filteredItems(
    items,
    scope: .today,
    searchText: "",
    now: today,
    calendar: calendar
)
expect(todayItems.map(\.word) == ["relate"], "today scope should only include words mastered today")

let translatedSearch = MasteredWordListPresentation.filteredItems(
    items,
    scope: .all,
    searchText: "放弃",
    now: today,
    calendar: calendar
)
expect(translatedSearch.map(\.word) == ["abandon"], "search should match local translations")

let sections = MasteredWordListPresentation.sections(
    for: items,
    now: today,
    calendar: calendar
)
expect(sections.count == 2, "items should be grouped by mastered date")
expect(sections[0].title == "今天 · 1 个", "today section should use friendly title")
expect(sections[1].title == "昨天 · 1 个", "yesterday section should use friendly title")

expect(
    MasteredWordListPresentation.reviewText(for: items[0], now: today, calendar: calendar).contains("下次复习"),
    "active review records should show next review time"
)
expect(
    MasteredWordListPresentation.reviewText(for: items[1], now: today, calendar: calendar) == "已完成全部复习",
    "graduated records should show completion"
)

print("MasteredWordListPresentationTests passed")
