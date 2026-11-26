import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/session/app_role.dart';
import '../../../core/theme/app_colors.dart';
import 'profile_cubit.dart';

/// The Thick Services "More" menu for staff and supervisors, served by the
/// company's web app.
abstract final class MoreMenu {
  static const _host = 'thickservices.com';
  static const _path = '/TSLfacilitymanager/mwrap/index';

  /// Identifies the app to the menu; the same for everyone.
  static const _sid = 'f470ea1807a7c7e8e82b7e289fdc0d5383d68e74';

  /// The menu link for the signed-in staff member or supervisor.
  static Uri linkFor(String staffEmail) =>
      Uri.https(_host, _path, {'sid': _sid, 'staffEmail': staffEmail});
}

/// The More menu, opened inside the app like an in-app browser.
class MorePage extends StatefulWidget {
  const MorePage({required this.role, super.key});

  final AppRole role;

  @override
  State<MorePage> createState() => _MorePageState();
}

class _MorePageState extends State<MorePage> {
  late final WebViewController _web;
  var _progress = 0;
  var _failed = false;

  @override
  void initState() {
    super.initState();
    final email = context.read<ProfileCubit>().of(widget.role).email;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColors.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (mounted) setState(() => _progress = value);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _failed = false);
          },
          onWebResourceError: (error) {
            // Only the page itself failing matters, not a missing image.
            if ((error.isForMainFrame ?? true) && mounted) {
              setState(() => _failed = true);
            }
          },
        ),
      )
      ..loadRequest(MoreMenu.linkFor(email));
  }

  /// Back goes back inside the menu first, then closes it.
  Future<void> _back() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    } else if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('More'),
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              tooltip: 'Reload',
              onPressed: () => _web.reload(),
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => context.pop(),
              icon: const Icon(Icons.close),
            ),
          ],
          bottom: _progress < 100
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress == 0 ? null : _progress / 100,
                    minHeight: 2,
                  ),
                )
              : null,
        ),
        body: _failed
            ? _Offline(onRetry: () => _web.reload())
            : WebViewWidget(controller: _web),
      ),
    );
  }
}

class _Offline extends StatelessWidget {
  const _Offline({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 40, color: AppColors.muted),
            const SizedBox(height: 12),
            Text('This page couldn’t load', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Check your connection and try again.',
              style: text.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
