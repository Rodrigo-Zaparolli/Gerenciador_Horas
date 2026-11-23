import 'dart:js_interop';

@JS('projectPdfWindows.open')
external JSBoolean _open(
    JSString key, JSString pdf, JSString title, JSBoolean draft);
@JS('projectPdfWindows.update')
external void _update(
    JSString key, JSString pdf, JSString title, JSBoolean draft);
@JS('projectPdfWindows.close')
external void _close(JSString key);
@JS('projectPdfWindows.stale')
external void _stale(JSString key);
@JS('projectPdfWindows.isOpen')
external JSBoolean _isOpen(JSString key);

bool openProjectPdfWindow(String key, String pdf, String title, bool draft) {
  try {
    return _open(key.toJS, pdf.toJS, title.toJS, draft.toJS).toDart;
  } catch (_) {
    return false;
  }
}

void updateProjectPdfWindow(String key, String pdf, String title, bool draft) {
  try {
    _update(key.toJS, pdf.toJS, title.toJS, draft.toJS);
  } catch (_) {}
}

void closeProjectPdfWindow(String key) {
  try {
    _close(key.toJS);
  } catch (_) {}
}

void markProjectPdfWindowStale(String key) {
  try {
    _stale(key.toJS);
  } catch (_) {}
}

bool projectPdfWindowOpen(String key) {
  try {
    return _isOpen(key.toJS).toDart;
  } catch (_) {
    return false;
  }
}
