import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/kept_contact.dart';

class KeptPage extends StatelessWidget {
  final List<KeptContact> contacts;
  final void Function(KeptContact) onRemove;

  const KeptPage({
    super.key,
    required this.contacts,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) {
      return const _EmptyKeptState();
    }

    final fmt = DateFormat.yMMMd().add_jm();

    return ListView.separated(
      itemCount: contacts.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final c = contacts[i];
        final secondary = <String>[];
        if (c.phone != null && c.phone!.trim().isNotEmpty) {
          secondary.add('📞 ${c.phone!.trim()}');
        }
        if (c.handle != null && c.handle!.trim().isNotEmpty) {
          secondary.add('🔗 ${c.handle!.trim()}');
        }

        final sub = StringBuffer();
        sub.write('Kept: ${fmt.format(c.keptAt.toLocal())}');
        if (secondary.isNotEmpty) {
          sub.write('\n${secondary.join(' • ')}');
        }

        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.bookmark)),
          title: Text(c.displayName),
          subtitle: Text(sub.toString()),
          isThreeLine: secondary.isNotEmpty,
          trailing: PopupMenuButton<String>(
            tooltip: 'Actions',
            onSelected: (v) async {
              if (v == 'copy_phone' && c.phone != null) {
                await Clipboard.setData(ClipboardData(text: c.phone!.trim()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Phone copied')),
                  );
                }
              }
              if (v == 'copy_handle' && c.handle != null) {
                await Clipboard.setData(ClipboardData(text: c.handle!.trim()));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Handle copied')),
                  );
                }
              }
              if (v == 'remove') {
                onRemove(c);
              }
            },
            itemBuilder: (_) => [
              if (c.phone != null && c.phone!.trim().isNotEmpty)
                const PopupMenuItem(value: 'copy_phone', child: Text('Copy phone')),
              if (c.handle != null && c.handle!.trim().isNotEmpty)
                const PopupMenuItem(value: 'copy_handle', child: Text('Copy handle')),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'remove', child: Text('Remove')),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyKeptState extends StatelessWidget {
  const _EmptyKeptState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 72,
              width: 72,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.04),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(Icons.bookmark_outline, size: 34),
            ),
            const SizedBox(height: 16),
            const Text(
              'Your kept people',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'People you choose to keep will appear here.\nThey stay even after the bubble ends.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black.withOpacity(0.65), height: 1.35),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                'Tip: Tap Keep while you\'re both in the same bubble.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
