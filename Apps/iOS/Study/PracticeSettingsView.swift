import SwiftUI

struct PracticeSettingsView:View {
    @EnvironmentObject private var practice:PracticeWorkspace
    var body:some View {
        Form {
                Section("复习设置") {
                    Toggle("自测错题自动收录",isOn:Binding(get:{practice.settings.automaticMistakes},set:{value in var settings=practice.settings;settings.automaticMistakes=value;practice.configure(settings)}))
                    Slider(value:Binding(get:{practice.settings.retention},set:{value in var settings=practice.settings;settings.retention=value;practice.configure(settings)}),in:0.7...0.99,step:0.01){Text("目标保留率")}
                    Text("目标保留率：\(Int(practice.settings.retention*100))%")
                    Stepper("每日建议 \(practice.settings.dailyLimit) 张",value:Binding(get:{practice.settings.dailyLimit},set:{value in var settings=practice.settings;settings.dailyLimit=value;practice.configure(settings)}),in:1...100)
                    Button(practice.settings.reminders ? "关闭复习提醒":"开启复习提醒") {
                        if practice.settings.reminders {var settings=practice.settings;settings.reminders=false;practice.configure(settings)} else {Task{await practice.authorize()}}
                    }
                    DatePicker("提醒时间",selection:Binding(get:{Calendar.current.date(bySettingHour:practice.settings.hour,minute:practice.settings.minute,second:0,of:Date()) ?? Date()},set:{value in var settings=practice.settings;settings.hour=Calendar.current.component(.hour,from:value);settings.minute=Calendar.current.component(.minute,from:value);practice.configure(settings)}),displayedComponents:.hourAndMinute)
                    Toggle("通知预览题干",isOn:Binding(get:{practice.settings.preview},set:{value in var settings=practice.settings;settings.preview=value;practice.configure(settings)}))
                }
        }.navigationTitle("复习与提醒")
        .alert("复习设置",isPresented:Binding(get:{practice.issue != nil},set:{if !$0 {practice.issue=nil}})){Button("知道了"){practice.issue=nil}}message:{Text(practice.issue ?? "")}
    }
}
