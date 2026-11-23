import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/context_menu_helper.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_app/widget/responsive_list_view.dart';
import 'package:refena_flutter/refena_flutter.dart';

/// 右键菜单的独立设置页：是否集成菜单、是否启用设备子菜单。
class ContextMenuPage extends StatefulWidget {
  const ContextMenuPage({super.key});

  @override
  State<ContextMenuPage> createState() => _ContextMenuPageState();
}

class _ContextMenuPageState extends State<ContextMenuPage> with Refena {
  /// null = 尚未读取注册表。
  bool? _showInContextMenu;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ensureRef((ref) async {
      final enabled = await isContextMenuEnabled();
      if (mounted) {
        setState(() => _showInContextMenu = enabled);
      }
    });
  }

  Future<void> _refreshDevices({required bool quickSend}) async {
    await updateContextMenuDevices(
      quickSend: quickSend,
      devices: ref.read(nearbyDevicesProvider).allDevices.values,
      favoriteFingerprints: ref.read(favoritesProvider).map((favorite) => favorite.fingerprint).toSet(),
    );
  }

  Future<void> _setShowInContextMenu(bool value) async {
    final quickSend = ref.read(settingsProvider).contextMenuQuickSend;
    final showIcon = ref.read(settingsProvider).contextMenuIcon;
    setState(() => _busy = true);
    final success = value ? await enableContextMenu(quickSend: quickSend, showIcon: showIcon) : await disableContextMenu();
    if (!mounted) {
      return;
    }
    if (!success) {
      setState(() => _busy = false);
      context.showSnackBar(t.general.error);
      return;
    }

    setState(() {
      _showInContextMenu = value;
      _busy = false;
    });
    await _refreshDevices(quickSend: quickSend);
  }

  Future<void> _setQuickSend(bool value) async {
    final showIcon = ref.read(settingsProvider).contextMenuIcon;
    setState(() => _busy = true);
    final success = await enableContextMenu(quickSend: value, showIcon: showIcon);
    if (!mounted) {
      return;
    }
    if (!success) {
      setState(() => _busy = false);
      context.showSnackBar(t.general.error);
      return;
    }

    await ref.notifier(settingsProvider).setContextMenuQuickSend(value);
    await _refreshDevices(quickSend: value);
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  Future<void> _setContextMenuIcon(bool value) async {
    final enabled = _showInContextMenu ?? false;
    if (!enabled) {
      await ref.notifier(settingsProvider).setContextMenuIcon(value);
      return;
    }
    final quickSend = ref.read(settingsProvider).contextMenuQuickSend;
    setState(() => _busy = true);
    final success = await enableContextMenu(quickSend: quickSend, showIcon: value);
    if (!mounted) {
      return;
    }
    if (!success) {
      setState(() => _busy = false);
      context.showSnackBar(t.general.error);
      return;
    }
    await ref.notifier(settingsProvider).setContextMenuIcon(value);
    if (mounted) {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Translations.of(context);
    final quickSend = context.watch(settingsProvider.select((settings) => settings.contextMenuQuickSend));
    final showIcon = context.watch(settingsProvider.select((settings) => settings.contextMenuIcon));
    final enabled = _showInContextMenu;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.contextMenuPage.title),
      ),
      body: enabled == null
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveListView(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 20),
              children: [
                SwitchListTile.adaptive(
                  title: Text(t.settingsTab.general.showInContextMenu),
                  subtitle: Text(t.contextMenuPage.enableDescription),
                  value: enabled,
                  onChanged: _busy ? null : _setShowInContextMenu,
                ),
                SwitchListTile.adaptive(
                  title: Text(t.contextMenuPage.quickSend),
                  subtitle: Text(t.contextMenuPage.quickSendDescription),
                  value: enabled && quickSend,
                  onChanged: !enabled || _busy ? null : _setQuickSend,
                ),
                SwitchListTile.adaptive(
                  title: Text(t.contextMenuPage.showIcon),
                  subtitle: Text(t.contextMenuPage.showIconDescription),
                  value: showIcon,
                  onChanged: _busy ? null : _setContextMenuIcon,
                ),
              ],
            ),
    );
  }
}
