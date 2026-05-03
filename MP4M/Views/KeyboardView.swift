import SwiftUI

/// ピアノキーボード表示 (8チャンネル分)
struct KeyboardView: View {
    let viewModel: PlayerViewModel?
    private let octaveCount = 8
    private let noteNames = ["E","F","F#","G","G#","A","A#","B","C","C#","D","D#"]
    private let noteXOffsets: [CGFloat] = [0, 4, 6, 8, 10, 12, 14, 16, 20, 22, 24, 26]
    private let isBlackKey: [Bool]       = [false, false, true, false, true, false, true, false, false, true, false, true]

    var body: some View {
        VStack(spacing: 1) {
            Text("KEYBOARD")
                .font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 15))
                .foregroundColor(Color.mmdspCyan)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .padding(.top, 3)
            GeometryReader { geo in
                let channels = viewModel?.channels ?? []
                let keyH = (geo.size.height - 16) / 8
                let totalOctW = geo.size.width / CGFloat(octaveCount)
                let whiteKeyW = totalOctW / 7
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.mmdspBackground))
                    for ch in 0..<8 {
                        let chState = ch < channels.count ? channels[ch] : ChannelDisplayState()
                        let y = CGFloat(ch) * keyH + 2
                        for octave in 0..<octaveCount {
                            let octX = CGFloat(octave) * totalOctW
                            for (wi, wNote) in [0, 1, 3, 5, 7, 8, 10].enumerated() {
                                let kx = octX + CGFloat(wi) * whiteKeyW
                                let kr = CGRect(x: kx + 0.5, y: y + 0.5,
                                                width: whiteKeyW - 1, height: keyH - 1)
                                let lit = isKeyOn(chState, octave: octave, note: wNote)
                                ctx.fill(Path(kr), with: .color(lit ? Color.mmdspBright : Color(white: 0.7)))
                            }
                            for (_, bNote) in [2, 4, 6, 9, 11].enumerated() {
                                let bx = octX + blackKeyX(note: bNote, whiteKeyW: whiteKeyW)
                                let bw = whiteKeyW * 0.6
                                let bh = keyH * 0.6
                                let br = CGRect(x: bx, y: y, width: bw, height: bh)
                                let lit = isKeyOn(chState, octave: octave, note: bNote)
                                ctx.fill(Path(br), with: .color(lit ? Color.mmdspBright.opacity(0.9) : Color(white: 0.15)))
                            }
                        }
                        ctx.draw(
                            Text("CH\(ch + 1)").font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 14)).foregroundColor(Color.mmdspCyan.opacity(0.6)),
                            at: CGPoint(x: 4, y: y + keyH / 2)
                        )
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color.mmdspBackground)
    }

    private func isKeyOn(_ ch: ChannelDisplayState, octave: Int, note: Int) -> Bool {
        guard ch.keyOn else { return false }
        let idx = Int(ch.keyCode) + Int(ch.keyOffset) - 15
        guard idx >= 0, idx < 96 else { return false }
        let kOct = idx / 12
        let kNote = idx % 12
        return kOct == octave && kNote == note
    }

    private func blackKeyX(note: Int, whiteKeyW: CGFloat) -> CGFloat {
        let map: [Int: CGFloat] = [2: 1.65, 4: 2.65, 6: 3.65, 9: 5.65, 11: 6.65]
        return (map[note] ?? 0) * whiteKeyW - whiteKeyW * 0.3
    }
}
