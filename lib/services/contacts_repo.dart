import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/kept_contact.dart';

class ContactsRepo {
  static const _kKey = 'kept_contacts_v1';

  Future<List<KeptContact>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kKey);
    if (raw == null || raw.isEmpty) return const [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => KeptContact.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(List<KeptContact> contacts) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await prefs.setString(_kKey, raw);
  }
}
