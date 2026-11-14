import 'dart:async';

import 'package:flutter/material.dart';

import 'sky.dart';
import 'theme.dart';

class _Msg {
  _Msg({required this.from, required this.text, this.time = '', this.media});

  final bool from; // true = me
  final String text;
  final String time;
  final String? media;
}

class _Conv {
  _Conv({
    required this.name,
    required this.short,
    required this.emoji,
    required this.preview,
    required this.time,
    required this.status,
    required this.colors,
    required this.messages,
    required this.replies,
    this.unread = 0,
    this.group = false,
  });

  final String name;
  final String short;
  final String emoji;
  final String preview;
  final String time;
  final String status;
  final List<Color> colors;
  final List<_Msg> messages;
  final List<String> replies;
  int unread;
  final bool group;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _search = TextEditingController();

  int _active = 0;
  String _query = '';
  bool _showInfo = true;
  bool _typing = false;
  Timer? _replyTimer;

  static const _c1 = [Color(0xFF3F5F9E), Color(0xFF1D2C4F)];
  static const _c2 = [Color(0xFF8A5A3C), Color(0xFF3A2418)];
  static const _c3 = [Color(0xFF2F6B6A), Color(0xFF123033)];
  static const _c4 = [Color(0xFF5B4A8A), Color(0xFF241C3D)];
  static const _c5 = [Color(0xFF7A3B5C), Color(0xFF2B1526)];
  static const _c6 = [Color(0xFF3A6A86), Color(0xFF152C3A)];

  final List<_Conv> _convs = [
    _Conv(
      name: '月面基地 · Luna',
      short: 'Luna',
      emoji: '🌙',
      preview: '欢迎登舰，舱内一切就绪',
      time: '21:04',
      status: '在线 · 第 3 号舷窗',
      colors: _c1,
      messages: [
        _Msg(from: false, text: '舱门已关闭，欢迎登舰 🚀', time: '21:04'),
        _Msg(from: false, text: '', time: '21:04', media: 'assets/rocket_closed.png'),
        _Msg(from: true, text: '终于上来了，外面星星真多。', time: '21:05'),
        _Msg(from: false, text: '这里是月面基地 A-07，你的频道已经接入全站。\n想聊什么都可以，我在。', time: '21:05'),
      ],
      replies: ['收到，信号很清楚 📡', '月面这边一切正常，窗外的地球正好升起来。', '那就说定了，环形山见 🌑', '我把频道调到最佳了，继续说。'],
    ),
    _Conv(
      name: '轨道咖啡屋',
      short: '咖啡屋',
      emoji: '☕',
      preview: '阿澈：今晚的月食别错过',
      time: '20:41',
      status: '12 人在线 · 环形山露台',
      colors: _c2,
      unread: 2,
      group: true,
      messages: [
        _Msg(from: false, text: '今晚 23:40 有月食，露台的位子我占了三个。', time: '20:38'),
        _Msg(from: false, text: '带了两罐冰的月尘汽水 🥤', time: '20:40'),
        _Msg(from: false, text: '今晚的月食别错过', time: '20:41'),
      ],
      replies: ['给我留一个位子！', '我带点吃的过去 🍪', '月尘汽水听起来很不错。'],
    ),
    _Conv(
      name: '阿波罗计划',
      short: '阿波罗',
      emoji: '🛰️',
      preview: '第 3 次对接演练已排期',
      time: '19:12',
      status: '8 人在线 · 任务频道',
      colors: _c3,
      group: true,
      messages: [
        _Msg(from: false, text: '第 3 次对接演练已排期：明日 09:00（月面时间）。', time: '19:12'),
        _Msg(from: true, text: '收到，我会提前 20 分钟进舱。', time: '19:20'),
      ],
      replies: ['演练流程已同步到你的终端。', '注意检查氧气循环，上次有点抖。'],
    ),
    _Conv(
      name: '星尘电台',
      short: '星尘',
      emoji: '📻',
      preview: '新一期：低频宇宙',
      time: '昨天',
      status: '正在广播 · 88.4 MHz',
      colors: _c4,
      messages: [
        _Msg(from: false, text: '新一期《低频宇宙》上线了，适合在舱里发呆的时候听。', time: '昨天 22:10'),
      ],
      replies: ['正在听，风的声音很干净。', '下一期想听地球的海。'],
    ),
    _Conv(
      name: 'Neo',
      short: 'Neo',
      emoji: '🌠',
      preview: '在吗？',
      time: '昨天',
      status: '离开 · 2 小时前',
      colors: _c5,
      messages: [
        _Msg(from: false, text: '在吗？', time: '昨天 18:02'),
        _Msg(from: true, text: '刚回来，怎么了？', time: '昨天 18:40'),
      ],
      replies: ['没什么，就是想找个人说说话。', '你那边能看到地球吗？'],
    ),
    _Conv(
      name: '月面天气',
      short: '天气',
      emoji: '⛅',
      preview: '今日无尘暴，适合出舱',
      time: '周一',
      status: '自动播报 · 每日 06:00',
      colors: _c6,
      messages: [
        _Msg(from: false, text: '今日无尘暴，能见度 18 km，适合出舱。', time: '周一 06:00'),
        _Msg(from: false, text: '夜间最低 -173°C，记得把加热开到 3 档。', time: '周一 06:00'),
      ],
      replies: ['收到，今天出门走走。', '帮我记一下明天的天气。'],
    ),
  ];

  _Conv get _conv => _convs[_active];

  @override
  void dispose() {
    _replyTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _active) return;
    setState(() {
      _active = i;
      _convs[i].unread = 0;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final now = TimeOfDay.now();
    final stamp = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    setState(() {
      _conv.messages.add(_Msg(from: true, text: text, time: stamp));
      _input.clear();
    });
    _scrollToEnd();

    _replyTimer?.cancel();
    _replyTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _typing = true);
      _scrollToEnd();
      _replyTimer = Timer(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        final reply = _conv.replies[_conv.messages.length % _conv.replies.length];
        setState(() {
          _typing = false;
          _conv.messages.add(_Msg(from: false, text: reply, time: stamp));
        });
        _scrollToEnd();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: SkyBackdrop()),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final showSidebar = w > 900;
                final showInfo = _showInfo && w > 1180;
                final frameW = w > 1360 ? 1300.0 : w * 0.96;
                final frameH = c.maxHeight > 940 ? 880.0 : c.maxHeight * 0.93;

                return Center(
                  child: SizedBox(
                    width: frameW,
                    height: frameH,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(26),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xE0101F3C), Color(0xF00A1327)],
                          ),
                          border: Border.all(color: MoonColors.line),
                          boxShadow: const [
                            BoxShadow(color: Color(0xB3000000), blurRadius: 90, offset: Offset(0, 40)),
                          ],
                        ),
                        child: Row(
                          children: [
                            _rail(),
                            if (showSidebar) _sidebar(),
                            Expanded(child: _room()),
                            if (showInfo) _info(),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /* ------------------------------------------------------------------ */

  Widget _rail() {
    return Container(
      width: 76,
      decoration: const BoxDecoration(
        color: Color(0x40050B18),
        border: Border(right: BorderSide(color: MoonColors.lineSoft)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset('assets/logo.png', width: 42, height: 42),
          ),
          const SizedBox(height: 18),
          _railButton(Icons.chat_bubble_outline_rounded, true),
          _railButton(Icons.people_outline_rounded, false),
          _railButton(Icons.explore_outlined, false),
          _railButton(Icons.settings_outlined, false),
          const Spacer(),
          _railButton(Icons.logout_rounded, false),
          const SizedBox(height: 10),
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(colors: [Color(0xFFF6D9A8), Color(0xFFE0AA6E)]),
            ),
            child: const Text('你', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF22160A))),
          ),
          const SizedBox(height: 22),
        ],
      ),
    );
  }

  Widget _railButton(IconData icon, bool active) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          color: active ? const Color(0x3D5A8CFF) : Colors.transparent,
          border: active ? Border.all(color: const Color(0x388CBEff)) : null,
        ),
        child: Icon(icon, size: 20, color: active ? const Color(0xFFDCEAFF) : MoonColors.ink3),
      ),
    );
  }

  /* ------------------------------------------------------------------ */

  Widget _sidebar() {
    final list = _convs.where((c) {
      if (_query.isEmpty) return true;
      return c.name.contains(_query) || c.preview.contains(_query);
    }).toList();

    return Container(
      width: 312,
      decoration: const BoxDecoration(
        color: Color(0x33070E1E),
        border: Border(right: BorderSide(color: MoonColors.lineSoft)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 14, 16),
            child: Row(
              children: [
                const Text('消息', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0x12FFFFFF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${list.length}', style: const TextStyle(fontSize: 10, color: MoonColors.ink2)),
                ),
                const Spacer(),
                Icon(Icons.add_rounded, size: 20, color: MoonColors.ink3),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0x0AFFFFFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0x1A8FBEEF)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded, size: 17, color: MoonColors.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v.trim()),
                      style: const TextStyle(fontSize: 13),
                      cursorColor: MoonColors.blue,
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: '搜索月面频道',
                        hintStyle: TextStyle(fontSize: 13, color: MoonColors.ink3),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                _tab('全部', active: true),
                const SizedBox(width: 4),
                _tab('未读 2'),
                const SizedBox(width: 4),
                _tab('群组'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final conv = list[i];
                final index = _convs.indexOf(conv);
                return _convTile(conv, index);
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: MoonColors.lineSoft))),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(colors: [Color(0xFFF6D9A8), Color(0xFFE0AA6E)]),
                  ),
                  child: const Text('你', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF22160A))),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('访客宇航员', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
                      SizedBox(height: 2),
                      Text('月面基地 · A-07 舱', style: TextStyle(fontSize: 10.5, color: MoonColors.ink3)),
                    ],
                  ),
                ),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF63E0A0),
                    boxShadow: [BoxShadow(color: Color(0xAA63E0A0), blurRadius: 8)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tab(String label, {bool active = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active ? const Color(0x14FFFFFF) : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: active ? MoonColors.ink : MoonColors.ink3),
      ),
    );
  }

  Widget _convTile(_Conv conv, int index) {
    final active = index == _active;
    return GestureDetector(
      onTap: () => _select(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: active
              ? const LinearGradient(colors: [Color(0x2E508CFF), Color(0x0A508CFF)])
              : null,
          border: active ? Border.all(color: const Color(0x2E8CBEff)) : null,
        ),
        child: Row(
          children: [
            _avatar(conv.emoji, conv.colors, 42),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conv.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: MoonColors.ink),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    conv.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: active ? MoonColors.ink2 : MoonColors.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(conv.time, style: const TextStyle(fontSize: 10, color: MoonColors.ink3)),
                const SizedBox(height: 6),
                if (conv.unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      gradient: const LinearGradient(colors: [Color(0xFF5A9BFF), Color(0xFF3D6BFF)]),
                    ),
                    child: Text('${conv.unread}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatar(String emoji, List<Color> colors, double size) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: colors),
        border: Border.all(color: const Color(0x1AFFFFFF)),
      ),
      child: Text(emoji, style: TextStyle(fontSize: size * 0.46)),
    );
  }

  /* ------------------------------------------------------------------ */

  Widget _room() {
    final conv = _conv;
    return Column(
      children: [
        Container(
          height: 74,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            color: Color(0x33081022),
            border: Border(bottom: BorderSide(color: MoonColors.lineSoft)),
          ),
          child: Row(
            children: [
              _avatar(conv.emoji, conv.colors, 44),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(conv.name, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFF63E0A0),
                          boxShadow: [BoxShadow(color: Color(0xAA63E0A0), blurRadius: 8)],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(conv.status, style: const TextStyle(fontSize: 11, color: MoonColors.ink3)),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              _headButton(Icons.call_outlined),
              _headButton(Icons.videocam_outlined),
              _headButton(Icons.info_outline_rounded, active: _showInfo, onTap: () => setState(() => _showInfo = !_showInfo)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 6),
            itemCount: 1 + conv.messages.length + (_typing ? 1 : 0),
            itemBuilder: (context, i) {
              if (i == 0) return _dayChip();
              final mi = i - 1;
              if (mi < conv.messages.length) return _bubble(conv, conv.messages[mi]);
              return _typingBubble(conv);
            },
          ),
        ),
        _composer(),
      ],
    );
  }

  Widget _headButton(IconData icon, {bool active = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        margin: const EdgeInsets.only(left: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: active ? const Color(0x1F5A96FF) : Colors.transparent,
        ),
        child: Icon(icon, size: 18, color: active ? MoonColors.blue : MoonColors.ink3),
      ),
    );
  }

  Widget _dayChip() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14, top: 2),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0x0AFFFFFF),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x148FBEEF)),
          ),
          child: const Text('今天 · 登舱第 1 天', style: TextStyle(fontSize: 10.5, letterSpacing: 0.8, color: MoonColors.ink3)),
        ),
      ),
    );
  }

  Widget _bubble(_Conv conv, _Msg msg) {
    final mine = msg.from;
    final bubble = Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: msg.media != null ? const EdgeInsets.all(6) : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: mine
            ? const LinearGradient(colors: [Color(0xFF4F8BFF), Color(0xFF6F6BFF)])
            : null,
        color: mine ? null : const Color(0x0EFFFFFF),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(mine ? 16 : 5),
          bottomRight: Radius.circular(mine ? 5 : 16),
        ),
        border: mine ? Border.all(color: const Color(0x4DA0BEff)) : Border.all(color: const Color(0x148FBEEF)),
        boxShadow: mine
            ? const [BoxShadow(color: Color(0x8C466EFF), blurRadius: 26, offset: Offset(0, 10))]
            : const [BoxShadow(color: Color(0x2E000000), blurRadius: 16)],
      ),
      child: msg.media != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 200,
                    height: 140,
                    color: const Color(0xFF0D1730),
                    padding: const EdgeInsets.all(8),
                    child: Image.asset(msg.media!, fit: BoxFit.contain),
                  ),
                ),
                const SizedBox(height: 6),
                const Text('📎 你的座驾已就位', style: TextStyle(fontSize: 11.5, color: MoonColors.ink2)),
              ],
            )
          : Text(
              msg.text,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: mine ? Colors.white : const Color(0xFFE4EDFF),
              ),
            ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!mine) ...[
            _avatar(conv.emoji, conv.colors, 30),
            const SizedBox(width: 10),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                bubble,
                const SizedBox(height: 4),
                Text(msg.time, style: const TextStyle(fontSize: 9.5, color: MoonColors.ink3)),
              ],
            ),
          ),
          if (mine) ...[
            const SizedBox(width: 10),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFFF6D9A8), Color(0xFFE0AA6E)]),
              ),
              child: const Text('你', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF22160A))),
            ),
          ],
        ],
      ),
    );
  }

  Widget _typingBubble(_Conv conv) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          _avatar(conv.emoji, conv.colors, 30),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0x0EFFFFFF),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(5),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: const Color(0x148FBEEF)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(
                3,
                (i) => Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: MoonColors.ink2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0x0AFFFFFF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x1F8FBEEF)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Icon(Icons.add_rounded, size: 20, color: MoonColors.ink3),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(fontSize: 13.5),
                    cursorColor: MoonColors.blue,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: '发一条消息给 Luna…',
                      hintStyle: TextStyle(fontSize: 13.5, color: MoonColors.ink3),
                      contentPadding: EdgeInsets.symmetric(vertical: 9),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.sentiment_satisfied_alt_outlined, size: 19, color: MoonColors.ink3),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _send,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(colors: [Color(0xFF6FB6FF), Color(0xFF4F7BFF), Color(0xFF6F5BFF)]),
                      boxShadow: const [BoxShadow(color: Color(0x8C4678FF), blurRadius: 20, offset: Offset(0, 8))],
                    ),
                    child: const Icon(Icons.send_rounded, size: 17, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.only(left: 4),
            child: Text('Enter 发送 · Shift + Enter 换行', style: TextStyle(fontSize: 10, color: MoonColors.ink3)),
          ),
        ],
      ),
    );
  }

  /* ------------------------------------------------------------------ */

  Widget _info() {
    final conv = _conv;
    return Container(
      width: 300,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0x33070E1E),
        border: Border(left: BorderSide(color: MoonColors.lineSoft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('会话信息', style: TextStyle(fontSize: 12, letterSpacing: 1.2, color: MoonColors.ink3)),
              const Spacer(),
              GestureDetector(
                onTap: () => setState(() => _showInfo = false),
                child: const Icon(Icons.chevron_right_rounded, size: 20, color: MoonColors.ink3),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Column(
              children: [
                _avatar(conv.emoji, conv.colors, 76),
                const SizedBox(height: 12),
                Text(conv.short, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                const Text('月面基地 · 频道主理人', style: TextStyle(fontSize: 11, color: MoonColors.ink3)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _chip('在线', const Color(0xFFA8E7C4), const Color(0x1A64DCA0)),
                    const SizedBox(width: 6),
                    _chip('已认证', const Color(0xFFBCD4FF), const Color(0x1A6EA0FF)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Divider(color: MoonColors.lineSoft, height: 1),
          _switchRow(Icons.notifications_none_rounded, '免打扰', false),
          _switchRow(Icons.push_pin_outlined, '置顶会话', true),
          const SizedBox(height: 6),
          const Text('共享星图  3', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: MoonColors.ink3)),
          const SizedBox(height: 10),
          Row(
            children: [
              _shot(Image.asset('assets/rocket_closed.png', fit: BoxFit.contain)),
              const SizedBox(width: 6),
              _shot(Container(decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xFFFFFDF6), Color(0xFFD9CFB6)])))),
              const SizedBox(width: 6),
              _shot(Container(color: const Color(0xFF0B1730))),
            ],
          ),
          const SizedBox(height: 18),
          const Text('舱位数据', style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: MoonColors.ink3)),
          const SizedBox(height: 10),
          _statRow('轨道高度', '384,400 km'),
          _statRow('舱位编号', 'A-07'),
          _statRow('信号延迟', '1.28 s'),
          const Spacer(),
          const Text(
            '你与 Luna 的对话已端到端加密，仅在这片月面上存在。',
            style: TextStyle(fontSize: 10.5, height: 1.7, color: MoonColors.ink3),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(label, style: TextStyle(fontSize: 10, color: color)),
    );
  }

  Widget _switchRow(IconData icon, String label, bool on) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: MoonColors.ink3),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 12.5, color: MoonColors.ink2)),
          const Spacer(),
          Container(
            width: 30,
            height: 17,
            padding: const EdgeInsets.all(2),
            alignment: on ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: on ? const Color(0xB35A96FF) : const Color(0x1F9FB9E0),
            ),
            child: Container(
              width: 13,
              height: 13,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shot(Widget child) {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF0C1730),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0x1F8FBEEF)),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _statRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(key, style: const TextStyle(fontSize: 11.5, color: MoonColors.ink3)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 11.5, color: MoonColors.ink2)),
        ],
      ),
    );
  }
}

