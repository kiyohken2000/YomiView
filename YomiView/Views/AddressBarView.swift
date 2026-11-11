import SwiftUI

/// ウィンドウ上部のアドレスバー（NeeView/AddressBar/AddressBarView.xaml の構成）。
struct AddressBarView: View {
    @Bindable var viewModel: ReaderViewModel
    var onCommit: () -> Void

    @State private var address = ""
    @FocusState private var isAddressFocused: Bool

    var body: some View {
        HStack(spacing: 2) {
            Button { viewModel.goBackBook() } label: {
                Image(systemName: "arrow.left")
            }
            .help("戻る（⌘[）")
            .disabled(!viewModel.canGoBackBook)

            Button { viewModel.goForwardBook() } label: {
                Image(systemName: "arrow.right")
            }
            .help("進む（⌘]）")
            .disabled(!viewModel.canGoForwardBook)

            Button { viewModel.openParentBook() } label: {
                Image(systemName: "arrow.up")
            }
            .help("上の階層へ（⌘↑）")
            .disabled(!viewModel.isBookOpen)

            Button { viewModel.reload() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("再読み込み")
            .disabled(!viewModel.isBookOpen)

            addressField
                .padding(.horizontal, 10)

            Button { viewModel.toggleViewMode() } label: {
                Image(systemName: viewModel.viewMode == .spread ? "2.square" : "1.square")
            }
            .help(viewModel.viewMode == .spread ? "1ページ表示にする（M）" : "見開き表示にする（M）")

            Button { viewModel.toggleReadingDirection() } label: {
                Image(systemName: viewModel.readingDirection == .rightToLeft ? "arrow.left" : "arrow.right")
            }
            .help(viewModel.readingDirection == .rightToLeft ? "右開き（D で左開き）" : "左開き（D で右開き）")
        }
        .buttonStyle(IconButtonStyle(foreground: Theme.foreground))
        .font(.system(size: 15))
        .padding(.horizontal, 4)
        .frame(height: 36)
        .background(Theme.menuBar)
        .onAppear { address = viewModel.bookURL?.path ?? "" }
        .onChange(of: viewModel.bookURL) { _, url in address = url?.path ?? "" }
    }

    private var addressField: some View {
        HStack(spacing: 6) {
            Image(systemName: viewModel.isBookOpen ? "book.closed" : "folder")
                .foregroundStyle(Theme.grayText)
            TextField("", text: $address, prompt: Text("パスを入力して Enter で開く").foregroundStyle(Theme.grayText))
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.foreground)
                .focused($isAddressFocused)
                .onSubmit {
                    let path = (address as NSString).expandingTildeInPath
                    guard !path.isEmpty else { return }
                    viewModel.open(URL(fileURLWithPath: path))
                    onCommit()
                }
                .onExitCommand {
                    address = viewModel.bookURL?.path ?? ""
                    onCommit()
                }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Theme.address)
    }
}
