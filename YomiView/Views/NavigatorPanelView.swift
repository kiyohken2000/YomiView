import SwiftUI

/// ナビゲーターパネル（NeeView/SidePanels/Navigate）。ストレッチ・回転・スケール・反転を操作する。
struct NavigatorPanelView: View {
    @Bindable var viewModel: ReaderViewModel

    @State private var angleText = ""
    @State private var scaleText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                stretchSection
                separator
                rotateSection
                separator
                scaleSection
                separator
                flipSection
                separator
                Button("表示をリセット") { viewModel.resetView() }
                    .buttonStyle(IconButtonStyle())
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .foregroundStyle(Theme.foreground)
        .font(.system(size: 13))
    }

    private var separator: some View {
        Rectangle().fill(Theme.panelSeparator).frame(height: 1)
    }

    private func header(_ text: String) -> some View {
        Text(text).font(.system(size: 13))
    }

    // MARK: - ストレッチ

    private var stretchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("ストレッチ")
            HStack(spacing: 2) {
                Menu {
                    Picker("ストレッチ", selection: Binding(
                        get: { viewModel.settings.stretchMode },
                        set: { viewModel.setStretchMode($0) }
                    )) {
                        ForEach(PageStretchMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text("\(viewModel.settings.stretchMode.label) \(Image(systemName: "chevron.down"))")
                        .foregroundStyle(Theme.accent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                Spacer()
                Button { viewModel.setAllowScaleDown(!viewModel.settings.allowScaleDown) } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                }
                .buttonStyle(IconButtonStyle(isChecked: viewModel.settings.allowScaleDown))
                .help("縮小を許可")
                Button { viewModel.setAllowScaleUp(!viewModel.settings.allowScaleUp) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(IconButtonStyle(isChecked: viewModel.settings.allowScaleUp))
                .help("拡大を許可")
            }
        }
    }

    // MARK: - 回転

    private var rotateSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("回転")
            HStack {
                Slider(
                    value: Binding(get: { viewModel.transform.angle }, set: { viewModel.setAngle($0.rounded()) }),
                    in: -180...180
                )
                .tint(Theme.accent)
                numberField(
                    text: $angleText, value: Int(viewModel.transform.angle.rounded()),
                    commit: { viewModel.setAngle($0) }
                )
            }
            HStack(spacing: 2) {
                Button { viewModel.rotateLeft() } label: { Image(systemName: "rotate.left") }
                    .help("左回転（⌘L）")
                Button { viewModel.rotateRight() } label: { Image(systemName: "rotate.right") }
                    .help("右回転（⌘R）")
                Button { viewModel.resetAngle() } label: { Image(systemName: "xmark") }
                    .help("角度をリセット")
            }
            .buttonStyle(IconButtonStyle())
        }
    }

    // MARK: - スケール

    /// スライダーは対数（10%〜2000%）
    private var scaleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("スケール")
            HStack {
                Slider(
                    value: Binding(
                        get: { log2(max(0.1, viewModel.displayedScale)) },
                        set: { viewModel.setDisplayedScale(pow(2, $0)) }
                    ),
                    in: log2(0.1)...log2(20)
                )
                .tint(Theme.accent)
                numberField(
                    text: $scaleText, value: Int((viewModel.displayedScale * 100).rounded()),
                    commit: { viewModel.setDisplayedScale($0 / 100) }
                )
            }
            HStack(spacing: 2) {
                Button { viewModel.zoomOut() } label: { Image(systemName: "minus.circle") }
                    .help("縮小（⌘-）")
                Button { viewModel.zoomIn() } label: { Image(systemName: "plus.circle") }
                    .help("拡大（⌘+）")
                Button { viewModel.resetScale() } label: { Image(systemName: "xmark") }
                    .help("スケールをリセット")
            }
            .buttonStyle(IconButtonStyle())
        }
    }

    // MARK: - 反転

    private var flipSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            header("反転")
            HStack(spacing: 2) {
                Button { viewModel.toggleFlipHorizontal() } label: {
                    Image(systemName: "arrow.left.and.right.righttriangle.left.righttriangle.right")
                }
                .buttonStyle(IconButtonStyle(isChecked: viewModel.transform.flipHorizontal))
                .help("左右反転")
                Button { viewModel.toggleFlipVertical() } label: {
                    Image(systemName: "arrow.up.and.down.righttriangle.up.righttriangle.down")
                }
                .buttonStyle(IconButtonStyle(isChecked: viewModel.transform.flipVertical))
                .help("上下反転")
            }
        }
    }

    /// 数値の入力欄。Enter で確定する
    private func numberField(text: Binding<String>, value: Int, commit: @escaping (Double) -> Void) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .padding(.horizontal, 4)
            .frame(width: 60, height: 22)
            .background(Theme.textBoxBackground)
            .overlay(Rectangle().strokeBorder(Theme.textBoxBorder, lineWidth: 1))
            .onAppear { text.wrappedValue = "\(value)" }
            .onChange(of: value) { _, new in text.wrappedValue = "\(new)" }
            .onSubmit {
                if let number = Double(text.wrappedValue.trimmingCharacters(in: .whitespaces)) { commit(number) }
                text.wrappedValue = "\(value)"
            }
    }
}
