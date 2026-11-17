import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../account_id.dart';
import '../api/models.dart';
import '../i18n/context_tr.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'widgets.dart';

/// 只从好友里选人（建群/拉群共用）。搜索框只认好友短号，找不到就是「无此好友」。
Future<List<int>?> showFriendPicker(
  BuildContext context, {
  required AppState state,
  Set<int> exclude = const <int>{},
  bool multi = false,
}) {
  return showDialog<List<int>>(
    context: context,
    builder: (BuildContext context) => _FriendPicker(
      state: state,
      exclude: exclude,
      multi: multi,
    ),
  );
}

class _FriendPicker extends StatefulWidget {
  const _FriendPicker({
    required this.state,
    required this.exclude,
    required this.multi,
  });

  final AppState state;
  final Set<int> exclude;
  final bool multi;

  @override
  State<_FriendPicker> createState() => _FriendPickerState();
}

class _FriendPickerState extends State<_FriendPicker> {
  final TextEditingController _search = TextEditingController();
  final Set<int> _selected = <int>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Friendship> get _all => widget.state.friends
      .where((Friendship f) => !widget.exclude.contains(f.peerAccountId))
      .toList(growable: false);

  List<Friendship> get _shown {
    final String raw = _search.text.trim();
    if (raw.isEmpty) {
      return _all;
    }
    final int? id = accountIdFromInput(raw);
    if (id == null) {
      return const <Friendship>[];
    }
    return _all.where((Friendship f) => f.peerAccountId == id).toList(growable: false);
  }

  bool get _noFriend => _search.text.trim().isNotEmpty && _shown.isEmpty;

  void _toggle(Friendship f) {
    setState(() {
      if (widget.multi) {
        if (!_selected.add(f.peerAccountId)) {
          _selected.remove(f.peerAccountId);
        }
      } else {
        _selected
          ..clear()
          ..add(f.peerAccountId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    final List<Friendship> shown = _shown;
    return AlertDialog(
      backgroundColor: p.surface,
      title: Text(
        context.tr(widget.multi ? '邀请好友' : '选择好友'),
        style: TextStyle(fontSize: 16, color: p.ink),
      ),
      content: SizedBox(
        width: 360,
        height: 420,
        child: Column(
          children: <Widget>[
            Container(
              height: 40,
              decoration: BoxDecoration(
                border: Border.all(color: p.line),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: <Widget>[
                  Icon(Icons.search, size: 14, color: p.ink3),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                      style: TextStyle(fontSize: 12.5, color: p.ink),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: context.tr('搜索好友短号'),
                        hintStyle: TextStyle(fontSize: 12.5, color: p.ink3),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _noFriend
                  ? Center(
                      child: Text(
                        context.tr('无此好友'),
                        style: TextStyle(fontSize: 12.5, color: p.ink3),
                      ),
                    )
                  : shown.isEmpty
                      ? Center(
                          child: Text(
                            context.tr('还没有好友'),
                            style: TextStyle(fontSize: 12.5, color: p.ink3),
                          ),
                        )
                      : ListView.builder(
                          itemCount: shown.length,
                          itemBuilder: (BuildContext context, int i) {
                            final Friendship f = shown[i];
                            final bool selected = _selected.contains(f.peerAccountId);
                            return InkWell(
                              onTap: () => _toggle(f),
                              child: Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Row(
                                  children: <Widget>[
                                    MoonAvatar(
                                      name: f.displayName,
                                      seed: f.peerAccountId,
                                      avatar: widget.state.avatarOf(f.peerAccountId),
                                      size: 30,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Text(f.displayName,
                                              style: TextStyle(fontSize: 13, color: p.ink)),
                                          Text('#${shortAccountId(f.peerAccountId)}',
                                              style: TextStyle(fontSize: 11, color: p.ink3)),
                                        ],
                                      ),
                                    ),
                                    if (selected) Icon(Icons.check, size: 18, color: p.accent),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        MoonButton(
          label: context.tr('取消'),
          kind: MoonButtonKind.text,
          small: true,
          onPressed: () => Navigator.of(context).pop(),
        ),
        MoonButton(
          label: widget.multi
              ? '${context.tr('邀请')} (${_selected.length})'
              : context.tr('确认'),
          small: true,
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_selected.toList(growable: false)),
        ),
      ],
    );
  }
}
