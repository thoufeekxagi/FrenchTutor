import SwiftUI

enum Passeport {
    // Palette — pastel take on the French flag (bleu / blanc / rouge)
    static let ink = Color(red: 27/255, green: 42/255, blue: 74/255)          // #1B2A4A pastel navy
    static let inkSoft = Color(red: 37/255, green: 55/255, blue: 92/255)      // #25375C
    static let parchment = Color(red: 250/255, green: 249/255, blue: 246/255) // #FAF9F6 soft blanc
    static let parchmentDim = Color(red: 237/255, green: 241/255, blue: 247/255) // #EDF1F7 pastel blue-white
    static let card = Color(red: 255/255, green: 255/255, blue: 255/255)      // #FFFFFF
    static let maroon = Color(red: 200/255, green: 67/255, blue: 62/255)      // #C8433E pastel rouge
    static let maroonDeep = Color(red: 168/255, green: 50/255, blue: 41/255)  // #A83229
    static let brass = Color(red: 107/255, green: 143/255, blue: 196/255)     // #6B8FC4 pastel bleu accent
    static let slate = Color(red: 149/255, green: 160/255, blue: 178/255)     // #95A0B2
    static let slateDim = Color(red: 96/255, green: 108/255, blue: 128/255)   // #606C80
    static let text = Color(red: 27/255, green: 42/255, blue: 74/255)         // #1B2A4A
    static let hairline = Color(red: 27/255, green: 42/255, blue: 74/255).opacity(0.12)
    static let hairlineLight = Color(red: 250/255, green: 249/255, blue: 246/255).opacity(0.16)

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
