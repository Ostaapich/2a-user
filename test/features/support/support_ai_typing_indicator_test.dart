import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/support/presentation/support_ai_typing_indicator.dart';

Widget host({
  bool reduceMotion = false,
  bool chinese = false,
  double scale = 1,
}) {
  return MaterialApp(
    locale: Locale(chinese ? 'zh' : 'ru'),
    supportedLocales: const [Locale('ru'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQueryData(
        disableAnimations: reduceMotion,
        textScaler: TextScaler.linear(scale),
      ),
      child: child!,
    ),
    home: const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(16),
        child: SupportAiTypingIndicator(),
      ),
    ),
  );
}

void main() {
  testWidgets('typing dots animate without changing the accessible status', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(host());
    expect(find.text('Помощник печатает'), findsOneWidget);
    expect(find.bySemanticsLabel('Помощник печатает…'), findsOneWidget);
    final dot = find.byKey(const ValueKey('assistant-typing-dot-0'));
    final before = tester.widget<Opacity>(dot).opacity;
    await tester.pump(const Duration(milliseconds: 180));
    expect(tester.widget<Opacity>(dot).opacity, isNot(before));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('reduced motion keeps dots static and Chinese label localized', (
    tester,
  ) async {
    await tester.pumpWidget(host(reduceMotion: true, chinese: true));
    expect(find.text('助手正在输入'), findsOneWidget);
    final dot = find.byKey(const ValueKey('assistant-typing-dot-0'));
    final before = tester.widget<Opacity>(dot).opacity;
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<Opacity>(dot).opacity, before);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('typing bubble fits narrow screens and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(host(scale: 1.8));
    expect(find.text('Помощник печатает'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
