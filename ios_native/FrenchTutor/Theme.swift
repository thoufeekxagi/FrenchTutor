import SwiftUI

enum Passeport {
    // Palette
    static let ink = Color(red: 16/255, green: 25/255, blue: 43/255)          // #10192B
    static let inkSoft = Color(red: 24/255, green: 34/255, blue: 54/255)      // #182236
    static let parchment = Color(red: 246/255, green: 241/255, blue: 231/255) // #F6F1E7
    static let parchmentDim = Color(red: 239/255, green: 232/255, blue: 216/255) // #EFE8D8
    static let card = Color(red: 255/255, green: 254/255, blue: 251/255)      // #FFFEFB
    static let maroon = Color(red: 122/255, green: 37/255, blue: 48/255)      // #7A2530
    static let maroonDeep = Color(red: 92/255, green: 27/255, blue: 36/255)   // #5C1B24
    static let brass = Color(red: 184/255, green: 134/255, blue: 62/255)      // #B8863E
    static let slate = Color(red: 139/255, green: 147/255, blue: 161/255)     // #8B93A1
    static let slateDim = Color(red: 91/255, green: 100/255, blue: 114/255)   // #5B6472
    static let text = Color(red: 27/255, green: 34/255, blue: 48/255)         // #1B2230
    static let hairline = Color(red: 27/255, green: 34/255, blue: 48/255).opacity(0.12)
    static let hairlineLight = Color(red: 246/255, green: 241/255, blue: 231/255).opacity(0.16)

    // Typography
    static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

struct PasseportCard: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Passeport.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Passeport.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func passeportCard(padding: CGFloat = 16) -> some View {
        modifier(PasseportCard(padding: padding))
    }
}

struct PasseportPrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Passeport.body(15, weight: .medium))
            .foregroundColor(Passeport.parchment)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(configuration.isPressed ? Passeport.maroonDeep : Passeport.maroon)
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Small uppercase monospaced label used as kicker text above titles.
struct KickerText: View {
    let text: String
    var color: Color = Passeport.brass
    var body: some View {
        Text(text.uppercased())
            .font(Passeport.mono(10, weight: .medium))
            .kerning(0.8)
            .foregroundColor(color)
    }
}
