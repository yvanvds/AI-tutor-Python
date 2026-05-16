import 'package:ai_tutor_python/l10n/generated/app_localizations.dart';
import 'package:ai_tutor_python/services/config/local_api_key_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shown when user is logged in but does not have access to the global key
/// AND has not yet provided a local key.
class LocalKeyGateScreen extends ConsumerStatefulWidget {
  const LocalKeyGateScreen({super.key});

  @override
  ConsumerState<LocalKeyGateScreen> createState() => _LocalKeyGateScreenState();
}

class _LocalKeyGateScreenState extends ConsumerState<LocalKeyGateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.auth_localKey_validation_empty)),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(localApiKeyStorageProvider.notifier).saveKey(text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.auth_localKey_saved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l.auth_localKey_saveFailed(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.auth_localKey_appBarTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  Text(
                    l.auth_localKey_explainer,
                    style: const TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _controller,
                    obscureText: _obscure,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l.auth_localKey_field_label,
                      hintText: 'sk-...',
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: _obscure
                                ? l.auth_localKey_tooltip_showKey
                                : l.auth_localKey_tooltip_hideKey,
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          IconButton(
                            tooltip: l.auth_localKey_tooltip_paste,
                            icon: const Icon(Icons.paste),
                            onPressed: () async {
                              final data = await Clipboard.getData(
                                'text/plain',
                              );
                              final pasted = data?.text ?? '';
                              if (pasted.isNotEmpty) {
                                _controller.text = pasted.trim();
                              }
                            },
                          ),
                        ],
                      ),
                      helperText: l.auth_localKey_field_helper,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(l.auth_localKey_button_save),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.auth_localKey_footnote,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
