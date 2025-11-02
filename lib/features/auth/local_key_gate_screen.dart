import 'package:ai_tutor_python/data/config/global_config_providers.dart';
import 'package:ai_tutor_python/data/config/local_api_key_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter an API key.')));
      return;
    }
    setState(() => _saving = true);
    try {
      await LocalApiKeyStorage.saveKey(text);
      if (mounted) ref.invalidate(localApiKeyExistsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API key saved locally.')));
      // Optional: pop or notify parent via Navigator/Callback if needed.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save key: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Provide Your API Key')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: ListView(
                children: [
                  const Text(
                    'Your account is not yet approved to use the global key.\n\n'
                    'You can either wait until your account is approved, or provide your own OpenAI API key to continue immediately. '
                    'Your key will be stored locally on this device and only used by this app.',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    controller: _controller,
                    obscureText: _obscure,
                    enableSuggestions: false,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: 'sk-...',
                      border: const OutlineInputBorder(),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: _obscure ? 'Show key' : 'Hide key',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                          IconButton(
                            tooltip: 'Paste',
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
                      helperText:
                          'We’ll store this key locally for this user on this device.',
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
                      label: const Text('Save key'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Note: You can change or remove this key later in Settings.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
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
