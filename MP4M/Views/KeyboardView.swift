import SwiftUI

/// ピアノキーボード表示 (8チャンネル分)
struct KeyboardView: View {
    let viewModel: PlayerViewModel?
    private let octaveCount = 8
    private let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    private let noteXOffsets: [CGFloat] = [0, 4, 6, 8, 10, 12, 14, 16, 20, 22, 24, 26]
    private let isBlackKey: [Bool]       = [false, true, false, true, false, false, true, false, true, false, true, false]

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
                let leftMargin: CGFloat = 64  // CHラベル用に調整（鍵盤全体を右にシフト）
                let totalOctW = (geo.size.width - leftMargin) / CGFloat(octaveCount)
                let whiteKeyW = totalOctW / 7
                Canvas { ctx, size in
                    ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.mmdspBackground))
                    for ch in 0..<8 {
                        let chState = ch < channels.count ? channels[ch] : ChannelDisplayState()
                        let y = CGFloat(ch) * keyH + 2
                        for octave in 0..<octaveCount {
                            let octX = CGFloat(octave) * totalOctW + leftMargin
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
                        // チャンネルラベル：再生中は Note名 + オクターヴ、それ以外は空白
                        let labelText = noteLabel(for: chState, channel: ch)
                        ctx.draw(
                            Text(labelText).font(.custom("KH-Dot-Kodenmachou-16-Ki", size: 21)).foregroundColor(Color.mmdspCyan.opacity(0.6)),
                            at: CGPoint(x: 20, y: y + keyH / 2)  // 左から20pxの位置に移動
                        )
                    }
                }
            }
            .padding(.horizontal, 4)  // パディングを4pxに戻す
        }
        .background(Color.mmdspBackground)
    }

    private func isKeyOn(_ ch: ChannelDisplayState, octave: Int, note: Int) -> Bool {
        guard ch.keyOn else { return false }
        // MDX 音符 → MIDI 音符 の変換：MDX 0x80 = MIDI 3 (C1)
        let mdxNote = Int(ch.keyCode) + Int(ch.keyOffset)
        let midiNote = mdxNote  // MDX 音符をそのまま使用（0x80 = 3）
        guard midiNote >= 0, midiNote < 96 else { return false }
        let kOct = midiNote / 12
        let kNote = midiNote % 12
        return kOct == octave && kNote == note
    }

    private func blackKeyX(note: Int, whiteKeyW: CGFloat) -> CGFloat {
        let map: [Int: CGFloat] = [2: 1.65, 4: 2.65, 6: 3.65, 9: 5.65, 11: 6.65]
        return (map[note] ?? 0) * whiteKeyW - whiteKeyW * 0.3
    }

    /// チャンネルラベル：再生中は Note名 + オクターヴ、それ以外は空白（スペース）
    private func noteLabel(for ch: ChannelDisplayState, channel: Int) -> String {
        guard ch.keyOn else { return " " }  // 空白（1スペース）
        // MDX 音符 → MIDI 音符：MDX 0x80 = MIDI 3
        let mdxNote = Int(ch.keyCode) + Int(ch.keyOffset)
        let midiNote = mdxNote  // 変換不要（MDX 音符がそのまま MIDI 音符として扱われる）
        guard midiNote >= 0, midiNote < 96 else { return " " }
        let kNote = midiNote % 12
        let kOct = midiNote / 12
        return "\(noteNames[kNote])\(kOct)"  // 例: C4, D#5
    }
}