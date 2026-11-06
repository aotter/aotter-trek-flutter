import 'package:flutter_test/flutter_test.dart';
import 'package:trek_gma_mediation_example/main.dart';

void main() {
  testWidgets('home page lists the pages and the Ad Inspector', (tester) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('Native ads in a feed'), findsOneWidget);
    expect(find.text('Banner ad'), findsOneWidget);
    expect(find.text('Ad Inspector'), findsOneWidget);
  });
}
