import SwiftUI

struct ProgressScreen: View {
    @State private var skills: [SkillProgress] = []
    @State private var checklist: [(id: String, title: String, done: Bool)] = []
    @State private var speakingMinutes = 0
    @State private var streak = 0

    private let store = LearningStore()
    private let storage = StorageService()

    var body: some View {
        NavigationStack {
            ZStack {
                Passeport.parchmentDim.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        paceCard
                        skillsCard
                        grammarCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Progress")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { reload() }
        }
    }

    private var paceCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            KickerText(text: "Pace check", color: Passeport.slateDim)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(streak)-day streak")
                        .font(Passeport.display(15, weight: .medium))
                        .foregroundColor(Passeport.text)
                    Text("\(speakingMinutes) min spoken with Marie so far")
                        .font(Passeport.body(11.5))
                        .foregroundColor(Passeport.slateDim)
                }
                Spacer()
                Image(systemName: "flame.fill")
                    .font(.system(size: 22))
                    .foregroundColor(streak > 0 ? Passeport.maroon : Passeport.slate)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private var skillsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Skills")
                .font(Passeport.display(16, weight: .medium))
                .foregroundColor(Passeport.text)

            ForEach(skills, id: \.name) { skill in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Image(systemName: skill.icon)
                            .font(.system(size: 12))
                            .foregroundColor(Passeport.maroon)
                            .frame(width: 18)
                        Text(skill.name)
                            .font(Passeport.body(12.5, weight: .medium))
                            .foregroundColor(Passeport.text)
                        Spacer()
                        Text("\(Int(skill.fraction * 100))%")
                            .font(Passeport.mono(11))
                            .foregroundColor(Passeport.slateDim)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Passeport.hairline)
                            Capsule()
                                .fill(Passeport.maroon)
                                .frame(width: max(4, geo.size.width * skill.fraction))
                        }
                    }
                    .frame(height: 6)
                    Text(skill.detail)
                        .font(Passeport.mono(9.5))
                        .foregroundColor(Passeport.slateDim)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private var grammarCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Grammar checklist")
                .font(Passeport.display(16, weight: .medium))
                .foregroundColor(Passeport.text)
                .padding(.bottom, 6)

            ForEach(Array(checklist.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Image(systemName: item.done ? "checkmark.seal.fill" : "seal")
                        .font(.system(size: 15))
                        .foregroundColor(item.done ? Passeport.brass : Passeport.slate)
                    Text(item.title)
                        .font(Passeport.body(13))
                        .foregroundColor(Passeport.text)
                    Spacer()
                }
                .padding(.vertical, 7)
                if index < checklist.count - 1 {
                    Divider().overlay(Passeport.hairline)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .passeportCard()
    }

    private func reload() {
        let progressService = ProgressService(store: store)
        skills = progressService.skillProgress()
        checklist = progressService.grammarChecklist()
        streak = progressService.streak()
        DispatchQueue.global(qos: .userInitiated).async {
            let sessions = storage.getAllSessions()
            let minutes = progressService.speakingMinutes(sessions: sessions)
            DispatchQueue.main.async { speakingMinutes = minutes }
        }
    }
}
