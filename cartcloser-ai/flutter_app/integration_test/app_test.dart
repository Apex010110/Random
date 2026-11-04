// Device / browser integration test of the MRD acceptance demo.
// Android emulator:  flutter test integration_test/app_test.dart -d emulator-5554
// iOS simulator:     flutter test integration_test/app_test.dart -d "iPhone 16"
// Chrome:            flutter drive --driver=test_driver/integration_test.dart --target=integration_test/app_test.dart -d chrome
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/acceptance_flow.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('MRD acceptance demo on device (offline mode)', runAcceptance);
}
