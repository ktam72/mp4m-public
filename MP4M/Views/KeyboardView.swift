import SwiftUI

/// ピアノキーボード表示 (8チャンネル分)
struct KeyboardView: View {
    let viewModel: PlayerViewModel?
    private let octaveCount = 8
    private let noteNames = ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]
    private let whiteKeyNotes: [Int] = [0, 2, 4, 5, 7, 9, 11]   // C, D, E, F, G, A, B
    private let blackKeyNotes: [Int] = [1, 3, 6, 8, 10]         // C#, D#, F#, G#, A#

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
                            // 白鍵: C(0), D(2), E(4), F(5), G(7), A(9), B(11)
                            for (wi, wNote) in whiteKeyNotes.enumerated() {
                                let kx = octX + CGFloat(wi) * whiteKeyW
                                let kr = CGRect(x: kx + 0.5, y: y + 0.5,
                                                width: whiteKeyW - 1, height: keyH - 1)
                                let lit = isKeyOn(chState, octave: octave, note: wNote)
                                ctx.fill(Path(kr), with: .color(lit ? Color.mmdspBright : Color(white: 0.7)))
                            }
                            // 黒鍵: C#(1), D#(3), F#(6), G#(8), A#(10)
                            for bNote in blackKeyNotes {
                                let bx = octX + blackKeyX(note: bNote, whiteKeyW: whiteKeyW)
                                let bw = whiteKeyW * 0.6
                                let bh = keyH * 0.6
                                let br = CGRect(x: bx, y: y, width: bw, height: bh)
                                let lit = isKeyOn(chState, octave: octave, note: bNote)
                                ctx.fill(Path(br), with: .color(lit ? Color.mmdspBright.opacity(0.9) : Color(white: 0.15)))
                            }
                        }
                        // チャンネルラベル：再生中は Note名 + オクターブ、それ以外は空白
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
        // 単純な変換：keyCodeをMIDIノートとして扱う
        let midiNote = Int(ch.keyCode) + Int(ch.keyOffset)
        guard midiNote >= 0, midiNote < 96 else { return false }
        let kOct = midiNote / 12
        let kNote = midiNote % 12
        return kOct == octave && kNote == note
    }

    /// 黒鍵のX座標を計算（白鍵の間に配置）
    private func blackKeyX(note: Int, whiteKeyW: CGFloat) -> CGFloat {
        // 黒鍵の位置: C#=1.5, D#=2.5, F#=4.5, G#=5.5, A#=6.5 (白鍵インデックス基準)
        let map: [Int: CGFloat] = [1: 1.5, 3: 2.5, 6: 4.5, 8: 5.5, 10: 6.5]
        return (map[note] ?? 0) * whiteKeyW
    }

    /// チャンネルラベル：再生中は Note名 + オクターブ、それ以外は空白（スペース）
    private func noteLabel(for ch: ChannelDisplayState, channel: Int) -> String {
        guard ch.keyOn else { return " " }  // 空白（1スペース）
        // 単純な変換：keyCodeをMIDIノートとして扱う
        let midiNote = Int(ch.keyCode) + Int(ch.keyOffset)
        guard midiNote >= 0, midiNote < 96 else { return " " }
        let kNote = midiNote % 12
        let kOct = midiNote / 12
        return "\(noteNames[kNote])\(kOct)"  // 例: C#4, D5
    }
}