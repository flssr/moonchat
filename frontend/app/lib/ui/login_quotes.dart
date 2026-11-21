import 'dart:math';

import 'package:flutter/foundation.dart';

/// 登录页的一句引言：说交流、相遇，以及人和机器怎么坐在同一张桌子边。
///
/// 文案放在这里，不参与任何业务状态；每次进入登录页取一句，避免连续重复。
/// 不选纯计算机科学的段子（算法、优化、架构），这类句子跟产品想说的不是一回事。
class LoginQuote {
  const LoginQuote(this.text, this.author);

  final String text;
  final String author;
}

const List<LoginQuote> kLoginQuotes = <LoginQuote>[
  LoginQuote('我们只能看到前方很短的一段，但那里已经有足够多的事情要做。', '艾伦·图灵'),
  LoginQuote('语言是误解的根源。', '圣埃克苏佩里'),
  LoginQuote('一切真实的生活都是相遇。', '马丁·布伯'),
  LoginQuote('语言是存在之家。', '海德格尔'),
  LoginQuote('我的语言的界限，意味着我的世界的界限。', '维特根斯坦'),
  LoginQuote('读书使人充实，讨论使人机智，笔记使人准确。', '弗朗西斯·培根'),
  LoginQuote('我们最好确信，交给机器的目的，正是我们真正想要的目的。', '诺伯特·维纳'),
  LoginQuote('你们说话，是当你们无法与自己的思想和平相处的时候。', '纪伯伦'),
  LoginQuote('有朋自远方来，不亦乐乎。', '孔子'),
  LoginQuote('独学而无友，则孤陋而寡闻。', '《礼记·学记》'),
  LoginQuote('信言不美，美言不信。', '老子'),
  LoginQuote('预测未来的最好方式，就是创造它。', '艾伦·凯'),
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
