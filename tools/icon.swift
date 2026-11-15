import SwiftUI

// Draws the app icon: a notch with agent dots and the glow under it. ./tools/icon.sh
struct Icon: View {
    var body: some View {
        let violet = Color(red: 0.55, green: 0.50, blue: 0.98)
        let teal = Color(red: 0.36, green: 0.85, blue: 0.70)
        let orange = Color(red: 0.98, green: 0.64, blue: 0.18)
        let green = Color(red: 0.55, green: 0.85, blue: 0.36)
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.11, blue: 0.24), Color(red: 0.03, green: 0.03, blue: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
            RadialGradient(colors: [violet.opacity(0.55), teal.opacity(0.15), .clear], center: .init(x: 0.5, y: 0.42),
                           startRadius: 0, endRadius: 360)
                .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            VStack(spacing: 0) {
                ZStack {
                    Path { p in
                        let (w, h, r): (CGFloat, CGFloat, CGFloat) = (440, 190, 70)
                        p.move(to: .zero)
                        p.addLine(to: CGPoint(x: w, y: 0))
                        p.addLine(to: CGPoint(x: w, y: h - r))
                        p.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
                        p.addLine(to: CGPoint(x: r, y: h))
                        p.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
                        p.closeSubpath()
                    }
                    .fill(.black)
                    HStack(spacing: 34) {
                        dot(orange)
                        dot(green)
                        dot(violet)
                    }
                    .offset(y: 8)
                }
                .frame(width: 440, height: 190)
                ZStack {
                    Capsule().fill(LinearGradient(colors: [violet, teal, green], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 400, height: 30).blur(radius: 26)
                    Capsule().fill(LinearGradient(colors: [violet, teal, green], startPoint: .leading, endPoint: .trailing))
                        .frame(width: 360, height: 8).blur(radius: 2)
                }
                .padding(.top, 18)
                VStack(alignment: .leading, spacing: 46) {
                    row(orange, 260)
                    row(violet, 330)
                    row(green, 210)
                }
                .padding(.top, 64)
                .padding(40)
                .frame(width: 520, alignment: .leading)
                Spacer()
            }
            .frame(width: 824, height: 824)
            .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 3)
        }
        .frame(width: 824, height: 824)
        .frame(width: 1024, height: 1024)
    }

    // Faint session rows: what the notch opens into.
    func row(_ color: Color, _ width: CGFloat) -> some View {
        HStack(spacing: 26) {
            Circle().fill(color.opacity(0.8)).frame(width: 30, height: 30).shadow(color: color.opacity(0.8), radius: 10)
            Capsule().fill(.white.opacity(0.16)).frame(width: width, height: 22)
        }
    }

    func dot(_ color: Color) -> some View {
        Circle().fill(color).frame(width: 58, height: 58).shadow(color: color, radius: 22)
    }
}

@main struct IconMain {
    @MainActor static func main() {
        let renderer = ImageRenderer(content: Icon())
        renderer.scale = 1
        let png = NSBitmapImageRep(data: renderer.nsImage!.tiffRepresentation!)!.representation(using: .png, properties: [:])!
        try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
