import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mondchat/theme.dart';
import 'package:mondchat/ui/login_stage.dart';

void main() {
  testWidgets('登舱飞离：机身朝月亮倾斜并缩小', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildMoonTheme(Brightness.light),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 611,
              height: 540,
              child: LoginStage(
                arrival: const AlwaysStoppedAnimation<double>(0.5),
                label: '发射基地',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final List<Transform> transforms =
        tester.widgetList<Transform>(find.byType(Transform)).toList();

    // 倾角：旋转矩阵的 m[1] = sinθ。月亮在右上，θ 应为正。
    final Iterable<Transform> tilted =
        transforms.where((Transform t) => t.transform.storage[1] > 0.1);
    expect(tilted, isNotEmpty, reason: '飞离时火箭应朝月亮方向倾斜');

    // 收缩：缩放矩阵没有旋转分量（m[4] ≈ 0），两条对角线都明显小于 1。
    final Iterable<Transform> scaled = transforms.where((Transform t) =>
        t.transform.storage[4].abs() < 0.01 &&
        t.transform.storage[0] < 0.9 &&
        t.transform.storage[5] < 0.9);
    expect(scaled, isNotEmpty, reason: '飞离时火箭应缩小');
  });
}
