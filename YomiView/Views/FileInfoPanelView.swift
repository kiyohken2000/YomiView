import SwiftUI

/// ファイル情報パネル。表示中のページ（見開きでは読む順で最初のページ）の情報をグループごとに表示する。
struct FileInfoPanelView: View {
    let viewModel: ReaderViewModel

    @State private var groups: [FileInformation.Group] = []

    var body: some View {
        let page = viewModel.currentSpread?.first
        Group {
            if viewModel.provider == nil {
                note("本を開いていません")
            } else if groups.isEmpty {
                note("")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.foreground)
                                ForEach(group.items) { item in
                                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                                        Text(item.label)
                                            .foregroundStyle(Theme.grayText)
                                            .frame(width: 110, alignment: .leading)
                                        Text(item.value)
                                            .foregroundStyle(Theme.foreground)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .font(.system(size: 12))
                                }
                            }
                            Rectangle().fill(Theme.panelSeparator).frame(height: 1)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
        .task(id: TaskKey(provider: viewModel.provider.map(ObjectIdentifier.init), page: page)) {
            guard let provider = viewModel.provider, let page else {
                groups = []
                return
            }
            let info = await Task.detached(priority: .utility) { try? provider.fileInfo(at: page) }.value
            guard !Task.isCancelled else { return }
            groups = info.map(FileInformation.groups(for:)) ?? []
        }
    }

    private struct TaskKey: Equatable {
        let provider: ObjectIdentifier?
        let page: Int?
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.grayText)
            .padding(8)
    }
}
