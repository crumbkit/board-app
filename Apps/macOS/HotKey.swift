// A system-wide shortcut through Carbon's RegisterEventHotKey, which needs
// no Accessibility permission, unlike a global event monitor.
import Carbon.HIToolbox

@MainActor
final class HotKey {
  private var hotKey: EventHotKeyRef?
  private var handler: EventHandlerRef?
  private let action: @MainActor () -> Void

  /// ⌃⌥Space by default. Nil when another app already holds the shortcut.
  init?(
    keyCode: Int = kVK_Space, modifiers: Int = controlKey | optionKey,
    action: @escaping @MainActor () -> Void
  ) {
    self.action = action
    var pressed = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let me = Unmanaged.passUnretained(self).toOpaque()
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
        // Carbon delivers application events on the main thread.
        MainActor.assumeIsolated { hotKey.action() }
        return noErr
      }, 1, &pressed, me, &handler)
    // 'BRDL' names this app's shortcut in the event.
    let id = EventHotKeyID(signature: 0x4252_444C, id: 1)
    let status = RegisterEventHotKey(
      UInt32(keyCode), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKey)
    guard status == noErr else {
      if let handler { RemoveEventHandler(handler) }
      return nil
    }
  }
}
