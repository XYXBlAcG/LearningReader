import SwiftUI
import PracticeCore

struct ReviewEvidenceEditor: View {
    @EnvironmentObject private var practice: PracticeWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var record = ReviewEvidence()
    var body: some View {
        NavigationStack {
            Form {
                Section("独立作答") {
                    if let issue = practice.issue { Text(issue).foregroundStyle(.red) }
                    status("独立想到第一步", value: $record.firstStepIndependent)
                    status("结论正确", value: $record.resultCorrect)
                    status("证明完整", value: $record.proofComplete)
                    Picker("提示使用", selection: Binding(get: { record.hintLevel ?? -1 }, set: { record.hintLevel = $0 < 0 ? nil : $0 })) {
                        Text("未记录").tag(-1)
                        Text("无提示").tag(0)
                        Text("澄清条件").tag(1)
                        Text("指出原理").tag(2)
                        Text("给关键构造").tag(3)
                        Text("已看答案").tag(4)
                    }
                    TextField("用时（分钟）", value: $record.minutes, format: .number).keyboardType(.decimalPad)
                    TextField("第一个卡点或错误", text: Binding(get: {record.error ?? ""}, set: {record.error = $0.isEmpty ? nil : $0}), axis: .vertical)
                }
            }
            .navigationTitle("作答记录 · 自评")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .onAppear { record = practice.session?.evidence ?? ReviewEvidence() }
            .onChange(of: record) { _, value in practice.saveEvidence(value) }
        }
    }

    private func status(_ title: String, value: Binding<Bool?>) -> some View {
        Picker(title, selection: Binding(get: { value.wrappedValue.map { $0 ? 1 : 0 } ?? -1 }, set: { value.wrappedValue = $0 < 0 ? nil : $0 == 1 })) {
            Text("未记录").tag(-1)
            Text("是").tag(1)
            Text("否").tag(0)
        }
    }
}
