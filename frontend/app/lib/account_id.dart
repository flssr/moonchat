/// 账号短号：后端 `account.id` 从 1 亿起（`V1__biz_account.sql` 的 identity start），
/// 它同时是 Turms 用户 id。界面只在**显示与查找输入**这一层把它折成从 1 起的短号，
/// 不改 id 本身，也不碰后端。
///
/// 这层约定依赖后端 identity 的起点；后端如果改起点（issue #36 的另一种方案），
/// 这里要一起改。完整 id（≥ 1 亿）在输入框里仍然原样接受。
const int kAccountIdBase = 100000000;

/// 100000000 → 1，100000001 → 2；不在短号区间的 id（如测试里的 1）原样显示。
String shortAccountId(int accountId) =>
    accountId >= kAccountIdBase ? '${accountId - kAccountIdBase + 1}' : '$accountId';

/// 输入框：短号（1 → 100000000）或完整账号 id 都接受；非法输入返回 null。
int? accountIdFromInput(String raw) {
  final int? value = int.tryParse(raw.trim());
  if (value == null || value <= 0) {
    return null;
  }
  return value < kAccountIdBase ? kAccountIdBase + value - 1 : value;
}
