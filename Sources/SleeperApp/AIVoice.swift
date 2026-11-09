import Foundation
import FoundationModels

/// Rephrases AI meeting lines with Apple's on-device model, when it's available. The template line shows first;
/// the model's version replaces it a moment later. If the model is missing, slow or fails, the template stays.
@MainActor final class AIVoice {
    let available: Bool
    private let personalities = ["cheerful and chatty", "nervous and quick", "dry and blunt", "dreamy and slow",
                                 "bossy", "polite and careful", "jumpy", "sleepy", "earnest", "sarcastic", "warm"]

    init() {
        if case .available = SystemLanguageModel.default.availability { available = true } else { available = false }
    }

    func rephrase(line id: Int, text: String, speaker: Int, controller: GameController?) {
        guard available, let controller, let game = controller.game else { return }
        let name = game.players[speaker].name
        let mood = personalities[speaker % personalities.count]
        let names = game.players.map(\.name) + game.map.rooms.map(\.name)
        Task { @MainActor [weak controller] in
            let instructions = """
            You voice \(name), an axolotl crew member in a cozy deep-sea station game where one crew member is secretly a \
            traitor. You are \(mood). The line you are given is something you say, in the first person: "I" always means \
            you, \(name). Restyle it in your own voice in at most 18 words, keeping exactly the same meaning. Keep every \
            name and room name exactly as written. Do not add facts, people, rooms or accusations. Reply with the line \
            only, no quotes.
            """
            let session = LanguageModelSession(instructions: instructions)
            guard let reply = try? await session.respond(to: text, options: GenerationOptions(temperature: 0.8)) else { return }
            var out = reply.content.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
            guard !out.isEmpty, out.count < 200 else { return }
            // Reject rewrites that drop a name the line mentioned.
            for n in names where text.contains(n) && !out.contains(n) { return }
            if !out.hasSuffix(".") && !out.hasSuffix("!") && !out.hasSuffix("?") { out += "." }
            controller?.rephrased(line: id, to: out)
        }
    }
}
