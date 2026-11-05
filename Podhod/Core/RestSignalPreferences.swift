import Foundation

enum RestSignalSound: String, Codable, CaseIterable, Identifiable {
    case system, shortBeep, doubleChime, tripleChime, electronic, loudBell, alarm, silent
    var id: String { rawValue }
    // Retain the old raw value for backups, but rest completion always requests a sound.
    var audible: Self { self == .silent ? .doubleChime : self }
    static var selectable: [Self] { allCases.filter { $0 != .silent } }
    var title: String {
        switch self {
        case .system: return "Системный"
        case .shortBeep: return "Короткий сигнал"
        case .doubleChime: return "Двойной сигнал"
        case .tripleChime: return "Тройной сигнал"
        case .electronic: return "Электронный"
        case .loudBell: return "Громкий звонок"
        case .alarm: return "Будильник"
        case .silent: return "Без звука"
        }
    }
    var fileName: String? {
        switch self {
        case .system, .silent: return nil
        case .shortBeep: return "rest-short.wav"
        case .doubleChime: return "rest-double.wav"
        case .tripleChime: return "rest-triple.wav"
        case .electronic: return "rest-electronic.wav"
        case .loudBell: return "rest-bell.wav"
        case .alarm: return "rest-alarm.wav"
        }
    }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        self = (Self(rawValue: value) ?? .system).audible
    }
}

struct RestSignalPreferences: Codable, Equatable {
    var sound: RestSignalSound = .system
    var hapticInApp = true
    // Legacy backup field. Kept for decoding only; rest signals always use notifications.
    var loudAlertsEnabled = false

    init(sound: RestSignalSound = .system, hapticInApp: Bool = true, loudAlertsEnabled: Bool = false) {
        self.sound = sound.audible; self.hapticInApp = hapticInApp; self.loudAlertsEnabled = loudAlertsEnabled
    }
    private enum CodingKeys: String, CodingKey { case sound, hapticInApp, loudAlertsEnabled }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        sound = try values.decodeIfPresent(RestSignalSound.self, forKey: .sound) ?? .system
        hapticInApp = try values.decodeIfPresent(Bool.self, forKey: .hapticInApp) ?? true
        loudAlertsEnabled = try values.decodeIfPresent(Bool.self, forKey: .loudAlertsEnabled) ?? false
    }
}
