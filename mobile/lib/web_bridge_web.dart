import 'dart:js_interop';

@JS('kundliBack')
external set _kundliBack(JSFunction handler);

/// `window.kundliBack()` closes the top screen or dialog and returns true, or returns false at the
/// home screen so the shell can leave the app (Navigator pushes add no browser history entries).
void exposeBack(bool Function() handler) {
  _kundliBack = (() => handler().toJS).toJS;
}
