/// 应用版本号。
///
/// 这个常量由构建脚本 tools/ascii_build.ps1 在编译前**改写成本次版本号**
/// （从构建副本的 pubspec.yaml 取），保证界面显示的版本永远和发出去的包一致。
///
/// 为什么不用 --dart-define + String.fromEnvironment：
/// 注入的值在 AOT 产物里取不到（实测），装到手机上会显示成兜底文案。
/// 直接写成源码里的 const 是编译期字面量，最可靠。
///
/// 下面这个默认值必须与 pubspec.yaml 的 version 保持一致
/// （test/unit_test.dart 里有测试守着，改 pubspec 忘改这里会测试失败）。
const String kAppVersion = '1.1.2';
