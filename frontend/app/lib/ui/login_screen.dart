import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../i18n/context_tr.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'login_quotes.dart';
import 'login_stage.dart';
import 'widgets.dart';

/// S1 登录 / 注册 + S2 登舱过渡（`SCREEN-MAP.md` §4）。
/// 表单在左，右侧是月面舞台；登录成功后播一次短促离场，再交给外壳换屏。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state, this.onArrived});

  final AppState state;

  /// 登舱过渡播完（或减少动态时直接跳过）后回调；外壳据此切到主界面。
  final VoidCallback? onArrived;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _name = TextEditingController();

  /// 800ms 的登舱过渡，只分三个节拍：关门（0–22%）、点火（22–34%）、离地（22–100%）。
  /// 不做旋转、不出画、不闪白；登录是高频动作，整段控制在 1 秒内。
  late final AnimationController _arrival = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  /// 过渡已经开始：表单淡出并停用，避免用户在这 800ms 里继续操作。
  bool _arriving = false;

  /// 每次进入登录页取一句：State 只在进出登录页时重建，切主题或切注册模式都不会换。
  late final LoginQuote _quote = nextLoginQuote();

  bool _registerMode = false;
  bool _submitting = false;
  String? _emailError;
  String? _passwordError;
  String? _nameError;
  String? _formError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    _arrival.dispose();
    super.dispose();
  }

  bool _validate() {
    final String email = _email.text.trim();
    final String password = _password.text;
    final String name = _name.text.trim();
    setState(() {
      _emailError = (email.isEmpty || !email.contains('@') || email.indexOf('@') == 0)
          ? '需要一个带 @ 的邮箱'
          : null;
      _passwordError = (password.length < 8 || password.length > 72)
          ? '密码 8–72 位'
          : int.tryParse(password) != null
              ? '密码不能是纯数字'
              : null;
      _nameError = !_registerMode
          ? null
          : (name.isEmpty || name.length > 20)
              ? '名字 1–20 字'
              : null;
      _formError = null;
    });
    return _emailError == null && _passwordError == null && _nameError == null;
  }

  Future<void> _submit() async {
    if (_submitting || !_validate()) {
      return;
    }
    setState(() {
      _submitting = true;
      _formError = null;
    });
    bool registered = false;
    try {
      if (_registerMode) {
        await widget.state.register(
          email: _email.text.trim(),
          password: _password.text,
          displayName: _name.text.trim(),
        );
        registered = true;
      }
      await widget.state.login(email: _email.text.trim(), password: _password.text);
      await _playArrival();
    } on ApiException catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        if (registered) {
          // 账号已经建好了，失败的是随后的登录：切回登录模式，别让重试撞 `conflict`。
          _registerMode = false;
          _formError = '注册成功，请再登录一次';
        } else if (e.isUnauthenticated) {
          _formError = '邮箱或密码不对';
        } else if (e.code == 'conflict') {
          _formError = '这个邮箱已经注册过了';
        } else {
          _formError = e.displayText;
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _formError = '操作失败，请重试');
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  /// 登录成功后的登舱过渡；减少动态时直接交棒，不强制看完。
  Future<void> _playArrival() async {
    if (!mounted) {
      return;
    }
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      widget.onArrived?.call();
      return;
    }
    setState(() => _arriving = true);
    await _arrival.forward();
    if (mounted) {
      widget.onArrived?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final MoonPalette p = context.moon;
    return Scaffold(
      backgroundColor: p.bg,
      body: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final bool narrow = c.maxWidth < 900;
          // 表单先淡出，舞台的关门/离地才开始；过渡期间点击不再落到表单上。
          final Widget formBody = _buildForm(context);
          final Widget form = IgnorePointer(
            ignoring: _arriving,
            child: AnimatedOpacity(
              opacity: _arriving ? 0 : 1,
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutCubic,
              // 宽屏表单区被 540 高度钉死；注册模式叠上字段错误会超出，给一个只在该分支生效的滚动。
              child: narrow ? formBody : SingleChildScrollView(child: formBody),
            ),
          );
          final Widget stage = _buildStage(context);
          return Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1092),
                child: Padding(
                  padding: EdgeInsets.all(narrow ? 20 : 56),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: p.surface,
                      border: Border.all(color: p.line),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: narrow
                          ? Column(
                              children: <Widget>[form, SizedBox(height: 300, child: stage)],
                            )
                          : SizedBox(
                              height: 540,
                              child: Row(
                                children: <Widget>[
                                  Expanded(flex: 44, child: form),
                                  Expanded(flex: 56, child: stage),
                                ],
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final MoonPalette p = context.moon;
    return Container(
      color: p.surface,
      padding: const EdgeInsets.fromLTRB(44, 40, 44, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // 站点标记 + 品牌：一行小字压住版面，把标题让给下面的大字号。
          Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset(
                  'assets/moonchat-logo.png',
                  width: 20,
                  height: 20,
                  filterQuality: FilterQuality.high,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'MOONCHAT',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 3.2,
                  color: p.ink3,
                  fontFamilyFallback: kMonoFallback,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'MoonChat',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.8,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 10),
          // 固定最小高度：引言长短不一，不能让下面的字段每次进入都跟着跳。
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: Container(
              padding: const EdgeInsets.only(left: 12),
              decoration: BoxDecoration(
                border: Border(
                  left: BorderSide(color: p.accent.withValues(alpha: 0.55), width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '“${context.tr(_quote.text)}”',
                    style: TextStyle(fontSize: 13, height: 1.7, color: p.ink2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '— ${context.tr(_quote.author)}',
                    style: TextStyle(fontSize: 11, letterSpacing: 0.4, color: p.ink3),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (_registerMode) ...<Widget>[
            MoonField(label: context.tr('名字'), controller: _name, errorText: _nameError == null ? null : context.tr(_nameError!), hint: context.tr('1–20 字')),
            const SizedBox(height: 18),
          ],
          MoonField(
            label: context.tr('邮箱'),
            controller: _email,
            errorText: _emailError == null ? null : context.tr(_emailError!),
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 18),
          MoonField(
            label: context.tr('密码'),
            controller: _password,
            obscure: true,
            errorText: _passwordError == null ? null : context.tr(_passwordError!),
            hint: context.tr('8–72 位，不能是纯数字'),
            onSubmitted: (_) => _submit(),
          ),
          if (_formError != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(context.tr(_formError!), style: TextStyle(fontSize: 12, color: p.accent)),
          ],
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              Expanded(
                child: MoonButton(
                  label: _registerMode ? context.tr('注册并登录') : context.tr('登录'),
                  onPressed: _submit,
                  busy: _submitting,
                ),
              ),
              const SizedBox(width: 12),
              MoonButton(
                label: _registerMode ? context.tr('已有账号') : context.tr('注册'),
                kind: MoonButtonKind.text,
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                          _registerMode = !_registerMode;
                          _formError = null;
                          _nameError = null;
                        }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    return LoginStage(arrival: _arrival, label: context.tr('发射基地'));
  }
}
