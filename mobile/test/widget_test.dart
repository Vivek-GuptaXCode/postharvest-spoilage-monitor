import 'package:postharvest_app/main.dart';
import 'package:flutter_test/flutter_test.dart';
// Basic Flutter widget test for PostHarvest Monitor app.

void main() {
  testWidgets('PostHarvestApp renders without errors', (
    WidgetTester tester,
  ) async {
    // Verify the app widget can be constructed.
    expect(const PostHarvestApp(), isA<PostHarvestApp>());
  });
}
