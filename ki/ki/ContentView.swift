//
//  ContentView.swift
//  lu
//
//  Created by 郭森 on 2025/1/22.
//
import SwiftUI
import PDFKit
import AVFoundation
import UIKit
import UniformTypeIdentifiers  // 添加这个导入
import Photos

// 添加 Color 扩展，支持十六进制颜色代码
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// 修改 DrawingTool 枚举，使其符合 Hashable 协议
enum DrawingTool: Hashable {
    case pen, pencil, marker, eraser, laser, shape(ShapeType), image, keyboard, text, light
    
    // 实现 Hashable 协议
    func hash(into hasher: inout Hasher) {
        switch self {
        case .pen: hasher.combine(0)
        case .pencil: hasher.combine(1)
        case .marker: hasher.combine(2)
        case .eraser: hasher.combine(3)
        case .laser: hasher.combine(4)
        case .shape(let type):
            hasher.combine(5)
            hasher.combine(type)
        case .image: hasher.combine(6)
        case .keyboard: hasher.combine(7)
        case .text: hasher.combine(8)
        case .light: hasher.combine(9)
        }
    }
    
    // 实现相等性比较
    static func == (lhs: DrawingTool, rhs: DrawingTool) -> Bool {
        switch (lhs, rhs) {
        case (.pen, .pen),
             (.pencil, .pencil),
             (.marker, .marker),
             (.eraser, .eraser),
             (.laser, .laser),
             (.image, .image),
             (.keyboard, .keyboard),
             (.text, .text),
             (.light, .light):
            return true
        case (.shape(let type1), .shape(let type2)):
            return type1 == type2
        default:
            return false
        }
    }
}

enum ParabolaDirection {
    case up, down, left, right
}

// 修改 ShapeType 枚举，添加新的形状类型
enum ShapeType: Hashable {
    case rectangle, circle, line, arrow
    case coordinateAxis  // 坐标轴
    case ellipse        // 椭圆
    case hyperbola(HyperbolaType)      // 双曲线
    case parabola(ParabolaDirection)  // 抛物线（带方向）
    case cube           // 正方体
    case cuboid         // 立方体
    case cone           // 圆锥
    case cylinder       // 圆柱
    case dashed        // 添加虚线类型
}

enum HyperbolaType {
    case xAxis, yAxis
}

// 定义绘图路径结构
struct DrawingPath: Identifiable {
    let id = UUID()
    var points: [CGPoint]
    var color: UIColor
    var lineWidth: CGFloat
    var tool: DrawingTool
    var opacity: CGFloat
    var shapeType: ShapeType?  // 用于形状工具
    var isFilled: Bool = false // 是否填充形状
    var pressurePoints: [CGFloat] = [] // 添加压力数组，与points一一对应
}

// 添加工具设置结构体
struct ToolSettings {
    var lineWidth: CGFloat
    var opacity: CGFloat
    var color: Color
}

// 添加工具设置管理器
class ToolSettingsManager: ObservableObject {
    static let shared = ToolSettingsManager()
    
    @Published private var settings: [DrawingTool: ToolSettings] = [
        .pen: ToolSettings(lineWidth: 1.0, opacity: 1.0, color: .black),
        .pencil: ToolSettings(lineWidth: 0.8, opacity: 0.8, color: .black),
        .marker: ToolSettings(lineWidth: 10.0, opacity: 0.3, color: .black),
        .eraser: ToolSettings(lineWidth: 20.0, opacity: 1.0, color: .white),
        .laser: ToolSettings(lineWidth: 3.0, opacity: 0.8, color: .red),
        .shape(.line): ToolSettings(lineWidth: 2.0, opacity: 1.0, color: .black)
    ]
    
    func getSettings(for tool: DrawingTool) -> ToolSettings {
        if case .shape(_) = tool {
            return settings[.shape(.line)] ?? ToolSettings(lineWidth: 2.0, opacity: 1.0, color: .black)
        }
        return settings[tool] ?? ToolSettings(lineWidth: 1.0, opacity: 1.0, color: .black)
    }
    
    func updateSettings(for tool: DrawingTool, lineWidth: CGFloat? = nil, opacity: CGFloat? = nil, color: Color? = nil) {
        var currentSettings = getSettings(for: tool)
        if let lineWidth = lineWidth {
            currentSettings.lineWidth = lineWidth
        }
        if let opacity = opacity {
            currentSettings.opacity = opacity
        }
        if let color = color {
            currentSettings.color = color
        }
        
        if case .shape = tool {
            settings[.shape(.line)] = currentSettings
        } else {
            settings[tool] = currentSettings
        }
    }
}

struct ContentView: View {
    @State private var selectedDocument: URL?
    @State private var isCameraOn = true
    @State private var isMicOn = true
    @State private var currentTool: DrawingTool = .pen
    @State private var selectedColor: Color = .black
    @State private var lineWidth: CGFloat = 1.0  // 添加线条粗细状态
    @StateObject private var toolSettings = ToolSettingsManager.shared
    @StateObject private var documentPickerDelegate = DocumentPickerDelegate()
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var isShowingSaveDialog = false
    @State private var recordedVideoURL: URL?
    @StateObject private var screenRecorder = ScreenRecorder.shared
    @State private var showSuccessAlert = false
    @State private var showErrorAlert = false
    @State private var showPermissionAlert = false
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            HStack(spacing: 8) {
                // 文档上传按钮
                Button(action: selectDocument) {
                    Image(systemName: "doc.badge.plus")
                        .foregroundColor(.gray)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                
                Divider()
                    .frame(height: 20)
                
                // 撤销重做按钮
                Group {
                    Button(action: {
                        DrawingView.shared.undo()
                        updateUndoRedoState()
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .foregroundColor(canUndo ? .accentColor : .gray)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canUndo)
                    
                    Button(action: {
                        DrawingView.shared.redo()
                        updateUndoRedoState()
                    }) {
                        Image(systemName: "arrow.uturn.forward")
                            .foregroundColor(canRedo ? .accentColor : .gray)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canRedo)
                }
                
                Divider()
                    .frame(height: 20)
                
                // 添加翻页控制按钮
                Group {
                    Button(action: { DocumentView.previousPage() }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.gray)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(!DocumentView.canGoToPreviousPage())
                    
                    Text("\(DocumentView.currentPage) / \(DocumentView.totalPages)")
                        .font(.system(size: 14))
                        .frame(width: 50)
                    
                    Button(action: { DocumentView.nextPage() }) {
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .disabled(!DocumentView.canGoToNextPage())
                }
                
                Divider()
                    .frame(height: 20)
                
                // 添加清除按钮
                Button(action: {
                    DrawingView.shared.clearAll()
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                
                Divider()
                    .frame(height: 20)
                
                // 颜色选择器
                ColorPicker("", selection: $selectedColor)
                    .frame(width: 32, height: 32)
                    .scaleEffect(0.8)
                
                // 添加常用颜色按钮
                Group {
                    // 蓝色按钮
                    Button(action: { selectedColor = Color(hex: "5E30EB") }) {
                        Circle()
                            .fill(Color(hex: "5E30EB"))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(selectedColor == Color(hex: "5E30EB") ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    // 红色按钮
                    Button(action: { selectedColor = Color(hex: "E22400") }) {
                        Circle()
                            .fill(Color(hex: "E22400"))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(selectedColor == Color(hex: "E22400") ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                    
                    // 黑色按钮
                    Button(action: { selectedColor = .black }) {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(selectedColor == .black ? Color.accentColor : Color.clear, lineWidth: 2)
                            )
                    }
                    .buttonStyle(.plain)
                }
                
                Divider()
                    .frame(height: 20)
                
                // 修改线条粗细滑动条部分
                Slider(value: Binding(
                    get: { toolSettings.getSettings(for: currentTool).lineWidth },
                    set: { toolSettings.updateSettings(for: currentTool, lineWidth: $0) }
                ), in: 0.5...10)
                    .frame(width: 100)
                
                Divider()
                    .frame(height: 20)
                
                // 工具栏按钮
                ForEach([
                    (.pen, "pencil.tip"),
                    (.pencil, "pencil"),
                    (.marker, "highlighter"),
                    (.eraser, "eraser"),
                    (.laser, "circle.dotted"),
                    (.shape(.line), "line.diagonal")
                ] as [(DrawingTool, String)], id: \.0) { tool, icon in
                    if case .shape = tool {
                        Menu {
                            Button("直线") { currentTool = .shape(.line) }
                            Button("虚线") { currentTool = .shape(.dashed) }
                            Button("箭头") { currentTool = .shape(.arrow) }
                            Button("矩形") { currentTool = .shape(.rectangle) }
                            Button("圆形") { currentTool = .shape(.circle) }
                            Divider()
                            Button("坐标轴") { currentTool = .shape(.coordinateAxis) }
                            Button("椭圆") { currentTool = .shape(.ellipse) }
                            Menu("双曲线") {
                                Button("X轴双曲线") { currentTool = .shape(.hyperbola(.xAxis)) }
                                Button("Y轴双曲线") { currentTool = .shape(.hyperbola(.yAxis)) }
                            }
                            Menu("抛物线") {
                                Button("向上开口") { currentTool = .shape(.parabola(.up)) }
                                Button("向下开口") { currentTool = .shape(.parabola(.down)) }
                                Button("向左开口") { currentTool = .shape(.parabola(.left)) }
                                Button("向右开口") { currentTool = .shape(.parabola(.right)) }
                            }
                            Divider()
                            Button("正方体") { currentTool = .shape(.cube) }
                            Button("立方体") { currentTool = .shape(.cuboid) }
                            Button("圆锥") { currentTool = .shape(.cone) }
                            Button("圆柱") { currentTool = .shape(.cylinder) }
                        } label: {
                            Image(systemName: "line.diagonal")
                                .foregroundColor(isShapeTool(currentTool) ? .accentColor : .gray)
                                .frame(width: 32, height: 32)
                        }
                    } else {
                        Button(action: { currentTool = tool }) {
                            Image(systemName: icon)
                                .foregroundColor(currentTool == tool ? .accentColor : .gray)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .background(currentTool == tool ? Color.accentColor.opacity(0.2) : Color.clear)
                        .cornerRadius(6)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(uiColor: .systemBackground))
            
            // 主要内容区域
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // 左侧课件显示区域 (4:3比例)
                    let mainWidth = geometry.size.width * 0.75  // 75%的宽度给课件
                    let mainHeight = geometry.size.height  // 使用完整高度
                    
                    ZStack {
                        // PDF 文档视图放在底层
                        DocumentView(documentURL: $selectedDocument)
                            .frame(width: mainWidth, height: mainHeight)
                            .allowsHitTesting(false)  // 禁止 PDF 视图接收触摸事件
                        
                        // 绘图层放在顶层
                        DrawingCanvas(tool: $currentTool, selectedColor: $selectedColor)
                            .frame(width: mainWidth, height: mainHeight)
                            .allowsHitTesting(true)  // 允许绘图层接收触摸事件
                    }
                    .background(Color.white)
                    .padding(.leading)
                    
                    // 右侧区域
                    VStack(alignment: .center) {  // 改为居中对齐
                        // 摄像头区域
                        let cameraWidth = mainWidth * 0.3
                        let cameraHeight = cameraWidth * 3/4
                        
                        ZStack {
                            if isCameraOn {
                                CameraView()
                                    .frame(width: cameraWidth, height: cameraHeight)
                                    .clipped()
                            } else {
                                Color.black
                                    .frame(width: cameraWidth, height: cameraHeight)
                            }
                            
                            // 摄像头控制按钮
                            VStack {
                                HStack {
                                    Spacer()
                                    Button(action: {
                                        isCameraOn.toggle()
                                        CameraView.shared.isCameraOn = isCameraOn
                                    }) {
                                        Image(systemName: isCameraOn ? "video.fill" : "video.slash.fill")
                                            .foregroundColor(isCameraOn ? .green : .red)
                                            .padding(4)
                                            .background(Color.black.opacity(0.5))
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(8)
                                }
                                Spacer()
                            }
                        }
                        .frame(width: cameraWidth, height: cameraHeight)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .padding(.top)
                        
                        // 控制按钮
                        HStack(spacing: 16) {
                            Button(action: { isMicOn.toggle() }) {
                                Image(systemName: isMicOn ? "mic.fill" : "mic.slash.fill")
                                    .foregroundColor(isMicOn ? .green : .red)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: {
                                if screenRecorder.isRecording {
                                    screenRecorder.stopRecording { url in
                                        if let url = url {
                                            recordedVideoURL = url
                                            isShowingSaveDialog = true
                                        }
                                    }
                                } else {
                                    screenRecorder.startRecording()
                                }
                            }) {
                                Image(systemName: screenRecorder.isRecording ? "stop.circle.fill" : "record.circle")
                                    .font(.title2)
                                    .foregroundColor(screenRecorder.isRecording ? .red : .gray)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                        
                        // 保存对话框
                        .alert("保存录制", isPresented: $isShowingSaveDialog) {
                            Button("保存") {
                                if let url = recordedVideoURL {
                                    saveVideo(at: url)
                                }
                            }
                            Button("取消", role: .cancel) {
                                // 清理临时文件
                                if let url = recordedVideoURL {
                                    try? FileManager.default.removeItem(at: url)
                                }
                            }
                        } message: {
                            Text("是否要保存录制的视频？")
                        }
                        
                        Spacer()  // 添加 Spacer 来保持布局
                    }
                    .frame(width: geometry.size.width * 0.25)  // 固定右侧区域宽度为25%
                    .padding(.trailing)  // 添加右边距
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        // 修改 onChange 为新的语法
        .onChange(of: currentTool, initial: false) { oldValue, newValue in
            // 当工具改变时，更新颜色
            selectedColor = toolSettings.getSettings(for: newValue).color
        }
        .onChange(of: selectedColor, initial: false) { oldValue, newValue in
            // 当颜色改变时，保存到当前工具的设置
            toolSettings.updateSettings(for: currentTool, color: newValue)
        }
        .onAppear {
            // 设置 documentPickerDelegate 的 completion handler
            documentPickerDelegate.completion = { url in
                if url.pathExtension.lowercased() == "ppt" || url.pathExtension.lowercased() == "pptx" {
                    print("PPT conversion not supported on iPadOS")
                } else {
                    selectedDocument = url
                }
            }
            updateUndoRedoState()
            
            // 添加撤销重做状态更新的通知观察者
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("UpdateUndoRedoState"),
                object: nil,
                queue: .main) { _ in
                    updateUndoRedoState()
                }
        }
        
        // 成功提示
        .alert("保存成功", isPresented: $showSuccessAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("视频已成功保存到相册")
        }
        
        // 错误提示
        .alert("保存失败", isPresented: $showErrorAlert) {
            Button("确定", role: .cancel) { }
        } message: {
            Text("保存视频时出现错误，请重试")
        }
        
        // 权限提示
        .alert("需要权限", isPresented: $showPermissionAlert) {
            Button("去设置", role: .cancel) {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("请在设置中允许访问相册以保存视频")
        }
    }
    
    private func updateUndoRedoState() {
        canUndo = DrawingView.shared.canUndo()
        canRedo = DrawingView.shared.canRedo()
    }
    
    // 修改文档选择方法
    func selectDocument() {
        let supportedTypes: [UTType] = [.pdf, .powerpoint, .presentationPackage]
        let documentPicker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        documentPicker.delegate = documentPickerDelegate
        documentPicker.allowsMultipleSelection = false
        
        // 确保文档选择器在主线程上显示
        DispatchQueue.main.async {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = windowScene.windows.first,
                  let viewController = window.rootViewController else {
                return
            }
            viewController.present(documentPicker, animated: true)
        }
    }
    
    // 添加工具比较函数
    private func matchTools(_ tool1: DrawingTool, _ tool2: DrawingTool) -> Bool {
        switch (tool1, tool2) {
        case (.pen, .pen),
             (.pencil, .pencil),
             (.marker, .marker),
             (.eraser, .eraser),
             (.laser, .laser),
             (.image, .image),
             (.keyboard, .keyboard),
             (.text, .text),
             (.light, .light):
            return true
        case (.shape(let type1), .shape(let type2)):
            return type1 == type2
        default:
            return false
        }
    }
    
    // 在 ContentView 中添加一个辅助函数来检查是否是形状工具
    private func isShapeTool(_ tool: DrawingTool) -> Bool {
        if case .shape = tool {
            return true
        }
        return false
    }
    
    // 修改 saveVideo 方法
    func saveVideo(at sourceURL: URL) {
        print("开始保存视频，文件路径：\(sourceURL.path)")
        
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("错误：视频文件不存在")
            showErrorAlert = true
            return
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: sourceURL.path)
            print("文件大小：\(attributes[.size] ?? 0) bytes")
        } catch {
            print("获取文件属性失败：\(error.localizedDescription)")
        }
        
        PHPhotoLibrary.requestAuthorization { [self] status in
            DispatchQueue.main.async {
                print("相册权限状态：\(status.rawValue)")
                switch status {
                case .authorized, .limited:
                    PHPhotoLibrary.shared().performChanges({
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .video, fileURL: sourceURL, options: options)
                    }) { success, error in
                        DispatchQueue.main.async {
                            if success {
                                print("视频已成功保存到相册")
                                self.showSuccessAlert = true
                            } else {
                                print("保存视频失败：\(error?.localizedDescription ?? "未知错误")")
                                self.showErrorAlert = true
                            }
                        }
                    }
                case .denied, .restricted:
                    print("没有相册访问权限")
                    self.showPermissionAlert = true
                case .notDetermined:
                    print("相册权限未确定")
                @unknown default:
                    print("未知的权限状态")
                }
            }
        }
    }
}

// 修改 DocumentPickerDelegate 类
class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate, ObservableObject {
    var completion: ((URL) -> Void)?
    
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        
        // 获取文件访问权限
        if !url.startAccessingSecurityScopedResource() {
            print("Failed to access the selected document")
            return
        }
        
        // 确保在主线程上更新 UI
        DispatchQueue.main.async {
            self.completion?(url)
            // 延迟释放文件访问权限
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                url.stopAccessingSecurityScopedResource()
            }
        }
    }
    
    // 添加取消选择的处理
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // 用户取消选择时的处理
        print("Document picker was cancelled")
    }
}

// 修改 DocumentView 实现
struct DocumentView: View {
    @Binding var documentURL: URL?
    public static var currentPage: Int = 1
    public static var totalPages: Int = 1
    public static var currentDocument: PDFDocument?
    
    // 修改 nextPage 方法
    static func nextPage() {
        guard let pdfView = PDFViewGlobal.shared.pdfView,
              let document = pdfView.document,
              let currentPage = pdfView.currentPage else {
            return
        }
        
        let currentIndex = document.index(for: currentPage)
        if let nextPage = document.page(at: currentIndex + 1) {
            pdfView.go(to: nextPage)
            self.currentPage = currentIndex + 2 // 页码从1开始显示
        }
    }
    
    // 修改 previousPage 方法
    static func previousPage() {
        guard let pdfView = PDFViewGlobal.shared.pdfView,
              let document = pdfView.document,
              let currentPage = pdfView.currentPage else {
            return
        }
        
        let currentIndex = document.index(for: currentPage)
        if currentIndex > 0,
           let prevPage = document.page(at: currentIndex - 1) {
            pdfView.go(to: prevPage)
            self.currentPage = currentIndex // 修正：这里应该是 currentIndex，而不是 currentIndex + 1
        }
    }
    
    // 修改 canGoToNextPage 方法
    static func canGoToNextPage() -> Bool {
        guard let pdfView = PDFViewGlobal.shared.pdfView,
              let document = pdfView.document,
              let currentPage = pdfView.currentPage else {
            return false
        }
        let currentIndex = document.index(for: currentPage)
        return currentIndex < document.pageCount - 1
    }
    
    // 修改 canGoToPreviousPage 方法
    static func canGoToPreviousPage() -> Bool {
        guard let pdfView = PDFViewGlobal.shared.pdfView,
              let document = pdfView.document,
              let currentPage = pdfView.currentPage else {
            return false
        }
        let currentIndex = document.index(for: currentPage)
        return currentIndex > 0
    }
    
    var body: some View {
        ZStack {
            Color.white
            
            if let url = documentURL {
                PDFKitView(url: url)
                    .allowsHitTesting(false)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("点击左上角按钮上传课件")
                        .font(.title3)
                    Text("支持 PDF 和 PPT 格式")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
        }
        .onAppear {
            if let url = documentURL,
               let document = PDFDocument(url: url) {
                DocumentView.currentDocument = document
                DocumentView.totalPages = document.pageCount
                DocumentView.currentPage = 1
            }
        }
    }
}

// 添加一个全局的 PDFView 引用
class PDFViewGlobal {
    static let shared = PDFViewGlobal()
    private init() {}
    
    weak var pdfView: PDFView?
    
    func go(to page: PDFPage) {
        pdfView?.go(to: page)
    }
}

// 修改 PDFKitView 实现
struct PDFKitView: UIViewRepresentable {
    let url: URL
    
    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.backgroundColor = .white
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        
        // 保存全局引用
        PDFViewGlobal.shared.pdfView = pdfView
        
        // 加载 PDF 文档
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            DocumentView.totalPages = document.pageCount
            
            // 确保初始页码正确
            if let firstPage = document.page(at: 0) {
                pdfView.go(to: firstPage)
                DocumentView.currentPage = 1
            }
            
            // 添加页面切换监听
            NotificationCenter.default.addObserver(
                forName: .PDFViewPageChanged,
                object: pdfView,
                queue: .main) { _ in
                    if let currentPage = pdfView.currentPage,
                       let document = pdfView.document {
                        let pageIndex = document.index(for: currentPage)
                        DocumentView.currentPage = pageIndex + 1 // 页码从1开始显示
                    }
                }
        }
        
        return pdfView
    }
    
    func updateUIView(_ pdfView: PDFView, context: Context) {
        if let document = PDFDocument(url: url),
           pdfView.document?.documentURL != url {
            pdfView.document = document
            DocumentView.totalPages = document.pageCount
            
            // 确保更新文档时页码正确
            if let firstPage = document.page(at: 0) {
                pdfView.go(to: firstPage)
                DocumentView.currentPage = 1
            }
        }
    }
}

// 修改 DrawingView
class DrawingView: UIView {
    static let shared = DrawingView(frame: .zero)
    weak var coordinator: DrawingCanvas.Coordinator?
    private var currentPath: DrawingPath?
    @Published private(set) var paths: [DrawingPath] = []  // 添加 @Published
    var tool: DrawingTool = .pen
    
    // 添加手写笔交互支持
    private var pencilInteraction: UIPencilInteraction?
    
    // 修改压力平滑相关属性
    private var lastPressure: CGFloat = 0.0  // 改为从0开始
    private let pressureSmoothingFactor: CGFloat = 0.2  // 降低平滑因子，使过渡更自然
    private var pressureBuffer: [CGFloat] = []  // 添加压力缓冲数组
    private let pressureBufferSize = 5  // 缓冲区大小
    
    // 恢复笔锋相关属性
    private var lastPoint: CGPoint?
    private var lastTime: TimeInterval = 0
    private var lastVelocity: CGFloat = 0
    private let velocitySmoothingFactor: CGFloat = 0.3
    
    // 在 DrawingView 类中添加以下属性
    private var pathHistory: [[DrawingPath]] = [[]]  // 路径历史记录
    private var currentHistoryIndex = 0  // 当前历史记录索引
    
    override init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = .clear
        isOpaque = false
        layer.backgroundColor = UIColor.clear.cgColor
        isUserInteractionEnabled = true
        isMultipleTouchEnabled = false
        
        // 配置 Apple Pencil 交互
        if #available(iOS 12.1, *) {
            pencilInteraction = UIPencilInteraction()
            pencilInteraction?.delegate = self
            addInteraction(pencilInteraction!)
        }
    }
    
    // 修改触摸开始方法
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        let settings = ToolSettingsManager.shared.getSettings(for: tool)
        
        // 重置状态
        lastPoint = location
        lastTime = touch.timestamp
        lastVelocity = 0
        
        // 重置压力缓冲区
        pressureBuffer.removeAll()
        
        // 获取初始压力值
        let initialPressure = touch.force > 0 ? touch.force / touch.maximumPossibleForce : 0.3
        lastPressure = initialPressure  // 设置初始压力
        pressureBuffer.append(initialPressure)
        
        currentPath = DrawingPath(
            points: [location],
            color: UIColor(settings.color),
            lineWidth: settings.lineWidth,
            tool: tool,
            opacity: settings.opacity,
            pressurePoints: [initialPressure]
        )
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard var path = currentPath,
              let touch = touches.first else { return }
        
        let location = touch.location(in: self)
        
        // 修改压力值计算，使用平滑处理
        let rawPressure = touch.force > 0 ? touch.force / touch.maximumPossibleForce : 0.3
        let smoothedPressure = smoothPressure(rawPressure)
        
        path.points.append(location)
        path.pressurePoints.append(smoothedPressure)  // 使用平滑后的压力值
        currentPath = path
        
        setNeedsDisplay()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let path = currentPath {
            // 移除当前索引之后的所有历史记录
            pathHistory.removeLast(pathHistory.count - currentHistoryIndex - 1)
            
            // 创建新的历史记录
            var newPaths = pathHistory[currentHistoryIndex]
            newPaths.append(path)
            pathHistory.append(newPaths)
            currentHistoryIndex += 1
            
            // 更新当前路径集合
            paths = newPaths
        }
        currentPath = nil
        setNeedsDisplay()
        
        // 通知 ContentView 更新撤销重做状态
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUndoRedoState"), object: nil)
    }
    
    override func draw(_ rect: CGRect) {
        super.draw(rect)
        guard let context = UIGraphicsGetCurrentContext() else { return }
        
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // 绘制所有路径
        for path in paths {
            drawPath(path, in: context)
        }
        
        // 绘制当前路径
        if let currentPath = currentPath {
            drawPath(currentPath, in: context)
        }
    }
    
    private func drawPath(_ path: DrawingPath, in context: CGContext) {
        guard !path.points.isEmpty else { return }
        
        context.saveGState()
        
        context.setStrokeColor(path.color.cgColor)
        context.setAlpha(path.opacity)
        
        if path.tool == .eraser {
            context.setBlendMode(.clear)
        } else {
            context.setBlendMode(.normal)
        }
        
        switch path.tool {
        case .pen, .pencil:
            drawStrokeWithPressure(path, in: context)
        case .shape(let shapeType):
            context.setLineWidth(path.lineWidth)
            drawShape(shapeType, points: path.points, in: context)
        case .marker:
            context.setLineWidth(path.lineWidth)
            drawStroke(points: path.points, in: context)
        default:
            context.setLineWidth(path.lineWidth)
            drawStroke(points: path.points, in: context)
        }
        
        context.restoreGState()
    }
    
    private func drawStrokeWithPressure(_ path: DrawingPath, in context: CGContext) {
        guard path.points.count > 1 else { return }
        
        let points = path.points
        let pressures = path.pressurePoints
        
        // 使用贝塞尔曲线
        let bezierPath = UIBezierPath()
        bezierPath.move(to: points[0])
        
        for i in 0..<points.count - 1 {
            let point = points[i]
            let nextPoint = points[i + 1]
            let pressure = pressures[i]
            
            // 改进压力计算
            let baseWidth = path.lineWidth
            let minWidth = baseWidth * 0.3  // 最小宽度为基础宽度的30%
            let pressureEffect = pressure * (baseWidth - minWidth)
            let width = minWidth + pressureEffect
            
            context.setLineWidth(width)
            
            // 使用二次贝塞尔曲线实现平滑过渡
            let midPoint = CGPoint(
                x: (point.x + nextPoint.x) / 2,
                y: (point.y + nextPoint.y) / 2
            )
            
            bezierPath.addQuadCurve(to: midPoint, controlPoint: point)
        }
        
        // 添加最后一段
        if let lastPoint = points.last {
            bezierPath.addLine(to: lastPoint)
        }
        
        // 绘制路径
        context.addPath(bezierPath.cgPath)
        context.strokePath()
    }
    
    private func drawShape(_ type: ShapeType, points: [CGPoint], in context: CGContext) {
        guard points.count >= 2 else { return }
        let start = points[0]
        let end = points.last!
        
        switch type {
        case .parabola(let direction):
            drawParabola(from: start, to: end, in: context, direction: direction)
        case .rectangle:
            drawRectangle(from: start, to: end, in: context)
        case .circle:
            drawCircle(from: start, to: end, in: context)
        case .line:
            drawLine(from: start, to: end, in: context)
        case .arrow:
            drawArrow(from: start, to: end, in: context)
        case .coordinateAxis:
            drawCoordinateAxis(from: start, to: end, in: context)
        case .ellipse:
            drawEllipse(from: start, to: end, in: context)
        case .hyperbola(let hyperbolaType):
            drawHyperbola(from: start, to: end, in: context, hyperbolaType: hyperbolaType)
        case .cube:
            drawCube(from: start, to: end, in: context)
        case .cuboid:
            drawCuboid(from: start, to: end, in: context)
        case .cone:
            drawCone(from: start, to: end, in: context)
        case .cylinder:
            drawCylinder(from: start, to: end, in: context)
        case .dashed:
            drawDashedLine(from: start, to: end, in: context)
        }
    }
    
    // 添加各个形状的具体绘制方法
    private func drawRectangle(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        context.addRect(rect)
        context.strokePath()
    }
    
    private func drawCircle(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        let center = CGPoint(
            x: (start.x + end.x) / 2,
            y: (start.y + end.y) / 2
        )
        let radius = hypot(end.x - start.x, end.y - start.y) / 2
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()
    }
    
    private func drawLine(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
    }
    
    private func drawArrow(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        // 绘制主线
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        
        // 绘制箭头
        let angle = atan2(end.y - start.y, end.x - start.x)
        drawArrowHead(at: end, angle: angle, length: 20.0, arrowAngle: .pi / 6, in: context)
    }
    
    private func drawDashedLine(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        context.setLineDash(phase: 0, lengths: [10, 5])
        context.move(to: start)
        context.addLine(to: end)
        context.strokePath()
        context.setLineDash(phase: 0, lengths: [])
    }
    
    // 修改撤销方法
    public func undo() {
        guard currentHistoryIndex > 0 else { return }
        currentHistoryIndex -= 1
        paths = pathHistory[currentHistoryIndex]
        setNeedsDisplay()
        
        // 通知 ContentView 更新撤销重做状态
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUndoRedoState"), object: nil)
    }
    
    // 修改重做方法
    public func redo() {
        guard currentHistoryIndex < pathHistory.count - 1 else { return }
        currentHistoryIndex += 1
        paths = pathHistory[currentHistoryIndex]
        setNeedsDisplay()
        
        // 通知 ContentView 更新撤销重做状态
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUndoRedoState"), object: nil)
    }
    
    public func canUndo() -> Bool {
        return currentHistoryIndex > 0
    }
    
    public func canRedo() -> Bool {
        return currentHistoryIndex < pathHistory.count - 1
    }
    
    // 添加基础绘制方法
    private func drawStroke(points: [CGPoint], in context: CGContext) {
        guard !points.isEmpty else { return }
        
        context.beginPath()
        context.move(to: points[0])
        
        if points.count == 1 {
            context.addLine(to: points[0])
        } else {
            for point in points.dropFirst() {
                context.addLine(to: point)
            }
        }
        
        context.strokePath()
    }
    
    // 添加激光点绘制方法
    private func drawLaserDot(at point: CGPoint, in context: CGContext) {
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor.red.cgColor, UIColor.clear.cgColor] as CFArray,
            locations: [0, 1]
        )!
        
        context.drawRadialGradient(
            gradient,
            startCenter: point,
            startRadius: 0,
            endCenter: point,
            endRadius: 10,
            options: []
        )
    }
    
    // 修改压力平滑处理方法
    private func smoothPressure(_ rawPressure: CGFloat) -> CGFloat {
        // 添加新的压力值到缓冲区
        pressureBuffer.append(rawPressure)
        
        // 保持缓冲区大小
        if pressureBuffer.count > pressureBufferSize {
            pressureBuffer.removeFirst()
        }
        
        // 计算平均压力值
        let averagePressure = pressureBuffer.reduce(0, +) / CGFloat(pressureBuffer.count)
        
        // 使用指数平滑
        let smoothedPressure = lastPressure + (averagePressure - lastPressure) * pressureSmoothingFactor
        lastPressure = smoothedPressure
        
        // 确保压力值在合理范围内
        return min(max(smoothedPressure, 0.3), 1.0)
    }
    
    public func clearAll() {
        // 保存清除前的状态到历史记录
        pathHistory.removeLast(pathHistory.count - currentHistoryIndex - 1)
        pathHistory.append([])
        currentHistoryIndex += 1
        
        // 清除所有路径
        paths = []
        setNeedsDisplay()
        
        // 通知 ContentView 更新撤销重做状态
        NotificationCenter.default.post(name: NSNotification.Name("UpdateUndoRedoState"), object: nil)
    }
    
    // 在 DrawingView 类中添加以下方法
    private func drawCoordinateAxis(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        // 计算中心点
        let centerX = (start.x + end.x) / 2
        let centerY = (start.y + end.y) / 2
        
        // 绘制 X 轴
        context.move(to: CGPoint(x: start.x, y: centerY))
        context.addLine(to: CGPoint(x: end.x, y: centerY))
        context.strokePath()
        
        // 绘制 Y 轴
        context.move(to: CGPoint(x: centerX, y: start.y))
        context.addLine(to: CGPoint(x: centerX, y: end.y))
        context.strokePath()
        
        // 绘制箭头
        drawArrowHead(at: CGPoint(x: end.x, y: centerY), angle: 0, length: 10, arrowAngle: .pi/6, in: context)
        drawArrowHead(at: CGPoint(x: centerX, y: start.y), angle: -.pi/2, length: 10, arrowAngle: .pi/6, in: context)
    }
    
    private func drawEllipse(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        let rect = CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
        context.addEllipse(in: rect)
        context.strokePath()
    }
    
    private func drawHyperbola(from start: CGPoint, to end: CGPoint, in context: CGContext, hyperbolaType: HyperbolaType) {
        let centerX = (start.x + end.x) / 2
        let centerY = (start.y + end.y) / 2
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        
        // 确保宽度和高度不为0
        guard width > 0 && height > 0 else { return }
        
        // 保存当前绘图状态
        context.saveGState()
        
        // 1. 绘制坐标轴
        context.setLineDash(phase: 0, lengths: [])
        
        // X轴
        context.move(to: CGPoint(x: start.x, y: centerY))
        context.addLine(to: CGPoint(x: end.x, y: centerY))
        
        // Y轴
        context.move(to: CGPoint(x: centerX, y: start.y))
        context.addLine(to: CGPoint(x: centerX, y: end.y))
        
        context.strokePath()
        
        // 2. 绘制渐近线
        context.setLineDash(phase: 0, lengths: [5, 5])  // 虚线
        
        let a: CGFloat
        let b: CGFloat
        
        switch hyperbolaType {
        case .xAxis:
            a = width / 4  // 实轴长的一半
            b = height / 4 // 虚轴长的一半
            
            // 渐近线方程：y = ±(b/a)x
            let slope = b / a
            
            // 绘制两条渐近线
            context.move(to: CGPoint(x: start.x, y: centerY - slope * (centerX - start.x)))
            context.addLine(to: CGPoint(x: end.x, y: centerY + slope * (end.x - centerX)))
            
            context.move(to: CGPoint(x: start.x, y: centerY + slope * (centerX - start.x)))
            context.addLine(to: CGPoint(x: end.x, y: centerY - slope * (end.x - centerX)))
            
            context.strokePath()
            
            // 3. 绘制双曲线
            context.setLineDash(phase: 0, lengths: [])  // 实线
            
            // 右上支
            context.beginPath()
            var firstPoint = true
            for x in stride(from: centerX + a, through: end.x, by: width/CGFloat(200)) {
                let dx = x - centerX
                let y = centerY + b * sqrt(dx * dx / (a * a) - 1)
                if firstPoint {
                    context.move(to: CGPoint(x: x, y: y))
                    firstPoint = false
                } else {
                    context.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.strokePath()
            
            // 右下支
            context.beginPath()
            firstPoint = true
            for x in stride(from: centerX + a, through: end.x, by: width/CGFloat(200)) {
                let dx = x - centerX
                let y = centerY - b * sqrt(dx * dx / (a * a) - 1)
                if firstPoint {
                    context.move(to: CGPoint(x: x, y: y))
                    firstPoint = false
                } else {
                    context.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.strokePath()
            
            // 左上支
            context.beginPath()
            firstPoint = true
            for x in stride(from: centerX - a, through: start.x, by: -width/CGFloat(200)) {
                let dx = x - centerX
                let y = centerY + b * sqrt(dx * dx / (a * a) - 1)
                if firstPoint {
                    context.move(to: CGPoint(x: x, y: y))
                    firstPoint = false
                } else {
                    context.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.strokePath()
            
            // 左下支
            context.beginPath()
            firstPoint = true
            for x in stride(from: centerX - a, through: start.x, by: -width/CGFloat(200)) {
                let dx = x - centerX
                let y = centerY - b * sqrt(dx * dx / (a * a) - 1)
                if firstPoint {
                    context.move(to: CGPoint(x: x, y: y))
                    firstPoint = false
                } else {
                    context.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.strokePath()
            
        case .yAxis:
            a = height / 4  // 实轴长的一半
            b = width / 4   // 虚轴长的一半
            
            // 渐近线方程：y = ±(a/b)x
            let slope = a / b
            
            // 绘制两条渐近线
            context.move(to: CGPoint(x: start.x, y: centerY - slope * (centerX - start.x)))
            context.addLine(to: CGPoint(x: end.x, y: centerY + slope * (end.x - centerX)))
            
            context.move(to: CGPoint(x: start.x, y: centerY + slope * (centerX - start.x)))
            context.addLine(to: CGPoint(x: end.x, y: centerY - slope * (end.x - centerX)))
            
            context.strokePath()
            
            // 3. 绘制双曲线
            context.setLineDash(phase: 0, lengths: [])  // 实线
            
            // 上右支
            context.beginPath()
            var firstPoint = true
            for y in stride(from: centerY + a, through: end.y, by: height/CGFloat(200)) {
                let dy = y - centerY
                let x = centerX + b * sqrt(dy * dy / (a * a) - 1)
                if firstPoint {
                    context.move(to: CGPoint(x: x, y: y))
                    firstPoint = false
                } else {
                    context.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.strokePath()
            
            // 上左支
            context.beginPath()
            firstPoint = true
            for y in stride(from: centerY + a, through: end.y, by: height/CGFloat(200)) {
                let dy = y - centerY
                let x = centerX - b * sqrt(dy * dy / (a * a) - 1)
                if firstPoint {
                    context.move(to: CGPoint(x: x, y: y))
                    firstPoint = false
                } else {
                    context.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.strokePath()
            
            // 下右支
            context.beginPath()
            firstPoint = true
            for y in stride(from: centerY - a, through: start.y, by: -height/CGFloat(200)) {
                let dy = y - centerY
                let x = centerX + b * sqrt(dy * dy / (a * a) - 1)
                if firstPoint {
                    context.move(to: CGPoint(x: x, y: y))
                    firstPoint = false
                } else {
                    context.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.strokePath()
            
            // 下左支
            context.beginPath()
            firstPoint = true
            for y in stride(from: centerY - a, through: start.y, by: -height/CGFloat(200)) {
                let dy = y - centerY
                let x = centerX - b * sqrt(dy * dy / (a * a) - 1)
                if firstPoint {
                    context.move(to: CGPoint(x: x, y: y))
                    firstPoint = false
                } else {
                    context.addLine(to: CGPoint(x: x, y: y))
                }
            }
            context.strokePath()
        }
        
        // 恢复绘图状态
        context.restoreGState()
    }
    
    private func drawParabola(from start: CGPoint, to end: CGPoint, in context: CGContext, direction: ParabolaDirection) {
        let centerX = (start.x + end.x) / 2
        let centerY = (start.y + end.y) / 2
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        
        // 确保宽度和高度不为0
        guard width > 0 && height > 0 else { return }
        
        var points: [CGPoint] = []
        let steps = 100 // 增加点的数量使曲线更平滑
        
        switch direction {
        case .up:
            let a = 4 * height / (width * width)
            for x in stride(from: start.x, through: end.x, by: max(width/CGFloat(steps), 1)) {
                let dx = x - centerX
                let y = centerY - a * dx * dx
                points.append(CGPoint(x: x, y: y))
            }
            
        case .down:
            let a = 4 * height / (width * width)
            for x in stride(from: start.x, through: end.x, by: max(width/CGFloat(steps), 1)) {
                let dx = x - centerX
                let y = centerY + a * dx * dx
                points.append(CGPoint(x: x, y: y))
            }
            
        case .left:
            let a = 4 * width / (height * height)
            for y in stride(from: start.y, through: end.y, by: max(height/CGFloat(steps), 1)) {
                let dy = y - centerY
                let x = centerX - a * dy * dy
                points.append(CGPoint(x: x, y: y))
            }
            
        case .right:
            let a = 4 * width / (height * height)
            for y in stride(from: start.y, through: end.y, by: max(height/CGFloat(steps), 1)) {
                let dy = y - centerY
                let x = centerX + a * dy * dy
                points.append(CGPoint(x: x, y: y))
            }
        }
        
        // 确保有足够的点来绘制
        guard points.count >= 2 else { return }
        
        // 绘制抛物线
        context.beginPath()
        context.move(to: points[0])
        for point in points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }
    
    private func drawCube(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        let size = min(abs(end.x - start.x), abs(end.y - start.y))
        let offset = size * 0.3  // 透视偏移量
        
        // 保存当前绘图状态
        context.saveGState()
        
        // 先绘制9条实线
        context.setLineDash(phase: 0, lengths: [])
        
        // 1. 前面的正方形（4条线）
        context.move(to: start)
        context.addLine(to: CGPoint(x: start.x + size, y: start.y))
        context.addLine(to: CGPoint(x: start.x + size, y: start.y + size))
        context.addLine(to: CGPoint(x: start.x, y: start.y + size))
        context.addLine(to: start)
        
        // 2. 右侧面的三条边
        // 顶部连接线
        context.move(to: CGPoint(x: start.x + size, y: start.y))
        context.addLine(to: CGPoint(x: start.x + size + offset, y: start.y - offset))
        
        // 右侧垂直线
        context.move(to: CGPoint(x: start.x + size + offset, y: start.y - offset))
        context.addLine(to: CGPoint(x: start.x + size + offset, y: start.y + size - offset))
        
        // 底部连接线
        context.move(to: CGPoint(x: start.x + size, y: start.y + size))
        context.addLine(to: CGPoint(x: start.x + size + offset, y: start.y + size - offset))
        
        // 3. 顶面的两条边
        context.move(to: start)
        context.addLine(to: CGPoint(x: start.x + offset, y: start.y - offset))
        
        context.move(to: CGPoint(x: start.x + offset, y: start.y - offset))
        context.addLine(to: CGPoint(x: start.x + size + offset, y: start.y - offset))
        
        context.strokePath()
        
        // 然后绘制3条虚线
        context.setLineDash(phase: 0, lengths: [5, 5])
        
        // 1. 左面底边（从左下角到后方）
        context.move(to: CGPoint(x: start.x, y: start.y + size))
        context.addLine(to: CGPoint(x: start.x + offset, y: start.y + size - offset))
        
        // 2. 后面底边（后方的横线）
        context.move(to: CGPoint(x: start.x + offset, y: start.y + size - offset))
        context.addLine(to: CGPoint(x: start.x + size + offset, y: start.y + size - offset))
        
        // 3. 后面左边（后方的竖线）
        context.move(to: CGPoint(x: start.x + offset, y: start.y - offset))
        context.addLine(to: CGPoint(x: start.x + offset, y: start.y + size - offset))
        
        context.strokePath()
        
        // 恢复绘图状态
        context.restoreGState()
    }
    
    private func drawCuboid(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        let depth = min(width, height) * 0.3
        
        // 保存当前绘图状态
        context.saveGState()
        
        // 先绘制9条实线
        context.setLineDash(phase: 0, lengths: [])
        
        // 1. 前面的矩形（4条线）
        context.move(to: start)
        context.addLine(to: CGPoint(x: start.x + width, y: start.y))
        context.addLine(to: CGPoint(x: start.x + width, y: start.y + height))
        context.addLine(to: CGPoint(x: start.x, y: start.y + height))
        context.closePath()
        
        // 2. 右侧面的三条边
        // 顶部连接线
        context.move(to: CGPoint(x: start.x + width, y: start.y))
        context.addLine(to: CGPoint(x: start.x + width + depth, y: start.y - depth))
        
        // 右侧垂直线
        context.move(to: CGPoint(x: start.x + width + depth, y: start.y - depth))
        context.addLine(to: CGPoint(x: start.x + width + depth, y: start.y + height - depth))
        
        // 底部连接线
        context.move(to: CGPoint(x: start.x + width, y: start.y + height))
        context.addLine(to: CGPoint(x: start.x + width + depth, y: start.y + height - depth))
        
        // 3. 顶面的两条边
        context.move(to: start)
        context.addLine(to: CGPoint(x: start.x + depth, y: start.y - depth))
        
        context.move(to: CGPoint(x: start.x + depth, y: start.y - depth))
        context.addLine(to: CGPoint(x: start.x + width + depth, y: start.y - depth))
        
        context.strokePath()
        
        // 然后绘制3条虚线
        context.setLineDash(phase: 0, lengths: [5, 5])
        
        // 1. 左面底边（从左下角到后方）
        context.move(to: CGPoint(x: start.x, y: start.y + height))
        context.addLine(to: CGPoint(x: start.x + depth, y: start.y + height - depth))
        
        // 2. 后面底边（后方的横线）
        context.move(to: CGPoint(x: start.x + depth, y: start.y + height - depth))
        context.addLine(to: CGPoint(x: start.x + width + depth, y: start.y + height - depth))
        
        // 3. 后面左边（后方的竖线）
        context.move(to: CGPoint(x: start.x + depth, y: start.y - depth))
        context.addLine(to: CGPoint(x: start.x + depth, y: start.y + height - depth))
        
        context.strokePath()
        
        // 恢复绘图状态
        context.restoreGState()
    }
    
    private func drawCone(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        let centerX = (start.x + end.x) / 2
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        
        // 绘制底部椭圆
        let bottomRect = CGRect(
            x: start.x,
            y: start.y + height - width/4,
            width: width,
            height: width/2
        )
        context.addEllipse(in: bottomRect)
        context.strokePath()
        
        // 绘制从顶点到底部椭圆的两条线
        let topPoint = CGPoint(x: centerX, y: start.y)
        context.move(to: topPoint)
        context.addLine(to: CGPoint(x: start.x, y: start.y + height))
        context.move(to: topPoint)
        context.addLine(to: CGPoint(x: end.x, y: start.y + height))
        context.strokePath()
    }
    
    private func drawCylinder(from start: CGPoint, to end: CGPoint, in context: CGContext) {
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)
        
        // 绘制顶部椭圆
        let topRect = CGRect(
            x: start.x,
            y: start.y,
            width: width,
            height: width/2
        )
        context.addEllipse(in: topRect)
        
        // 绘制底部椭圆
        let bottomRect = CGRect(
            x: start.x,
            y: start.y + height - width/2,
            width: width,
            height: width/2
        )
        context.addEllipse(in: bottomRect)
        
        // 绘制连接线
        context.move(to: CGPoint(x: start.x, y: start.y + width/4))
        context.addLine(to: CGPoint(x: start.x, y: start.y + height - width/4))
        context.move(to: CGPoint(x: end.x, y: start.y + width/4))
        context.addLine(to: CGPoint(x: end.x, y: start.y + height - width/4))
        
        context.strokePath()
    }
    
    private func drawArrowHead(at point: CGPoint, angle: CGFloat, length: CGFloat, arrowAngle: CGFloat, in context: CGContext) {
        let x = point.x
        let y = point.y
        
        let x1 = x - length * cos(angle + arrowAngle)
        let y1 = y - length * sin(angle + arrowAngle)
        let x2 = x - length * cos(angle - arrowAngle)
        let y2 = y - length * sin(angle - arrowAngle)
        
        context.move(to: point)
        context.addLine(to: CGPoint(x: x1, y: y1))
        context.move(to: point)
        context.addLine(to: CGPoint(x: x2, y: y2))
        context.strokePath()
    }
}

// 添加 UIPencilInteraction 代理支持
extension DrawingView: UIPencilInteractionDelegate {
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        // 可以在这里处理 Apple Pencil 的双击等手势
    }
}

// 修改 DrawingCanvas 实现
struct DrawingCanvas: UIViewRepresentable {
    @Binding var tool: DrawingTool
    @Binding var selectedColor: Color
    
    func makeUIView(context: Context) -> DrawingView {
        let view = DrawingView.shared
        view.coordinator = context.coordinator
        view.backgroundColor = .clear  // 设置为透明背景
        view.isOpaque = false  // 设置为非不透明
        return view
    }
    
    func updateUIView(_ uiView: DrawingView, context: Context) {
        uiView.tool = tool
        uiView.isUserInteractionEnabled = true
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject {
        var parent: DrawingCanvas
        
        init(_ parent: DrawingCanvas) {
            self.parent = parent
        }
        
        func getToolAttributes() -> (UIColor, CGFloat, CGFloat) {
            let settings = ToolSettingsManager.shared.getSettings(for: parent.tool)
            return (UIColor(settings.color), settings.lineWidth, settings.opacity)
        }
    }
}

// 修改 CameraView 实现
struct CameraView: UIViewRepresentable {
    static let shared = CameraViewModel()
    @ObservedObject private var viewModel = CameraView.shared
    static var captureSession: AVCaptureSession?
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        // 创建预览层
        let previewLayer = AVCaptureVideoPreviewLayer()
        // 修改：确保预览层填满整个视图
        previewLayer.frame = view.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        // 添加：自动调整预览层大小
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        
        // 初始化和配置 captureSession
        if CameraView.captureSession == nil {
            CameraView.captureSession = AVCaptureSession()
            // 添加：检查相机权限
            checkCameraPermission { granted in
                if granted {
                    setupCamera(previewLayer)
                }
            }
        } else {
            previewLayer.session = CameraView.captureSession
        }
        
        return view
    }
    
    // 添加：权限检查方法
    private func checkCameraPermission(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }
    
    private func setupCamera(_ previewLayer: AVCaptureVideoPreviewLayer) {
        guard let captureSession = CameraView.captureSession else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.beginConfiguration()
            
            // 清除现有输入
            captureSession.inputs.forEach { captureSession.removeInput($0) }
            
            // 配置内置摄像头
            if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                do {
                    let input = try AVCaptureDeviceInput(device: device)
                    if captureSession.canAddInput(input) {
                        captureSession.addInput(input)
                        print("Camera input added successfully")
                    }
                } catch {
                    print("Camera setup error: \(error.localizedDescription)")
                }
            }
            
            // 设置高质量预设并锁定为 4:3 比例
            if captureSession.canSetSessionPreset(.photo) {
                captureSession.sessionPreset = .photo  // 使用 photo preset 来确保 4:3 比例
            }
            
            captureSession.commitConfiguration()
            
            // 在主线程更新 UI
            DispatchQueue.main.async {
                previewLayer.session = captureSession
                
                // 锁定摄像头方向为横向
                if let connection = previewLayer.connection {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .landscapeRight  // 锁定为横向
                    }
                }
                
                // 确保预览层填满整个视图
                previewLayer.videoGravity = .resizeAspectFill
                
                // 启动摄像头会话
                if !captureSession.isRunning {
                    captureSession.startRunning()
                }
            }
        }
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let previewLayer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            DispatchQueue.main.async {
                previewLayer.frame = uiView.bounds
                // 保持方向锁定
                if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
                    connection.videoOrientation = .landscapeRight  // 锁定为横向
                }
            }
        }
    }
}

// 修改 CameraViewModel
class CameraViewModel: ObservableObject {
    @Published var isCameraOn = true {
        didSet {
            if isCameraOn {
                startCamera()
            } else {
                stopCamera()
            }
        }
    }
    @Published var isUsingContinuityCamera = false
    
    func startCamera() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let captureSession = CameraView.captureSession,
                  !captureSession.isRunning else { return }
            captureSession.startRunning()
        }
    }
    
    func stopCamera() {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let captureSession = CameraView.captureSession,
                  captureSession.isRunning else { return }
            captureSession.stopRunning()
        }
    }
    
    // 添加切换摄像头的方法
    func switchCamera() {
        guard let captureSession = CameraView.captureSession else { return }
        
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.beginConfiguration()
            
            // 移除当前输入
            captureSession.inputs.forEach { captureSession.removeInput($0) }
            
            if self.isUsingContinuityCamera {
                // 切换到内置摄像头
                if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                    do {
                        let input = try AVCaptureDeviceInput(device: device)
                        if captureSession.canAddInput(input) {
                            captureSession.addInput(input)
                            self.isUsingContinuityCamera = false
                        }
                    } catch {
                        print("Error switching to built-in camera: \(error.localizedDescription)")
                    }
                }
            } else if #available(iOS 16.0, *) {
                // 切换到 Continuity Camera
                let discoverySession = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.continuityCamera],
                    mediaType: .video,
                    position: .unspecified
                )
                
                if let continuityDevice = discoverySession.devices.first {
                    do {
                        let input = try AVCaptureDeviceInput(device: continuityDevice)
                        if captureSession.canAddInput(input) {
                            captureSession.addInput(input)
                            self.isUsingContinuityCamera = true
                        }
                    } catch {
                        print("Error switching to Continuity Camera: \(error.localizedDescription)")
                    }
                }
            }
            
            captureSession.commitConfiguration()
        }
    }
}

#Preview {
    ContentView()
}

// 添加 UTType 扩展
extension UTType {
    static var powerpoint: UTType {
        UTType(filenameExtension: "ppt")!
    }
    
    static var presentationPackage: UTType {
        UTType(filenameExtension: "pptx")!
    }
}

// 在文件末尾添加新的 ScreenRecorder 类
class ScreenRecorder: NSObject, ObservableObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let shared = ScreenRecorder()
    @Published private(set) var isRecording = false
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    private var audioSession: AVCaptureSession?
    private var displayLink: CADisplayLink?
    private var recordingStartTime: TimeInterval = 0
    private var outputURL: URL?
    private var assetWriterPixelBufferInput: AVAssetWriterInputPixelBufferAdaptor?
    private var frameCount: Int = 0  // 添加帧计数器
    
    private override init() {
        super.init()
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            // 配置音频会话
            let avAudioSession = AVAudioSession.sharedInstance()
            try avAudioSession.setCategory(.playAndRecord, mode: .default)
            try avAudioSession.setActive(true)
            
            // 创建捕获会话
            audioSession = AVCaptureSession()
            
            // 配置音频输入
            guard let audioDevice = AVCaptureDevice.default(for: .audio) else { return }
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            
            // 配置音频输出
            audioDataOutput = AVCaptureAudioDataOutput()
            audioDataOutput?.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audio.queue"))
            
            // 添加输入输出到会话
            if let audioSession = audioSession {
                if audioSession.canAddInput(audioInput) {
                    audioSession.addInput(audioInput)
                }
                if let audioDataOutput = audioDataOutput,
                   audioSession.canAddOutput(audioDataOutput) {
                    audioSession.addOutput(audioDataOutput)
                }
            }
        } catch {
            print("Error setting up audio session: \(error.localizedDescription)")
        }
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        // 重置帧计数器
        frameCount = 0
        
        // 创建临时文件URL，使用 mov 格式而不是 mp4
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "recording_\(Date().timeIntervalSince1970).mov"
        outputURL = tempDir.appendingPathComponent(fileName)
        
        guard let outputURL = outputURL else { return }
        
        do {
            // 删除可能存在的旧文件
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            
            // 创建 AVAssetWriter，使用 mov 格式
            videoWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
            
            // 修改视频设置以确保与 iPad 相册兼容
            let screenSize = UIScreen.main.bounds.size
            let videoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(screenSize.width),
                AVVideoHeightKey: Int(screenSize.height),
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 2500000,
                    AVVideoMaxKeyFrameIntervalKey: 30,
                    AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                    AVVideoExpectedSourceFrameRateKey: 30
                ]
            ]
            
            // 音频设置
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 128000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            
            // 创建输入
            videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            
            guard let videoWriterInput = videoWriterInput,
                  let audioWriterInput = audioWriterInput else {
                throw NSError(domain: "ScreenRecorder", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Failed to create writer inputs"])
            }
            
            // 创建 pixel buffer adaptor
            let sourcePixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                kCVPixelBufferWidthKey as String: Int(screenSize.width),
                kCVPixelBufferHeightKey as String: Int(screenSize.height)
            ]
            
            assetWriterPixelBufferInput = AVAssetWriterInputPixelBufferAdaptor(
                assetWriterInput: videoWriterInput,
                sourcePixelBufferAttributes: sourcePixelBufferAttributes
            )
            
            videoWriterInput.expectsMediaDataInRealTime = true
            audioWriterInput.expectsMediaDataInRealTime = true
            
            // 添加输入前检查
            guard videoWriter?.canAdd(videoWriterInput) == true,
                  videoWriter?.canAdd(audioWriterInput) == true else {
                throw NSError(domain: "ScreenRecorder", code: -1,
                            userInfo: [NSLocalizedDescriptionKey: "Cannot add inputs to writer"])
            }
            
            videoWriter?.add(videoWriterInput)
            videoWriter?.add(audioWriterInput)
            
            // 开始写入
            videoWriter?.startWriting()
            videoWriter?.startSession(atSourceTime: CMTime.zero)
            recordingStartTime = CACurrentMediaTime()
            
            // 启动音频会话
            audioSession?.startRunning()
            
            // 设置显示链接
            displayLink = CADisplayLink(target: self, selector: #selector(captureFrame))
            displayLink?.preferredFramesPerSecond = 30
            displayLink?.add(to: .main, forMode: .common)
            
            isRecording = true
            recordingStartTime = CACurrentMediaTime()
            print("Recording started successfully")
            
        } catch {
            print("Error starting recording: \(error.localizedDescription)")
        }
    }
    
    // 实现音频代理方法
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRecording,
              let audioWriterInput = audioWriterInput,
              audioWriterInput.isReadyForMoreMediaData else {
            return
        }
        
        // 获取音频样本的原始时间戳
        var audioTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        // 调整音频时间戳以匹配视频时间
        if audioTime.seconds > 0 {
            audioTime = CMTime(seconds: audioTime.seconds - recordingStartTime, preferredTimescale: audioTime.timescale)
        }
        
        // 创建新的音频样本缓冲区，使用调整后的时间戳
        if let adjustedBuffer = createAdjustedSampleBuffer(from: sampleBuffer, withPresentationTime: audioTime) {
            audioWriterInput.append(adjustedBuffer)
        }
    }
    
    // 添加辅助方法来创建调整后的音频样本缓冲区
    private func createAdjustedSampleBuffer(from original: CMSampleBuffer, withPresentationTime time: CMTime) -> CMSampleBuffer? {
        var adjustedBuffer: CMSampleBuffer?
        
        guard let audioBufferFormat = CMSampleBufferGetFormatDescription(original),
              let audioData = CMSampleBufferGetDataBuffer(original) else {
            return nil
        }
        
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(original),
            presentationTimeStamp: time,
            decodeTimeStamp: time
        )
        
        CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: original,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &adjustedBuffer
        )
        
        return adjustedBuffer
    }
    
    @objc private func captureFrame() {
        guard let videoWriter = videoWriter,
              videoWriter.status == .writing,
              let videoWriterInput = videoWriterInput,
              let pixelBufferAdaptor = assetWriterPixelBufferInput,
              videoWriterInput.isReadyForMoreMediaData else {
            print("Writer not ready for video data")
            return
        }
        
        // 使用帧计数器计算准确的时间戳
        let frameTime = CMTime(value: Int64(frameCount), timescale: 30)
        frameCount += 1
        
        autoreleasepool {
            guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else { return }
            let bounds = window.bounds
            
            UIGraphicsBeginImageContextWithOptions(bounds.size, true, UIScreen.main.scale)
            defer { UIGraphicsEndImageContext() }
            
            // 先填充白色背景
            UIColor.white.setFill()
            UIRectFill(bounds)
            
            // 渲染窗口内容
            window.drawHierarchy(in: bounds, afterScreenUpdates: false)
            
            guard let image = UIGraphicsGetImageFromCurrentImageContext(),
                  let pixelBuffer = image.toPixelBuffer() else {
                print("Failed to create pixel buffer")
                return
            }
            
            if !pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: frameTime) {
                print("Failed to append pixel buffer: \(videoWriter.status.rawValue), \(videoWriter.error?.localizedDescription ?? "Unknown error")")
            }
        }
    }
    
    func stopRecording(completion: @escaping (URL?) -> Void) {
        guard isRecording else {
            completion(nil)
            return
        }
        
        isRecording = false
        frameCount = 0  // 重置帧计数器
        
        // 停止显示链接
        displayLink?.invalidate()
        displayLink = nil
        
        // 停止音频会话
        audioSession?.stopRunning()
        
        // 标记输入完成
        videoWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()
        
        // 完成写入
        videoWriter?.finishWriting { [weak self] in
            DispatchQueue.main.async {
                guard let self = self,
                      let outputURL = self.outputURL,
                      FileManager.default.fileExists(atPath: outputURL.path) else {
                    print("Error: Video file not found")
                    completion(nil)
                    return
                }
                
                // 检查视频文件大小
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
                    let fileSize = attributes[.size] as? Int64 ?? 0
                    print("Video file size: \(fileSize) bytes")
                    
                    if fileSize > 0 {
                        // 确保视频文件完整性
                        let asset = AVAsset(url: outputURL)
                        if asset.duration.seconds > 0 {
                            completion(outputURL)
                        } else {
                            print("Error: Invalid video duration")
                            completion(nil)
                        }
                    } else {
                        print("Error: Video file is empty")
                        completion(nil)
                    }
                } catch {
                    print("Error checking video file: \(error.localizedDescription)")
                    completion(nil)
                }
                
                // 清理资源
                self.videoWriter = nil
                self.videoWriterInput = nil
                self.audioWriterInput = nil
                self.assetWriterPixelBufferInput = nil
                self.outputURL = nil
            }
        }
    }
}

// 添加 UIImage 扩展，用于转换为 PixelBuffer
extension UIImage {
    func toPixelBuffer() -> CVPixelBuffer? {
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                    kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                       Int(self.size.width),
                                       Int(self.size.height),
                                       kCVPixelFormatType_32ARGB,
                                       attrs,
                                       &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pixelData,
                                    width: Int(self.size.width),
                                    height: Int(self.size.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                    space: rgbColorSpace,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            return nil
        }
        
        context.translateBy(x: 0, y: self.size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context)
        self.draw(in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
        UIGraphicsPopContext()
        
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return buffer
    }
}


