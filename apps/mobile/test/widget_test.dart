import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raaste/app.dart';
import 'package:raaste/core/di/injection.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await dotenv.load();
    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );
    await configureDependencies();
  });

  testWidgets('Raaste app renders splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const RaasteApp());
    expect(find.text('Raaste'), findsOneWidget);
  });
}
