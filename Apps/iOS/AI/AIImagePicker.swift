import SwiftUI
import PhotosUI
import AVFoundation
import ImageIO
import AICore

enum AIImageSource: String, Identifiable { case camera, library; var id: String { rawValue } }

struct AIPhotoHost: ViewModifier {
    @Binding var source: AIImageSource?
    let onMaterial: (AIMaterial) -> Void
    @State private var pending: AIMaterial?
    func body(content: Content) -> some View {
        content.sheet(item: $source, onDismiss: {
            if let pending { self.pending = nil; onMaterial(pending) }
        }) { value in
            AIPhotoFlow(source: value) { image in
                pending = AIMaterial(title: "图片讲题", text: "请讲一讲这张图片中的问题。", image: image)
                source = nil
            }
        }
    }
}

struct AIPhotoFlow: View {
    let source: AIImageSource
    let onImage: (AIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var selected: PhotosPickerItem?
    @State private var camera = false
    @State private var photoPicker = false
    @State private var issue: String?
    @State private var loading = false
    @State private var crop = CGRect.zero

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let image {
                    GeometryReader { geometry in
                        let scale = min(geometry.size.width / image.size.width, geometry.size.height / image.size.height)
                        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                            if !crop.isEmpty { Rectangle().stroke(.tint, lineWidth: 2).background(.tint.opacity(0.12)).frame(width: crop.width, height: crop.height).offset(x: crop.minX, y: crop.minY) }
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 5).onChanged { value in
                            let start = CGPoint(x: min(max(value.startLocation.x, 0), size.width), y: min(max(value.startLocation.y, 0), size.height))
                            let end = CGPoint(x: min(max(value.location.x, 0), size.width), y: min(max(value.location.y, 0), size.height))
                            crop = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottom) {
                            if crop.width > 20 && crop.height > 20 {
                                Button("裁剪选区") {
                                    let rect = CGRect(x: crop.minX / scale, y: crop.minY / scale, width: crop.width / scale, height: crop.height / scale).integral
                                    if let cg = image.cgImage?.cropping(to: rect) { self.image = UIImage(cgImage: cg); crop = .zero }
                                }.buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    Text("可拖动框选需要讲解的题目。").font(.caption).foregroundStyle(.secondary)
                    Button("讲一讲") {
                        do { onImage(try AIImageProcessor.encode(image)) }
                        catch { issue = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                } else if loading { ProgressView("读取图片") }
                else { ContentUnavailableView("选择一道题", systemImage: "camera", description: Text("拍照或选择图片后讲解")) }
                HStack {
                    Button("拍照", systemImage: "camera") { Task { await openCamera() } }
                    Button("选择图片", systemImage: "photo") { photoPicker = true }
                }
                if let issue { Text(issue).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
            }
            .padding()
            .navigationTitle("图片讲题")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .fullScreenCover(isPresented: $camera) { AICamera { value in
                if let value { image = AIImageProcessor.prepare(value); crop = .zero }
                camera = false
            }.ignoresSafeArea() }
            .photosPicker(isPresented: $photoPicker, selection: $selected, matching: .images)
            .task { if source == .camera { await openCamera() } else { photoPicker = true } }
            .task(id: selected) {
                guard let selected else { return }
                loading = true
                defer { loading = false }
                do {
                    guard let data = try await selected.loadTransferable(type: Data.self) else { throw AIError.generation("无法读取此图片，请选择其他图片。") }
                    try Task.checkCancellation()
                    image = try AIImageProcessor.prepare(data: data); crop = .zero; issue = nil
                } catch { if !Task.isCancelled { issue = error.localizedDescription } }
            }
        }
    }

    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { issue = "此设备没有可用相机，请选择图片。"; return }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var allowed = status == .authorized
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        if allowed { issue = nil; camera = true }
        else { issue = "相机权限未开启。可在系统设置中允许相机，或直接选择图片。" }
    }
}

struct AICamera: UIViewControllerRepresentable {
    let onImage: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController(); picker.sourceType = .camera; picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) { }
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onImage(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) { onImage(info[.originalImage] as? UIImage) }
    }
}

enum AIImageProcessor {
    static func prepare(data: Data) throws -> UIImage {
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2400, kCGImageSourceCreateThumbnailWithTransform: true]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw AIError.generation("无法读取此图片，请选择其他图片。") }
        return UIImage(cgImage: image)
    }
    static func prepare(_ image: UIImage) -> UIImage {
        let scale = min(1, 2400 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
    static func encode(_ image: UIImage) throws -> AIImage {
        guard let data = prepare(image).jpegData(compressionQuality: 0.86), data.count <= 8_000_000 else { throw AIError.generation("图片过大，请裁剪题目后重试。") }
        return AIImage(data: data, mimeType: "image/jpeg")
    }
}
