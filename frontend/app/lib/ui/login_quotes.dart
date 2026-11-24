import 'dart:math';

import 'package:flutter/foundation.dart';

/// 登录页的一句引言：说人和机器怎么一起待着。
///
/// 文案放在这里，不参与任何业务状态；每次进入登录页取一句，避免连续重复。
/// 选句标准是「人机共生」：工具怎么塑造人、人怎么和会说话的机器相处。
/// 只讲语言、相遇、聊天的句子和纯计算机科学的段子都不选。
class LoginQuote {
  const LoginQuote(this.text, this.author);

  final String text;
  final String author;
}

const List<LoginQuote> kLoginQuotes = <LoginQuote>[
  LoginQuote('我们塑造工具，然后工具塑造我们。', '马歇尔·麦克卢汉'),
  LoginQuote('计算机是人类心灵的自行车。', '史蒂夫·乔布斯'),
  LoginQuote('我不害怕计算机，我害怕的是没有它们。', '艾萨克·阿西莫夫'),
  LoginQuote('我们都是赛博格。', '唐娜·哈拉维'),
  LoginQuote('我们的书写工具也在参与我们的思考。', '尼采'),
  LoginQuote('我们最好确信，交给机器的目的，正是我们真正想要的目的。', '诺伯特·维纳'),
  LoginQuote('人工智能或许是我们最好的事，也或许是最坏的。', '斯蒂芬·霍金'),
  LoginQuote('天地与我并生，而万物与我为一。', '庄子'),
  LoginQuote('我们只能看到前方很短的一段，但那里已经有足够多的事情要做。', '艾伦·图灵'),
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
