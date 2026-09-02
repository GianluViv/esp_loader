import 'package:esp_loader/main.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpDesktop(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const EspLoaderApp());
    await tester.pumpAndSettle();
  }

  testWidgets('shows the desktop navigation', (tester) async {
    await pumpDesktop(tester);
    expect(find.text('ESP Loader'), findsNothing);
    expect(find.text('Programming'), findsWidgets);
    expect(find.text('Monitor'), findsOneWidget);
    expect(find.text('Plot'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
  testWidgets('toggles technical log from serial controls', (tester) async {
    await pumpDesktop(tester);
    expect(find.textContaining(r'$ esptool'), findsNothing);
    await tester.tap(find.byKey(const Key('technical-log-button')));
    await tester.pumpAndSettle();
    expect(find.textContaining(r'$ esptool'), findsOneWidget);
  });
  testWidgets('starts simulated flash', (tester) async {
    await pumpDesktop(tester);
    await tester.tap(find.byKey(const Key('start-flash-button')));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.textContaining('Writing'), findsOneWidget);
  });
}
