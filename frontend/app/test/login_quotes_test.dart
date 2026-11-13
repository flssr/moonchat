import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moonchat/ui/login_quotes.dart';

/// 每次都返回区间里的最后一个值，用来钉住“首次抽取也能命中最后一条”。
class _LastIntRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => max - 1;
}

void main() {
  setUp(resetLoginQuoteHistory);

  test('首次进入可以抽到列表最后一条', () {
    final LoginQuote quote = nextLoginQuote(random: _LastIntRandom());
    expect(quote.text, kLoginQuotes.last.text);
  });

  test('登录引言都有正文与署名，且相邻两次不会重复', () {
    expect(kLoginQuotes.length, greaterThan(1));
    expect(
      kLoginQuotes.map((LoginQuote q) => q.text).toSet().length,
      kLoginQuotes.length,
      reason: '同一条文案不能出现两次，否则“不重复”会失效',
    );
    final Random random = Random(20261112);
    String? previous;
    for (int i = 0; i < kLoginQuotes.length * 5; i++) {
      final LoginQuote quote = nextLoginQuote(random: random);
      expect(quote.text.trim(), isNotEmpty);
      expect(quote.author.trim(), isNotEmpty);
      expect(quote.text, isNot(previous), reason: '连续两次进入登录页不能是同一句');
      previous = quote.text;
    }
  });
}
