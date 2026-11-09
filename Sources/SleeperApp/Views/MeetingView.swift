import SleeperCore
import SwiftUI

struct MiniGameView: View {
    let state: MiniGameState
    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
            VStack(spacing: 14) {
                Text(state.title).font(Theme.title(18)).foregroundStyle(Theme.ink)
                Group {
                    switch state.game {
                    case .hold: hold
                    case .sequence: sequence
                    case .timing: timing
                    }
                }
                .frame(width: 320, height: 90)
                HStack(spacing: 14) {
                    switch state.game {
                    case .hold: Hint(key: "Hold E", text: "until full")
                    case .sequence: Hint(key: "Arrows", text: "in order")
                    case .timing: Hint(key: "Space", text: "inside the green, 3 times")
                    }
                    Hint(key: "Esc", text: "close")
                }
            }
            .padding(20)
            .panel(tint: state.finished > 0 ? Theme.good : nil, radius: 18)
            .offset(x: state.mistake > 0 ? CGFloat(sin(state.mistake * 60) * 6) : 0)
        }
    }

    private var hold: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.08)).frame(width: 70, height: 80)
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [Theme.good, Theme.good.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 70, height: 80 * state.progress)
                Image(systemName: state.holding ? "drop.fill" : "drop").font(.system(size: 22)).foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 28)
            }
        }
    }

    private var sequence: some View {
        HStack(spacing: 10) {
            ForEach(Array(state.sequence.enumerated()), id: \.offset) { i, d in
                Image(systemName: d.symbol)
                    .font(.system(size: 22, weight: .bold))
                    .frame(width: 46, height: 46)
                    .foregroundStyle(i < state.index ? Theme.deep : (i == state.index ? Theme.ink : Theme.faint))
                    .background(RoundedRectangle(cornerRadius: 10).fill(i < state.index ? Theme.good : .white.opacity(i == state.index ? 0.18 : 0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(state.mistake > 0 ? Theme.alert : .clear, lineWidth: 2))
            }
        }
    }

    private var timing: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(Theme.good.opacity(state.flash > 0 ? 0.9 : 0.5))
                        .frame(width: w * (state.zone.upperBound - state.zone.lowerBound))
                        .offset(x: w * state.zone.lowerBound)
                    RoundedRectangle(cornerRadius: 2).fill(state.mistake > 0 ? Theme.alert : Theme.ink)
                        .frame(width: 4, height: 34)
                        .offset(x: w * state.needle - 2)
                }
            }
            .frame(height: 34)
            HStack(spacing: 8) {
                ForEach(0..<3) { i in
                    Circle().fill(i < state.hits ? Theme.good : .white.opacity(0.15)).frame(width: 10, height: 10)
                }
            }
        }
    }
}

struct MeetingView: View {
    var rev = 0
    let controller: GameController
    let game: Game
    let meeting: Meeting

    var body: some View {
        let me = game.me
        let sel = controller.meetingSelection % game.players.count
        let myVote = meeting.votes[game.you]
        ZStack {
            Color(red: 0.01, green: 0.03, blue: 0.06).opacity(0.92)
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(Theme.title(20)).foregroundStyle(Theme.ink)
                        Text(subtitle).font(Theme.body(12)).foregroundStyle(Theme.soft)
                    }
                    Spacer()
                    Text("\(Int(meeting.timeLeft.rounded(.up)))s").font(Theme.title(20)).monospacedDigit()
                        .foregroundStyle(meeting.timeLeft < 15 ? Theme.alert : Theme.soft)
                }
                HStack(alignment: .top, spacing: 10) {
                    // Players.
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(78), spacing: 6), count: 4), spacing: 6) {
                        ForEach(Array(game.players.enumerated()), id: \.offset) { i, p in
                            PlayerTile(player: p, selected: i == sel, voted: meeting.votes[p.id] != nil,
                                       votedFor: myVote == .player(p.id), isYou: p.id == game.you, speaking: lastSpeaker == p.id)
                        }
                    }
                    .frame(width: 330)
                    // Chat.
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 7) {
                                ForEach(meeting.lines) { l in
                                    let p = game.players[l.speaker]
                                    HStack(alignment: .top, spacing: 7) {
                                        Portrait(color: p.color, hat: p.hat, scale: 1.5)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text("\(p.name) · \(p.color.name)").font(Theme.body(10, .bold)).foregroundStyle(Theme.text(p.color))
                                            Text(l.text).font(Theme.body(12.5)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .id(l.id)
                                }
                                if meeting.lines.isEmpty {
                                    Text("The crew gathers around the table…").font(Theme.body(12)).foregroundStyle(Theme.faint)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                        }
                        .onChange(of: meeting.lines.count) { _, _ in
                            if let last = meeting.lines.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                        }
                    }
                    .panel(radius: 12)
                }
                // Controls.
                if me.alive && controller.chatOpen {
                    ChatBox(controller: controller)
                } else if me.alive {
                    HStack(spacing: 12) {
                        Hint(key: "T", text: "type")
                        Hint(key: "← → ↑ ↓", text: "pick")
                        Hint(key: "A", text: "accuse")
                        Hint(key: "V", text: "vouch")
                        Hint(key: "[ ] C", text: "I was in \(game.map.rooms[controller.claimRoom].name)")
                        Spacer()
                        if myVote == nil {
                            Hint(key: "Enter", text: "vote")
                            Hint(key: "S", text: "skip")
                        } else {
                            Text("You voted \(voteText(myVote!))").font(Theme.body(12, .semibold)).foregroundStyle(Theme.good)
                        }
                    }
                } else {
                    Text("Ghosts can't speak or vote. Watch and learn.").font(Theme.body(12)).foregroundStyle(Theme.faint)
                }
            }
            .padding(14)
        }
    }

    private var lastSpeaker: Int? { meeting.lines.last.map(\.speaker) }

    private var title: String {
        switch meeting.reason {
        case .body: "Body reported"
        case .emergency: "Emergency meeting"
        }
    }

    private var subtitle: String {
        let caller = game.players[meeting.caller].name
        switch meeting.reason {
        case .body(let v, let room): return "\(caller) found \(game.players[v].name) in \(room). Who did it?"
        case .emergency: return "\(caller) pressed the button. Talk, then vote."
        }
    }

    private func voteText(_ v: Vote) -> String {
        switch v { case .skip: "to skip"; case .player(let p): "for \(game.players[p].name)" }
    }
}

/// The meeting's text box. Enter sends, Esc closes.
struct ChatBox: View {
    let controller: GameController
    @FocusState private var focused: Bool
    var body: some View {
        HStack(spacing: 10) {
            TextField("Say something… name names, say where you were", text: Binding(
                get: { controller.chatText }, set: { controller.chatText = String($0.prefix(160)) }))
                .textFieldStyle(.plain)
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink)
                .focused($focused)
                .onSubmit { controller.sendChat() }
            Hint(key: "Enter", text: "send")
            Hint(key: "Esc", text: "close")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .panel(tint: Theme.accent, radius: 10)
        .onAppear { focused = true }
    }
}

struct PlayerTile: View {
    let player: Player
    let selected: Bool
    let voted: Bool
    let votedFor: Bool
    let isYou: Bool
    let speaking: Bool
    var body: some View {
        VStack(spacing: 3) {
            ZStack(alignment: .topTrailing) {
                Portrait(color: player.color, hat: player.hat, scale: 2.6, dead: !player.alive)
                    .opacity(player.alive ? 1 : 0.45)
                if voted && player.alive {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 11)).foregroundStyle(Theme.good).offset(x: 10, y: -2)
                }
            }
            Text(isYou ? "\(player.name) (you)" : player.name).font(Theme.body(10.5, .bold)).foregroundStyle(player.alive ? Theme.ink : Theme.faint)
                .lineLimit(1)
            Text(player.alive ? player.color.name : "Gone").font(Theme.body(9.5)).foregroundStyle(player.alive ? Theme.text(player.color) : Theme.faint)
        }
        .frame(width: 78, height: 86)
        .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(selected ? 0.16 : (speaking ? 0.09 : 0.04))))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(votedFor ? Theme.accent : (selected ? .white.opacity(0.7) : .clear), lineWidth: 1.5))
    }
}

struct EjectionView: View {
    var rev = 0
    let game: Game
    let ejection: Ejection
    var body: some View {
        ZStack {
            Color(red: 0.01, green: 0.03, blue: 0.06).opacity(0.95)
            BubbleField()
            VStack(spacing: 12) {
                if let id = ejection.ejected {
                    let p = game.players[id]
                    Portrait(color: p.color, hat: p.hat, scale: 5)
                        .rotationEffect(.degrees(12))
                    Text("\(p.name) was sent up to the surface.").font(Theme.title(20)).foregroundStyle(Theme.ink)
                    Text(ejection.wasTraitor ? "\(p.name) was the traitor." : "\(p.name) was not the traitor.")
                        .font(Theme.body(14, .semibold)).foregroundStyle(ejection.wasTraitor ? Theme.good : Theme.alert)
                } else {
                    Text("No one was sent up.").font(Theme.title(20)).foregroundStyle(Theme.ink)
                    Text(ejection.skips > 0 ? "Not enough votes agreed." : "It was a tie.").font(Theme.body(13)).foregroundStyle(Theme.soft)
                }
                HStack(spacing: 10) {
                    ForEach(ejection.tally.sorted(by: { $0.value > $1.value }), id: \.key) { k, v in
                        Text("\(game.players[k].name) \(v)").font(Theme.body(11)).foregroundStyle(Theme.soft)
                    }
                    if ejection.skips > 0 { Text("Skip \(ejection.skips)").font(Theme.body(11)).foregroundStyle(Theme.faint) }
                }
            }
        }
    }
}

struct GameOverView: View {
    var rev = 0
    let game: Game
    let winner: Winner
    let reason: String
    var body: some View {
        let traitor = game.players.first(where: \.isTraitor)!
        let youWon = (winner == .traitor) == game.me.isTraitor
        ZStack {
            Color(red: 0.01, green: 0.03, blue: 0.06).opacity(0.93)
            VStack(spacing: 12) {
                Text(youWon ? "You win" : "You lose").font(Theme.body(13, .bold)).foregroundStyle(youWon ? Theme.good : Theme.alert)
                Text(winner == .crew ? "THE CREW WINS" : "THE TRAITOR WINS").font(Theme.title(30)).foregroundStyle(Theme.ink)
                Text(reason).font(Theme.body(13)).foregroundStyle(Theme.soft)
                VStack(spacing: 4) {
                    Portrait(color: traitor.color, hat: traitor.hat, scale: 5)
                    Text("The traitor was \(traitor.label)").font(Theme.body(12, .semibold)).foregroundStyle(Theme.alert)
                }
                .padding(.top, 6)
                HStack(spacing: 14) { Hint(key: "Space", text: "play again"); Hint(key: "L", text: "lobby") }
                    .padding(.top, 6)
            }
        }
    }
}
