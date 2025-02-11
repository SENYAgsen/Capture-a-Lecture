import SwiftUI

struct ContentView: View {
    var body: some View {
        // 1. 绘制坐标轴
        context.setLineDash(phase: 0, lengths: [])
        
        // X轴
        context.move(to: CGPoint(x: start.x, y: centerY))
        context.addLine(to: CGPoint(x: end.x, y: centerY))
        
        // Y轴
        context.move(to: CGPoint(x: centerX, y: start.y))
        context.addLine(to: CGPoint(x: centerX, y: end.y))
        
        context.strokePath()
        
        // 添加箭头
        switch hyperbolaType {
        case .xAxis:
            // X轴正方向箭头
            drawArrowHead(at: CGPoint(x: end.x, y: centerY), angle: 0, length: 10, arrowAngle: .pi/6, in: context)
            // 外轴（X轴）正方向箭头
            drawArrowHead(at: CGPoint(x: end.x, y: centerY), angle: 0, length: 10, arrowAngle: .pi/6, in: context)
        case .yAxis:
            // X轴正方向箭头
            drawArrowHead(at: CGPoint(x: end.x, y: centerY), angle: 0, length: 10, arrowAngle: .pi/6, in: context)
            // 外轴（Y轴）正方向箭头
            drawArrowHead(at: CGPoint(x: centerX, y: start.y), angle: -.pi/2, length: 10, arrowAngle: .pi/6, in: context)
        }
        
        // 2. 绘制渐近线
        // ... existing code ...
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
} 