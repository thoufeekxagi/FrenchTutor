import SwiftUI

/// Reusable conjugation grid with a per-row TTS button. Optionally highlights a row
/// (used by GrammarLessonView while narrating).
struct ConjugationTableView: View {
    let verb: String
    let group: String
    let rows: [ConjRow]
    var highlightedPronoun: String? = nil
    var onSpeak: ((String) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verb)
                    .font(Passeport.display(15, weight: .medium))
                    .foregroundColor(Passeport.maroon)
                Text("(\(group))")
                    .font(Passeport.mono(11))
                    .foregroundColor(Passeport.slateDim)
                Spacer()
            }
            VStack(spacing: 0) {
                ForEach(rows) { row in
                    HStack {
                        Text(row.pronoun)
                            .font(Passeport.body(12.5))
                            .foregroundColor(Passeport.slateDim)
                            .frame(width: 70, alignment: .leading)
                        Text(row.form)
                            .font(Passeport.body(13.5, weight: .medium))
                            .foregroundColor(Passeport.text)
                        Spacer()
                        Button {
                            onSpeak?("\(row.pronoun) \(row.form)")
                        } label: {
                            Image(systemName: "speaker.wave.2")
                                .font(.system(size: 11))
                                .foregroundColor(Passeport.brass)
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        row.pronoun == highlightedPronoun
                            ? Passeport.brass.opacity(0.12)
                            : Color.clear
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .passeportCard(padding: 12)
    }
}

/// Compact irregular-verb table: present-tense forms across the six pronouns + passé composé.
struct IrregularVerbTableView: View {
    let verb: IrregularVerb
    var onSpeak: ((String) -> Void)? = nil

    private let pronouns = ["je", "tu", "il/elle", "nous", "vous", "ils/elles"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(verb.verb)
                    .font(Passeport.display(15, weight: .medium))
                    .foregroundColor(Passeport.maroon)
                Text("— \(verb.en)")
                    .font(Passeport.mono(11))
                    .foregroundColor(Passeport.slateDim)
                Spacer()
                Button {
                    onSpeak?(verb.verb)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 12))
                        .foregroundColor(Passeport.brass)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(zip(pronouns, verb.present)), id: \.0) { pronoun, form in
                    VStack(spacing: 1) {
                        Text(pronoun)
                            .font(Passeport.mono(8.5))
                            .foregroundColor(Passeport.slateDim)
                        Text(form)
                            .font(Passeport.body(11.5, weight: .medium))
                            .foregroundColor(Passeport.text)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Passé composé: \(verb.passeCompose)")
                .font(Passeport.mono(10.5))
                .foregroundColor(Passeport.slateDim)
        }
        .passeportCard(padding: 12)
    }
}
