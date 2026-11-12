import 'package:flutter_test/flutter_test.dart';
import 'package:moonchat/ui/constellation.dart';

void main() {
  test('生日边界落在正确的星座', () {
    expect(constellationOf(DateTime(2000, 1, 19)), '摩羯座');
    expect(constellationOf(DateTime(2000, 1, 20)), '水瓶座');
    expect(constellationOf(DateTime(2000, 2, 18)), '水瓶座');
    expect(constellationOf(DateTime(2000, 2, 19)), '双鱼座');
    expect(constellationOf(DateTime(2000, 2, 29)), '双鱼座');
    expect(constellationOf(DateTime(2000, 3, 20)), '双鱼座');
    expect(constellationOf(DateTime(2000, 3, 21)), '白羊座');
    expect(constellationOf(DateTime(2000, 4, 19)), '白羊座');
    expect(constellationOf(DateTime(2000, 4, 20)), '金牛座');
    expect(constellationOf(DateTime(2000, 5, 20)), '金牛座');
    expect(constellationOf(DateTime(2000, 5, 21)), '双子座');
    expect(constellationOf(DateTime(2000, 6, 21)), '双子座');
    expect(constellationOf(DateTime(2000, 6, 22)), '巨蟹座');
    expect(constellationOf(DateTime(2000, 7, 22)), '巨蟹座');
    expect(constellationOf(DateTime(2000, 7, 23)), '狮子座');
    expect(constellationOf(DateTime(2000, 8, 22)), '狮子座');
    expect(constellationOf(DateTime(2000, 8, 23)), '处女座');
    expect(constellationOf(DateTime(2000, 9, 22)), '处女座');
    expect(constellationOf(DateTime(2000, 9, 23)), '天秤座');
    expect(constellationOf(DateTime(2000, 10, 23)), '天秤座');
    expect(constellationOf(DateTime(2000, 10, 24)), '天蝎座');
    expect(constellationOf(DateTime(2000, 11, 22)), '天蝎座');
    expect(constellationOf(DateTime(2000, 11, 23)), '射手座');
    expect(constellationOf(DateTime(2000, 12, 21)), '射手座');
    expect(constellationOf(DateTime(2000, 12, 22)), '摩羯座');
  });
}
