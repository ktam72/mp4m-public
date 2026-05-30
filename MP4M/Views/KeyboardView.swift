import SwiftUI

// MARK: - PianoKey: 個別の鍵
struct PianoKey: Identifiable {
    static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    let id: Int  // MIDI ノート番号
    let midiNote: Int
    let isBlackKey: Bool

    var octave: Int { midiNote / 12 }
    var note: Int { midiNote % 12 }

    var label: String {
        "\(Self.noteNames[note])\(octave)"
    }
}

// MARK: - PianoKeyboard: キーボード全体を管理
struct PianoKeyboard {
    private(set) var keys: [PianoKey]
    let startMidiNote: Int
    let endMidiNote: Int

    init(startMidiNote: Int = 0, endMidiNote: Int = 96) {
        self.startMidiNote = startMidiNote
        self.endMidiNote = endMidiNote
        self.keys = (startMidiNote..<endMidiNote).map { midiNote in
            PianoKey(
                id: midiNote,
                midiNote: midiNote,
                isBlackKey: Self.isBlackNote(midiNote % 12)
            )
        }
    }

    // MIDI ノートに対応する鍵を取得
    func key(for midiNote: Int) -> PianoKey? {
        guard midiNote >= startMidiNote && midiNote < endMidiNote else { return nil }
        return keys[midiNote - startMidiNote]
    }

    // note が黒鍵か判定
    private static func isBlackNote(_ note: Int) -> Bool {
        [1, 3, 6, 8, 10].contains(note)
    }

    // 白鍵リスト
    var whiteKeys: [PianoKey] {
        keys.filter { !$0.isBlackKey }
    }

    // 黒鍵リスト
    var blackKeys: [PianoKey] {
        keys.filter { $0.isBlackKey }
    }
}

// MARK: - KeyboardView
struct KeyboardView: View {
    let viewModel: PlayerViewModel?
    @State private var keyboard = PianoKeyboard(startMidiNote: 0, endMidiNote: 96)
    @State private var cachedWhiteKeys: [PianoKey] = []
    @State private var cachedBlackKeys: [PianoKey] = []

    var body: some View {
        VStack(spacing: 1) {
            Text("KEYBOARD")
                .font(.mp4mSmall)
                .foregroundColor(Color.mp4mCyan)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .padding(.top, 3)

            GeometryReader { geo in
                let channels = viewModel?.channels ?? []
                let keyH = (geo.size.height - 16) / CGFloat(AudioConstants.fmChannelCount)
                let leftMargin: CGFloat = 50
                let drawWidth = geo.size.width - leftMargin
                let whiteKeyW = drawWidth / CGFloat(cachedWhiteKeys.count)

                Canvas { ctx, size in
                    // 背景
                    ctx.fill(Path(CGRect(origin: .zero, size: size)),
                            with: .color(Color.mp4mBackground))

                    // キャッシュされた白鍵・黒鍵を使用（毎フレームフィルタ不要）
                    let whiteKeys = cachedWhiteKeys
                    let blackKeys = cachedBlackKeys

                    // FM 8チャンネル分のキーボード行を描画
                    for channelIndex in 0..<AudioConstants.fmChannelCount {
                        let rowY = CGFloat(channelIndex) * keyH + 2

                        // 現在のチャンネルが再生中のノートを取得（このチャンネルのみ）
                        let chState = channelIndex < channels.count ? channels[channelIndex] : ChannelDisplayState()
                        let litMidiNote: Int? = chState.keyOn ? Int(chState.keyCode) : nil

                        // 白鍵を描画
                        for (whiteIndex, whiteKey) in whiteKeys.enumerated() {
                            let keyX = leftMargin + CGFloat(whiteIndex) * whiteKeyW
                            let keyRect = CGRect(x: keyX + 0.5, y: rowY + 0.5,
                                               width: whiteKeyW - 1, height: keyH - 1)
                            let isLit = litMidiNote == whiteKey.midiNote
                            let color = isLit ? Color.mp4mBright : Color(white: 0.7)

                            ctx.fill(Path(keyRect), with: .color(color))
                        }

                        // 黒鍵を描画
                        for blackKey in blackKeys {
                            // 黒鍵の前にある白鍵の数を数える
                            let whitesBefore = whiteKeys
                                .filter { $0.midiNote < blackKey.midiNote }.count

                            // 黒鍵の X 位置: 前の白鍵の右端付近
                            let blackKeyX = leftMargin + CGFloat(whitesBefore - 1) * whiteKeyW + whiteKeyW * 0.65
                            let blackKeyWidth = whiteKeyW * 0.6
                            let blackKeyHeight = keyH * 0.6
                            let blackKeyRect = CGRect(
                                x: blackKeyX, y: rowY,
                                width: blackKeyWidth, height: blackKeyHeight
                            )

                            let isLit = litMidiNote == blackKey.midiNote
                            let color = isLit ? Color.mp4mBright.opacity(0.9) : Color(white: 0.15)
                            ctx.fill(Path(blackKeyRect), with: .color(color))
                        }

                        // CHラベル：再生中は Note名 + オクターブ、それ以外は空白
                        let labelText = chLabel(for: chState, keyboard: keyboard)
                        ctx.draw(
                            Text(labelText).font(.mp4mTitle)
                                .foregroundColor(Color.mp4mCyan.opacity(0.6)),
                            at: CGPoint(x: 20, y: rowY + keyH / 2)
                        )
                    }
                }
            }
            .padding(.horizontal, 4)
        }
        .background(Color.mp4mBackground)
        .onAppear {
            // キャッシュを初期化（1回だけ実行）
            cachedWhiteKeys = keyboard.whiteKeys
            cachedBlackKeys = keyboard.blackKeys
        }
    }

    private func chLabel(for ch: ChannelDisplayState, keyboard: PianoKeyboard) -> String {
        guard ch.keyOn else { return " " }
        let midiNote = Int(ch.keyCode)
        guard let pianoKey = keyboard.key(for: midiNote) else { return " " }
        return pianoKey.label
    }
}
