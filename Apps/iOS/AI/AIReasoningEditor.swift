import SwiftUI
import AICore

struct AIReasoningEditor:View {
    @Binding var profile:AIProfile
    var body:some View {
        Section("推理与输出") {
            Toggle("自定义推理参数",isOn:Binding(get:{profile.reasoning != nil},set:{profile.reasoning=$0 ? AIReasoning() : nil}))
            if let configuration=profile.reasoning {
                Picker("参数模式",selection:Binding(get:{configuration.mode},set:{value in
                    var updated=configuration;updated.mode=value
                    if !updated.efforts(for:profile.api).contains(updated.effort) { updated.effort = .high }
                    profile.reasoning=updated
                })) {
                    ForEach(AIReasoningMode.available(for:profile.api),id:\.self) { Text($0.title).tag($0) }
                }
                if configuration.mode == .budget {
                    TextField("思考 Token 预算",text:Binding(get:{String(configuration.budget)},set:{value in if let count=Int(value) { var updated=configuration;updated.budget=count;profile.reasoning=updated } })).keyboardType(.numbersAndPunctuation)
                } else {
                    Picker("推理强度",selection:Binding(get:{configuration.effort},set:{value in var updated=configuration;updated.effort=value;profile.reasoning=updated})) {
                        ForEach(configuration.efforts(for:profile.api),id:\.self) { Text($0.title+"（"+$0.rawValue+"）").tag($0) }
                    }
                }
                Text("请按所选模型支持的参数配置；测试和讲解使用相同设置。").font(.caption).foregroundStyle(.secondary)
            }
            TextField("最大输出 Token（留空用默认值）",text:Binding(get:{profile.maxOutputTokens.map(String.init) ?? ""},set:{profile.maxOutputTokens=Int($0)})).keyboardType(.numberPad)
        }
    }
}
