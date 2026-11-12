import 'dart:math';

import 'package:flutter/foundation.dart';

/// 登录页的一句计算机科学 / AI 引言。
///
/// 文案放在这里，不参与任何业务状态；每次进入登录页取一句，避免连续重复。
class LoginQuote {
  const LoginQuote(this.text, this.author);

  final String text;
  final String author;
}

const List<LoginQuote> kLoginQuotes = <LoginQuote>[
  LoginQuote('我们只能看到前方很短的一段，但那里已经有足够多的事情要做。', '艾伦·图灵'),
  LoginQuote('分析机没有声称自己能创造任何东西。它只能执行我们知道如何命令它执行的事情。', '埃达·洛芙莱斯'),
  LoginQuote('计算机能否思考，这个问题并不比潜艇能否游泳更有趣。', '艾兹格·迪杰斯特拉'),
  LoginQuote('计算机科学并不只是关于计算机，就像天文学并不只是关于望远镜一样。', '艾兹格·迪杰斯特拉'),
  LoginQuote('人工智能是让机器去做那些如果由人来做就需要智能的事情的科学。', '马文·明斯基'),
  LoginQuote('预测未来的最好方式，就是创造它。', '艾伦·凯'),
  LoginQuote('真正的问题不是机器是否会思考，而是人是否会思考。', 'B.F. 斯金纳'),
  LoginQuote('人工智能是新的电力。', '吴恩达'),
  LoginQuote('最危险的一句话是：我们一直都是这么做的。', '格蕾丝·霍珀'),
  LoginQuote('过早优化是万恶之源。', '唐纳德·克努特'),
  LoginQuote('我无法创造的东西，我就无法理解。', '理查德·费曼'),
  LoginQuote('注意力就是你所需要的一切。', '阿希什·瓦西瓦尼等'),
];

int? _lastIndex;

/// 只给测试用：清掉「上一句」，让每个用例从已知状态开始。
@visibleForTesting
void resetLoginQuoteHistory() {
  _lastIndex = null;
}

/// 随机取一句，并保证不与上一次取到的重复。
LoginQuote nextLoginQuote({Random? random}) {
  assert(kLoginQuotes.isNotEmpty, '登录引言不能为空');
  if (kLoginQuotes.length == 1) {
    return kLoginQuotes.single;
  }
  final Random rng = random ?? Random();
  final int? last = _lastIndex;
  int index;
  if (last == null) {
    // 首次进入没有“上一句”，在全部条目里抽，别把最后一条排除掉。
    index = rng.nextInt(kLoginQuotes.length);
  } else {
    index = rng.nextInt(kLoginQuotes.length - 1);
    if (index >= last) {
      index++;
    }
  }
  _lastIndex = index;
  return kLoginQuotes[index];
}
