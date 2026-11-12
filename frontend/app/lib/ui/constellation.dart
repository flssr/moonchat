/// 生日 → 星座。只做客户端展示，不落库（后端 issue #5）。
String constellationOf(DateTime birthday) {
  const List<(int, int, String)> starts = <(int, int, String)>[
    (1, 20, '水瓶座'),
    (2, 19, '双鱼座'),
    (3, 21, '白羊座'),
    (4, 20, '金牛座'),
    (5, 21, '双子座'),
    (6, 22, '巨蟹座'),
    (7, 23, '狮子座'),
    (8, 23, '处女座'),
    (9, 23, '天秤座'),
    (10, 24, '天蝎座'),
    (11, 23, '射手座'),
    (12, 22, '摩羯座'),
  ];
  // 1 月 1–19 日落在上一年的摩羯区间；没有更晚的起点覆盖它。
  String result = '摩羯座';
  for (final (int month, int day, String sign) in starts) {
    if (birthday.month > month ||
        (birthday.month == month && birthday.day >= day)) {
      result = sign;
    }
  }
  return result;
}
