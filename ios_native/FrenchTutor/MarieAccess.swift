import SwiftUI

/// A phone-icon toolbar button that reaches Marie from anywhere in a lab — not just at
/// the end of a session. `onTap` should stop/deactivate any local speech service before
/// `showMarie` flips true (single-owner audio-session rule), and the caller is responsible
/// for attaching the matching `.fullScreenCover(isPresented: $showMarie) { SessionView(...) }`.
struct MarieToolbarButton: ToolbarContent {
    @Binding var showMarie: Bool
    var onTap: () -> Void = {}

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                onTap()
                showMarie = true
            } label: {
                Image(systemName: "phone.fill")
                    .foregroundColor(Passeport.maroon)
            }
        }
    }
}
