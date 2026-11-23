import 'package:flutter/foundation.dart';
import '../platform/local_user_state.dart';

/// A device-local visual preference. Never stores credentials or business data.
class BackgroundDecoration extends ValueNotifier<bool> {
  BackgroundDecoration() : super(true);
  static final instance = BackgroundDecoration();
  void restore() {
    value =
        LocalUserState.read('appearance', 'background')?['enabled'] != false;
  }

  void select(bool enabled) {
    value = enabled;
    LocalUserState.write('appearance', 'background', {'enabled': enabled});
  }
}
