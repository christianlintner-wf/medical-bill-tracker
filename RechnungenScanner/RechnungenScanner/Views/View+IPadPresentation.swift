import SwiftUI

extension View {
    /// Forces a `.sheet` to present at full height on iPad (matching iPhone's
    /// default), while keeping the native swipe-to-dismiss gesture intact.
    /// No-op on iPhone.
    @ViewBuilder
    func iPadFullHeightSheet() -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            self.presentationDetents([.large])
        } else {
            self
        }
    }
}
