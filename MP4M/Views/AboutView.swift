import SwiftUI

struct AboutView: View {
    @Binding var isPresented: Bool
    @AppStorage(UserDefaultsKey.opmEngine) private var opmEngineType: Int = 0

    var body: some View {
        VStack(spacing: 16) {
            // アプリアイコン
            Image(nsImage: NSImage(named: "MP4M") ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)

            // タイトル
            Text("mp4m").font(.mp4mTitle).foregroundColor(.mp4mAmber)

            // バージョン情報
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            Text("Version \(version)").font(.mp4mSmall).foregroundColor(.mp4mText)
            Text("MDX Player for macOS").font(.mp4mTiny).foregroundColor(.mp4mDim)

            // OPM エンジン切替
            VStack(spacing: 6) {
                Text("OPM Engine")
                    .font(.mp4mTiny)
                    .foregroundColor(.mp4mDim)

                HStack(spacing: 0) {
                    engineButton("ymfm", type: 0)
                    engineButton("fmgen", type: 1)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.mp4mBorder, lineWidth: 1)
                )
            }

            Divider().background(Color.mp4mBorder)

            // ライセンス情報（スクロール可能）
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    LicenseRow(
                        name: "ymfm",
                        author: "Aaron Giles",
                        license: "BSD 3-Clause (Commercial use permitted)"
                    )
                    LicenseRow(
                        name: "fmgen",
                        author: "cisc",
                        license: "Free for non-commercial use"
                    )
                    LicenseRow(
                        name: "GAMDX",
                        author: "GORRY",
                        license: "Apache 2.0"
                    )
                    LicenseRow(
                        name: "LZX Decompression",
                        author: "MP4M Project",
                        license: "0BSD (Commercial use permitted)"
                    )
                    LicenseRow(
                        name: "Monaspace Neon",
                        author: "GitHub Next",
                        license: "SIL OFL v1.1"
                    )
                }
                .padding(.trailing, 8)
            }
            .frame(maxHeight: 160)

            Divider().background(Color.mp4mBorder)

            // 著作権・配布方針
            VStack(alignment: .leading, spacing: 6) {
                Text("X68000 Freeware Copyright Policy")
                    .font(.mp4mSmall)
                    .foregroundColor(.mp4mBright)

                Text("This project respects the copyrights of X68000 freeware authors:")
                    .font(.mp4mTiny)
                    .foregroundColor(.mp4mText.opacity(0.9))
                    .lineLimit(nil)
                Text("GORRY (GAMDX), milk, K.MAEKAWA, m_puusan, Yosshin, Missy.M, Yatsube (MXDRV), and others.")
                    .font(.mp4mTiny)
                    .foregroundColor(.mp4mText.opacity(0.9))
                    .lineLimit(nil)
                Text("We do not distribute through App Store to preserve their original intent.")
                    .font(.mp4mTiny)
                    .foregroundColor(.mp4mText.opacity(0.9))
                    .lineLimit(nil)

                Text("Distribution: GitHub Releases only")
                    .font(.mp4mTiny)
                    .foregroundColor(.mp4mDim)
                    .italic()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider().background(Color.mp4mBorder)

            // 閉じるボタン
            Button("[ CLOSE ]") {
                isPresented = false
            }
            .buttonStyle(.plain)
            .font(.mp4mSmall)
            .foregroundColor(.mp4mBright)
            .onHover { isHovered in
                if isHovered {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        .padding(24)
        .background(Color.mp4mBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.mp4mAmber, lineWidth: 1.5)
        )
        .frame(width: 480)
        .shadow(color: .black.opacity(0.8), radius: 24)
    }

    @ViewBuilder
    private func engineButton(_ label: String, type: Int) -> some View {
        Button {
            opmEngineType = type
            MXDRVGBridge.setOpmEngine(Int32(type))
        } label: {
            Text(label)
                .font(.mp4mTiny)
                .foregroundColor(opmEngineType == type ? .mp4mAmber : .mp4mDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(opmEngineType == type ? Color.mp4mAmber.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// ライセンス情報の1行表示
private struct LicenseRow: View {
    let name: String
    let author: String
    let license: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.mp4mSmall)
                .foregroundColor(.mp4mBright)

            HStack(spacing: 8) {
                Text("©")
                    .font(.mp4mTiny)
                    .foregroundColor(.mp4mDim)

                Text(author)
                    .font(.mp4mTiny)
                    .foregroundColor(.mp4mText)

                Text("—")
                    .font(.mp4mTiny)
                    .foregroundColor(.mp4mDim)

                Text(license)
                    .font(.mp4mTiny)
                    .foregroundColor(.mp4mText.opacity(0.8))
                    .lineLimit(nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ZStack {
        Color.mp4mBackground.ignoresSafeArea()
        AboutView(isPresented: .constant(true))
    }
}
