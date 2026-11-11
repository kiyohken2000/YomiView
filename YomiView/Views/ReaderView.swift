import SwiftUI

/// メインの表示領域。Phase 0 では空のウィンドウのみ。
struct ReaderView: View {
    var body: some View {
        Color.black
            .frame(minWidth: 400, minHeight: 300)
            .navigationTitle("YomiView")
    }
}
