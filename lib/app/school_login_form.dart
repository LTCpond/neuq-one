import 'package:material_ui/material_ui.dart';

import '../core/auth/neuq_login_protocol.dart';
import '../core/auth/school_auth.dart';
import '../core/network/official_browser.dart';

class SchoolLoginForm extends StatefulWidget {
  const SchoolLoginForm({
    super.key,
    required this.canRememberPassword,
    required this.onSubmit,
    this.canSubmit = true,
    this.initialFailure,
  });

  final bool canRememberPassword;
  final bool canSubmit;
  final SchoolRequestFailure? initialFailure;
  final Future<void> Function(
    NeuqCredentials credentials,
    bool rememberPassword,
  )
  onSubmit;

  @override
  State<SchoolLoginForm> createState() => _SchoolLoginFormState();
}

class _SchoolLoginFormState extends State<SchoolLoginForm> {
  final _form = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  SchoolRequestFailure? _failure;
  bool _rememberPassword = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _failure = widget.initialFailure;
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || !widget.canSubmit || !_form.currentState!.validate()) {
      return;
    }
    final credentials = NeuqCredentials(_username.text.trim(), _password.text);
    final rememberPassword = widget.canRememberPassword && _rememberPassword;
    FocusScope.of(context).unfocus();
    _password.clear();
    setState(() {
      _submitting = true;
      _failure = null;
    });
    try {
      await widget.onSubmit(credentials, rememberPassword);
    } on SchoolRequestFailure catch (error) {
      if (mounted) setState(() => _failure = error);
    } catch (_) {
      if (mounted) setState(() => _failure = SchoolRequestFailure.unavailable);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _username,
            readOnly: _submitting,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: '学号'),
            validator: (value) =>
                schoolSubjectForStudentCode(value?.trim() ?? '') == null
                ? '请输入有效学号'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _password,
            readOnly: _submitting,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: '统一身份认证密码'),
            validator: (value) =>
                value == null || value.isEmpty ? '请输入密码' : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (widget.canRememberPassword)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _rememberPassword,
              onChanged: _submitting
                  ? null
                  : (value) =>
                        setState(() => _rememberPassword = value ?? false),
              title: const Text('在此设备记住密码'),
              subtitle: const Text('加密保存在本机，用于教务续登及学校远程访问服务按需认证。'),
            ),
          const SizedBox(height: 16),
          if (_submitting) const LinearProgressIndicator(),
          if (!_submitting)
            FilledButton(
              onPressed: widget.canSubmit ? _submit : null,
              child: const Text('统一身份认证登录'),
            ),
          if (_failure case final failure?) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                failure.message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            if (failure.requiresOfficialLogin)
              TextButton.icon(
                onPressed: () =>
                    openOfficialPage(context, schoolWebEntry.toString()),
                icon: const Icon(Icons.open_in_new),
                label: const Text('在系统浏览器打开教务'),
              ),
          ],
        ],
      ),
    ),
  );
}
