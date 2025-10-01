import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/peer_profile.dart';

class PeerTile extends StatelessWidget {
  final PeerProfile peer;
  final VoidCallback onKeep;
  final VoidCallback onTap;

  const PeerTile({
    super.key,
    required this.peer,
    required this.onKeep,
    required this.onTap,
  });

  ImageProvider? _avatarProvider(PeerProfile p) {
    // ✅ Canonical field in your updated model/service code is `profileImageB64`
    final b64 = p.profileImageB64;
    if (b64 == null || b64.trim().isEmpty) return null;

    try {
      return MemoryImage(base64Decode(b64.trim()));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = <String>[];
    if (peer.phone != null && peer.phone!.trim().isNotEmpty) meta.add('📞');
    if (peer.handle != null && peer.handle!.trim().isNotEmpty) meta.add('🔗');
    final hint = meta.isEmpty ? 'Tap to chat' : 'Tap to chat • has contact info';

    final avatar = _avatarProvider(peer);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: Colors.black.withOpacity(0.06),
        backgroundImage: avatar,
        child: avatar == null
            ? Text(
          peer.displayName.isEmpty ? '?' : peer.displayName.characters.first.toUpperCase(),
          style: TextStyle(
            color: Colors.black.withOpacity(0.75),
            fontWeight: FontWeight.w900,
          ),
        )
            : null,
      ),
      title: Text(
        peer.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        hint,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: TextButton.icon(
        onPressed: onKeep,
        icon: const Icon(Icons.bookmark_add),
        label: const Text('Keep'),
      ),
    );
  }
}