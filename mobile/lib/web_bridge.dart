// Hooks the web build exposes to the native shell (lib/shell.dart); no-ops elsewhere.
export 'web_bridge_stub.dart' if (dart.library.js_interop) 'web_bridge_web.dart';
