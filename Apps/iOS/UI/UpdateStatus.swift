import SwiftUI

@MainActor final class UpdateStatus:ObservableObject {
    @Published var message=""
    @Published var checking=false
    @Published var url:URL?
    @AppStorage("updateReminders") var reminders=true
    @AppStorage("updateLastCheck") private var lastCheck=0.0
    @AppStorage("updateNotified") private var notified=""
    func check(automatic:Bool=false) async {
        guard !checking, !automatic || (reminders && Date().timeIntervalSince1970-lastCheck>86400) else {return}
        checking=true;defer{checking=false}
        do {
            let (data,response)=try await URLSession.shared.data(from:URL(string:"https://api.github.com/repos/XYXBlAcG/LearningReader/releases/latest")!)
            guard (response as? HTTPURLResponse)?.statusCode==200 else {throw URLError(.badServerResponse)}
            let release=try JSONDecoder().decode(Release.self,from:data)
            let version=release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()):release.tag_name
            let current=Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "0"
            let numbers:(String)->[Int]={value in var parts=value.split(separator:".").compactMap{Int($0)};while parts.count<3 {parts.append(0)};return parts}
            let newer=numbers(current).lexicographicallyPrecedes(numbers(version)) && !release.draft && !release.prerelease
            lastCheck=Date().timeIntervalSince1970
            guard !automatic || (newer && notified != version) else {return}
            url=newer ? release.html_url:nil
            message=newer ? "发现新版本 "+version:"已是最新版本"
            if newer {notified=version}
        }catch{if !automatic {message="检查更新失败，请稍后重试"}}
    }
    private struct Release:Decodable {let tag_name:String;let html_url:URL;let draft:Bool;let prerelease:Bool}
}
