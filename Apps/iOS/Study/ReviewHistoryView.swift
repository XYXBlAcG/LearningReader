import SwiftUI
import PracticeCore

struct ReviewHistoryView: View {
    let item: PracticeItem
    var body: some View {
        List {
            if item.reviews.isEmpty { ContentUnavailableView("暂无作答记录", systemImage: "clock") }
            ForEach(Array(item.reviews.enumerated().reversed()), id: \.offset) { _, review in
                Section(review.date.formatted()) {
                    Text("记忆反馈 · " + (ReviewConfidence(rawValue: review.grade)?.title ?? String(review.grade)))
                    if let evidence = review.evidence {
                        LabeledContent("独立起手", value: evidence.firstStepIndependent.map { $0 ? "是" : "否" } ?? "未记录")
                        LabeledContent("提示层级", value: evidence.hintLevel.map { String($0) } ?? "未记录")
                        LabeledContent("结论正确", value: evidence.resultCorrect.map { $0 ? "是" : "否" } ?? "未记录")
                        LabeledContent("证明完整", value: evidence.proofComplete.map { $0 ? "是" : "否" } ?? "未记录")
                        if let minutes = evidence.minutes { Text("用时 \(minutes.formatted()) 分钟") }
                        if let error = evidence.error { Text(error) }
                    } else { Text("此条记录未填写作答自评").foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle("历史作答 · 自评")
    }
}
