/// App configuration.
///
/// Pass real values with:
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJ...
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://cbjmhkfqeeprcuqyyxrt.supabase.co',
  );
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNiam1oa2ZxZWVwcmN1cXl5eHJ0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTE3ODYzNTksImV4cCI6MjEwNzM2MjM1OX0.flkrszZyeJyrVPliGrxSSmhE-hW_4UgUKxdRHqLuANI',
  );

  static bool get isConfigured =>
      !supabaseUrl.contains('YOUR-PROJECT') &&
      !supabaseAnonKey.contains('YOUR-ANON-KEY');
}
