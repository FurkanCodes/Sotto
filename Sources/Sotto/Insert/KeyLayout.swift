import Carbon
import CoreGraphics

/// Finds which physical key types a character with Command held, so Cmd+V
/// works on layouts like Dvorak. Non-Latin layouts map Command shortcuts to
/// ANSI positions, so they fall back to kVK_ANSI_V (Handy input.rs).
@MainActor
enum KeyLayout {
    static func keyCode(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        let target = String(character).lowercased()
        let commandModifier = UInt32((cmdKey >> 8) & 0xFF)

        return data.withUnsafeBytes { bytes -> CGKeyCode? in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDown), commandModifier,
                    UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState, characters.count, &length, &characters
                )
                if status == noErr, length > 0,
                   String(utf16CodeUnits: characters, count: length).lowercased() == target {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }
}
