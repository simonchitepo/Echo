import 'package:flutter/material.dart';

class GuidePage extends StatelessWidget {
  const GuidePage({super.key});

  static const Color _brandGreen = Color(0xFF0F9D58);
  static const Color _softField = Color(0xFFF7F8F7);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guide'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _heroCard(),
          const SizedBox(height: 14),
          _section(
            title: 'Quick start',
            items: const [
              _StepItem(
                title: '1) Set your name',
                body: 'Open Here & Now and set a display name so others can recognize you.',
                icon: Icons.person_outline,
              ),
              _StepItem(
                title: '2) Go live (host)',
                body: 'On Android: tap Go live to create a bubble. Keep GPS on and stay within the radius.',
                icon: Icons.play_arrow,
              ),
              _StepItem(
                title: '3) Join a bubble',
                body: 'On any device on the same Wi-Fi: open Bubbles nearby and tap Join.',
                icon: Icons.group_add_outlined,
              ),
              _StepItem(
                title: '4) Chat & Keep',
                body: 'Tap a person to chat. Tap Keep to save their contact card.',
                icon: Icons.chat_bubble_outline,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _section(
            title: 'Important note about PC hosting',
            highlight: true,
            items: const [
              _StepItem(
                title: 'Hosting from PC is limited right now',
                body:
                'At the moment, bubbles should be hosted from an Android device.\n\n'
                    'Windows/PC builds can join bubbles, but hosting from PC may not be discoverable on all networks due to OS/network restrictions (firewall / broadcast).',
                icon: Icons.info_outline,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _section(
            title: 'Troubleshooting',
            items: const [
              _StepItem(
                title: 'Not seeing bubbles nearby?',
                body:
                'Make sure all devices are on the same Wi-Fi network (not guest/isolated). '
                    'On Android, ensure Wi-Fi is ON and Location is ON.',
                icon: Icons.wifi_tethering_outlined,
              ),
              _StepItem(
                title: 'Can’t connect after joining?',
                body:
                'The host device must stay online. If the host is a PC, firewall rules may block TCP/UDP. '
                    'For now, host from Android for the most reliable experience.',
                icon: Icons.shield_outlined,
              ),
            ],
          ),
          const SizedBox(height: 18),
          _privacyCard(),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Echo is local and temporary — your bubble disappears when you leave.',
              style: TextStyle(color: Colors.black.withOpacity(0.55), fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _softField,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _brandGreen.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.wifi_tethering, color: _brandGreen),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('How to use Echo', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                SizedBox(height: 4),
                Text(
                  'Create or join local “bubbles” on your Wi-Fi network and chat with people nearby.',
                  style: TextStyle(height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section({
    required String title,
    required List<_StepItem> items,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? _brandGreen.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          ...items.map((s) => _stepTile(s)).toList(),
        ],
      ),
    );
  }

  Widget _stepTile(_StepItem s) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(s.icon, color: Colors.black.withOpacity(0.70)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(
                  s.body,
                  style: TextStyle(color: Colors.black.withOpacity(0.70), height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _privacyCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Privacy', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            '• Your bubble is local and temporary.\n'
                '• People can only see you while you’re in the bubble.\n'
                '• When you leave, connections vanish.\n'
                '• Use Keep to save someone’s contact card.',
            style: TextStyle(color: Colors.black.withOpacity(0.70), height: 1.3, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _StepItem {
  final String title;
  final String body;
  final IconData icon;

  const _StepItem({
    required this.title,
    required this.body,
    required this.icon,
  });
}