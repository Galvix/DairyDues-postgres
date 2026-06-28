// lib/widgets/sync_status_banner.dart
//
// A thin bar shown across screens reflecting the offline-first sync state:
// offline, queued (pending) changes, syncing, or errors. Tap to "Sync now".
// Hides itself when everything is synced and online, to stay out of the way.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/sync_service.dart';
import '../theme/app_theme.dart';

class SyncStatusBanner extends StatelessWidget {
  const SyncStatusBanner({super.key});

  String _ago(DateTime? t) {
    if (t == null) return 'never';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final pending = sync.pendingCount;
    final offline = !sync.online;
    final syncing = sync.syncing;
    final hasError = sync.lastError != null;

    // Nothing to show: online, nothing queued, idle, no error.
    if (!offline && pending == 0 && !syncing && !hasError) {
      return const SizedBox.shrink();
    }

    late final Color color;
    late final IconData icon;
    late final String text;

    if (syncing) {
      color = AppTheme.primary;
      icon = Icons.sync;
      text = 'Syncing…';
    } else if (offline) {
      color = AppTheme.warning;
      icon = Icons.cloud_off;
      final err = sync.lastError;
      text = err != null
          ? 'Offline — $err'
          : pending > 0
              ? 'Offline — $pending change${pending == 1 ? '' : 's'} queued'
              : 'Offline — showing saved data';
    } else if (pending > 0) {
      color = AppTheme.warning;
      icon = Icons.cloud_upload_outlined;
      text = '$pending change${pending == 1 ? '' : 's'} to sync';
    } else {
      color = AppTheme.error;
      icon = Icons.error_outline;
      text = 'Sync issue — tap to retry';
    }

    return Material(
      color: color.withOpacity(0.10),
      child: InkWell(
        onTap: syncing ? null : () => sync.sync(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Row(children: [
            if (syncing)
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            if (!syncing) ...[
              Text('Synced ${_ago(sync.lastSyncAt)}',
                  style: TextStyle(color: color.withOpacity(0.8), fontSize: 11)),
              const SizedBox(width: 6),
              Text('Sync now',
                  style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      decoration: TextDecoration.underline)),
            ],
          ]),
        ),
      ),
    );
  }
}
