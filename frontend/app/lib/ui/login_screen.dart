import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../state/app_state.dart';
import '../theme.dart';
import 'login_quotes.dart';
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
      setState(() => _formError = '操作失败，请重试');
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
      padding: const EdgeInsets.fromLTRB(44, 44, 44, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            'MoonChat',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.6,
              color: p.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '“${_quote.text}”',
            style: TextStyle(fontSize: 13, height: 1.7, color: p.ink2),
          ),
          const SizedBox(height: 6),
          Text(
            '— ${_quote.author}',
            style: TextStyle(fontSize: 11, letterSpacing: 0.4, color: p.ink3),
          ),
          const SizedBox(height: 28),
          if (_registerMode) ...<Widget>[
            MoonField(label: '名字', controller: _name, errorText: _nameError, hint: '1–20 字'),
            const SizedBox(height: 16),
          ],
          MoonField(
            label: '邮箱',
            controller: _email,
            errorText: _emailError,
            hint: 'you@example.com',
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),
          MoonField(
            label: '密码',
            controller: _password,
            obscure: true,
            errorText: _passwordError,
            hint: '8–72 位，不能是纯数字',
            onSubmitted: (_) => _submit(),
          ),
          if (_formError != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(_formError!, style: TextStyle(fontSize: 12, color: p.accent)),
          ],
          const SizedBox(height: 24),
          Row(
            children: <Widget>[
              MoonButton(
                label: _registerMode ? '注册并登录' : '登录',
                onPressed: _submit,
                busy: _submitting,
              ),
              const SizedBox(width: 12),
              MoonButton(
                label: _registerMode ? '已有账号' : '注册',
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
    final MoonPalette p = context.moon;
    return Container(
      color: p.stage,
      child: AnimatedBuilder(
        animation: _arrival,
        builder: (BuildContext context, Widget? _) {
          final double t = _arrival.value;
          // 关门先于离地：0–22% 换关；22–34% 点火；之后一直抬升。
          final double door = (t / 0.22).clamp(0.0, 1.0);
          final double ignite = ((t - 0.22) / 0.12).clamp(0.0, 1.0);
          final double lift = Curves.easeOutCubic.transform(((t - 0.22) / 0.78).clamp(0.0, 1.0));
          return Stack(
            children: <Widget>[
              // 地平线与月盘：只用描边与明度，不加渐变。
              Positioned(
                left: 0,
                right: 0,
                bottom: 96,
                child: Container(height: 1, color: p.ink3.withValues(alpha: 0.85)),
              ),
              Positioned(
                right: 56,
                top: 64,
                child: Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: p.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: p.lineStrong),
                  ),
                ),
              ),
              Center(
                child: Transform.translate(
                  offset: Offset(0, -56 * lift),
                  child: Transform.scale(
                    scale: 1 - 0.06 * lift,
                    child: Opacity(
                      opacity: 1 - 0.85 * lift,
                      child: SizedBox(
                        width: 240,
                        child: AspectRatio(
                          aspectRatio: 420 / 649,
                          child: Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              Opacity(
                                opacity: 1 - door,
                                child: Image.asset('assets/rocket-open.png', fit: BoxFit.contain),
                              ),
                              Opacity(
                                opacity: door * (1 - ignite),
                                child: Image.asset('assets/rocket-closed.png', fit: BoxFit.contain),
                              ),
                              Opacity(
                                opacity: ignite,
                                child: Image.asset('assets/rocket-launch.png', fit: BoxFit.contain),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 24,
                bottom: 20,
                child: Text(
                  '发射基地',
                  style: TextStyle(fontSize: 11, letterSpacing: 2, color: p.ink3, fontFamilyFallback: kMonoFallback),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
