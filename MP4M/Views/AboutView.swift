import SwiftUI

struct AboutView: View {
    @Binding var isPresented: Bool

    var body: some View {
        VStack(spacing: 16) {
            // アプリアイコン
            Image(nsImage: NSImage(named: "MP4M") ?? NSImage())
                .resizable()
                .frame(width: 80, height: 80)

            // タイトル
            Text("mp4m").font(.mp4mTitle).foregroundColor(.mp4mAmber)

            // バージョン情報
            Text("Version 1.0 β").font(.mp4mSmall).foregroundColor(.mp4mText)
            Text("macOS MDX Player for X68000").font(.mp4mTiny).foregroundColor(.mp4mDim)

            Divider().background(Color.mp4mBorder)

            // ライセンス情報（スクロール可能）
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    LicenseRow(
                        name: "fmgen",
                        author: "cisc",
                        license: "cisc Copyright (Commercial use requires prior agreement)"
                    )
                    LicenseRow(
                        name: "MXDRVG",
                        author: "GORRY",
                        license: "Apache 2.0"
                    )
                    LicenseRow(
                        name: "pcm8 / x68pcm8",
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
