import SwiftUI
import LearningCore

enum LearningTab:String,CaseIterable,Identifiable {
    case home,catalog,study
    var id:String {rawValue}
    var title:String {switch self{case .home:return "主界面";case .catalog:return "目录";case .study:return "学习"}}
    var symbol:String {switch self{case .home:return "house";case .catalog:return "list.bullet";case .study:return "book"}}
}
enum LearningBarPreference:String,CaseIterable,Identifiable {
    case visible,readingHidden,hidden
    var id:String {rawValue}
    var title:String {switch self{case .visible:return "始终显示";case .readingHidden:return "阅读时隐藏";case .hidden:return "始终隐藏"}}
    func hides(_ tab:LearningTab)->Bool {self == .hidden || (self == .readingHidden && tab == .study)}
}

extension LearningLocation {
    init(course:CourseSource,kind:String,path:String,title:String){
        let key=course.repositoryID.map{"github:\($0):\(course.branch):\(course.configuration.root)"} ?? "local:"+course.id
        self.init(courseKey:key,courseID:course.id,kind:kind,path:path,title:title)
    }
}
