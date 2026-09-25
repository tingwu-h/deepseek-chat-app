/// 应用版本号。
///
/// 构建时由 tools/ascii_build.ps1 通过 --dart-define=APP_VERSION=x.y.z 注入，
/// 保证界面上显示的版本和 pubspec.yaml 永远一致（之前是写死的，改版本会忘）。
/// 本地直接 `flutter run` 时没有注入，回退到占位文案。
const String kAppVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '开发版',
);
