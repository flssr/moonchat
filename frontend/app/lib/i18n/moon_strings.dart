/// 设置页与导航用的最小文案表。其他页面仍按中文渲染，后续可按同一 key 分批接入。
String moonText(String languageCode, String zh) {
  final Map<String, String>? table = _tables[languageCode];
  assert(
    languageCode == 'zh' || table?.containsKey(zh) == true,
    'missing translation for "$zh" in "$languageCode"',
  );
  return table?[zh] ?? zh;
}

/// 只给测试与调试用：检查某条中文 key 在该语言里有没有显式翻译。
bool moonHasText(String languageCode, String zh) =>
    languageCode == 'zh' || _tables[languageCode]?.containsKey(zh) == true;

/// 设置页与 `MaterialApp.supportedLocales` 共用同一张语言清单。
const List<(String, String)> kMoonLanguages = <(String, String)>[
  ('zh', '中文'),
  ('en', 'English'),
  ('ja', '日本語'),
  ('de', 'Deutsch'),
];

const Map<String, Map<String, String>> _tables = <String, Map<String, String>>{
  'en': <String, String>{
    '消息': 'Messages',
    '联系人': 'Contacts',
    '账号': 'Account',
    '个人资料': 'Profile',
    '设置': 'Settings',
    '切到亮色': 'Switch to light',
    '切到暗色': 'Switch to dark',
    '退出登录': 'Sign out',
    '字体': 'Font',
    '小': 'Small',
    '中': 'Medium',
    '大': 'Large',
    '语言': 'Language',
    '隐私': 'Privacy',
    '黑名单管理': 'Blocklist',
    '我的友情关系': 'My friendships',
    '敬请期待': 'Coming soon',
    '待接入': 'Pending',
    '关闭': 'Close',
  },
  'ja': <String, String>{
    '消息': 'メッセージ',
    '联系人': '連絡先',
    '账号': 'アカウント',
    '个人资料': 'プロフィール',
    '设置': '設定',
    '切到亮色': 'ライトに切り替え',
    '切到暗色': 'ダークに切り替え',
    '退出登录': 'ログアウト',
    '字体': 'フォント',
    '小': '小',
    '中': '中',
    '大': '大',
    '语言': '言語',
    '隐私': 'プライバシー',
    '黑名单管理': 'ブロックリスト',
    '我的友情关系': '友達関係',
    '敬请期待': 'お楽しみに',
    '待接入': '準備中',
    '关闭': '閉じる',
  },
  'de': <String, String>{
    '消息': 'Nachrichten',
    '联系人': 'Kontakte',
    '账号': 'Konto',
    '个人资料': 'Profil',
    '设置': 'Einstellungen',
    '切到亮色': 'Zum hellen Modus',
    '切到暗色': 'Zum dunklen Modus',
    '退出登录': 'Abmelden',
    '字体': 'Schrift',
    '小': 'Klein',
    '中': 'Mittel',
    '大': 'Groß',
    '语言': 'Sprache',
    '隐私': 'Privatsphäre',
    '黑名单管理': 'Sperrliste',
    '我的友情关系': 'Meine Freundschaften',
    '敬请期待': 'Bald verfügbar',
    '待接入': 'In Arbeit',
    '关闭': 'Schließen',
  },
};
