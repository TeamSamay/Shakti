import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/guardian_overlay_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _safeWordController = TextEditingController(text: 'I am safe');
  final _sosCommandController = TextEditingController(text: 'red alert');
  final _fakeCallCommandController = TextEditingController(text: 'call me now');
  final List<EmergencyContact> _contacts = [];

  bool _saving = false;
  bool _autoShareLocation = true;
  bool _autoStartEvidence = true;
  bool _enableOverlayBubble = false;
  static const _overlayPreferenceKey = 'enable_overlay_bubble_v2';

  static const _relations = [
    'Mom',
    'Dad',
    'Brother',
    'Sister',
    'Friend',
    'Guardian',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _safeWordController.dispose();
    _sosCommandController.dispose();
    _fakeCallCommandController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final contactsJson = prefs.getString('emergency_contacts');
    final loadedContacts = <EmergencyContact>[];

    if (contactsJson != null && contactsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(contactsJson) as List<dynamic>;
        loadedContacts.addAll(
          decoded
              .map((item) => EmergencyContact.fromJson(item))
              .where((contact) => contact.name.trim().isNotEmpty),
        );
      } catch (_) {}
    }

    final oldName = prefs.getString('emergency_name') ?? '';
    if (loadedContacts.isEmpty && oldName.trim().isNotEmpty) {
      loadedContacts.add(
        EmergencyContact(
          name: oldName,
          relation: prefs.getString('emergency_relation') ?? 'Mom',
          phone: prefs.getString('emergency_phone') ?? '',
          whatsapp: prefs.getString('emergency_whatsapp') ?? '',
          isPrimary: true,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _contacts
        ..clear()
        ..addAll(loadedContacts);
      if (_contacts.isNotEmpty && !_contacts.any((c) => c.isPrimary)) {
        _contacts[0] = _contacts[0].copyWith(isPrimary: true);
      }
      _safeWordController.text =
          prefs.getString('safe_word') ?? _safeWordController.text;
      _sosCommandController.text =
          prefs.getString('sos_command_word') ?? _sosCommandController.text;
      _fakeCallCommandController.text = prefs.getString('fake_call_command') ??
          _fakeCallCommandController.text;
      _autoShareLocation = prefs.getBool('auto_share_location') ?? true;
      _autoStartEvidence = prefs.getBool('auto_start_evidence') ?? true;
      _enableOverlayBubble = prefs.getBool(_overlayPreferenceKey) ?? false;
    });
  }

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    if (_contacts.isNotEmpty && !_contacts.any((c) => c.isPrimary)) {
      _contacts[0] = _contacts[0].copyWith(isPrimary: true);
    }
    final primary = _contacts.where((c) => c.isPrimary).firstOrNull;

    await prefs.setString(
      'emergency_contacts',
      jsonEncode(_contacts.map((c) => c.toJson()).toList()),
    );
    await prefs.setString('safe_word', _safeWordController.text.trim());
    await prefs.setString('sos_command_word', _sosCommandController.text.trim());
    await prefs.setString(
      'fake_call_command',
      _fakeCallCommandController.text.trim(),
    );
    await prefs.setBool('auto_share_location', _autoShareLocation);
    await prefs.setBool('auto_start_evidence', _autoStartEvidence);
    await prefs.setBool(_overlayPreferenceKey, _enableOverlayBubble);

    // Backward-compatible primary contact keys used by SOS/check-in screens.
    await prefs.setString('emergency_name', primary?.name ?? '');
    await prefs.setString('emergency_phone', primary?.phone ?? '');
    await prefs.setString('emergency_whatsapp', primary?.whatsapp ?? '');
    await prefs.setString('emergency_relation', primary?.relation ?? 'Mom');
    await GuardianOverlayService.ensureStarted();

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Safety profile saved')),
    );
  }

  void _setPrimary(int index) {
    setState(() {
      for (var i = 0; i < _contacts.length; i++) {
        _contacts[i] = _contacts[i].copyWith(isPrimary: i == index);
      }
    });
  }

  void _deleteContact(int index) {
    setState(() {
      final wasPrimary = _contacts[index].isPrimary;
      _contacts.removeAt(index);
      if (wasPrimary && _contacts.isNotEmpty) {
        _contacts[0] = _contacts[0].copyWith(isPrimary: true);
      }
    });
  }

  Future<void> _openContactSheet({EmergencyContact? contact, int? index}) async {
    final result = await showModalBottomSheet<EmergencyContact>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ContactSheet(
        relations: _relations,
        initial: contact,
        makePrimary: _contacts.isEmpty || contact?.isPrimary == true,
      ),
    );
    if (result == null) return;
    setState(() {
      if (result.isPrimary) {
        for (var i = 0; i < _contacts.length; i++) {
          _contacts[i] = _contacts[i].copyWith(isPrimary: false);
        }
      }
      if (index == null) {
        _contacts.add(result);
      } else {
        _contacts[index] = result;
      }
      if (!_contacts.any((c) => c.isPrimary)) {
        _contacts[0] = _contacts[0].copyWith(isPrimary: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        title: const Text('Safety Profile'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveProfile,
            child: Text(_saving ? 'Saving...' : 'Save'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 18),
              _buildContactsCard(),
              const SizedBox(height: 16),
              _buildSafetyWordsCard(),
              const SizedBox(height: 16),
              _buildPreferencesCard(),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _saving ? null : _saveProfile,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Saving...' : 'Save Safety Profile'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(56),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final primary = _contacts.where((c) => c.isPrimary).firstOrNull;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2563EB), Color(0xFF10B981)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 28,
            backgroundColor: Colors.white,
            child: Icon(Icons.shield_rounded, color: Color(0xFF2563EB)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Guardian settings',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  primary == null
                      ? 'Add contacts, safe words, and SOS preferences.'
                      : '${_contacts.length} contacts • Primary: ${primary.name}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsCard() {
    return _buildCard(
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Emergency Contacts',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            IconButton.filled(
              onPressed: () => _openContactSheet(),
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Add multiple numbers. Primary contact appears first in SOS and fake call.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 14),
        if (_contacts.isEmpty)
          _emptyContactState()
        else
          ..._contacts.asMap().entries.map(
                (entry) => _contactTile(entry.value, entry.key),
              ),
      ],
    );
  }

  Widget _emptyContactState() {
    return InkWell(
      onTap: () => _openContactSheet(),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: const Row(
          children: [
            Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF2563EB)),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Add your first emergency contact',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _contactTile(EmergencyContact contact, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: contact.isPrimary ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: contact.isPrimary
              ? const Color(0xFF93C5FD)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor:
                contact.isPrimary ? const Color(0xFF2563EB) : Colors.white,
            child: Text(
              contact.name.isEmpty ? '?' : contact.name[0].toUpperCase(),
              style: TextStyle(
                color: contact.isPrimary ? Colors.white : const Color(0xFF2563EB),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        contact.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (contact.isPrimary) ...[
                      const SizedBox(width: 6),
                      _badge('Primary'),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${contact.relation} • ${contact.phone.isEmpty ? 'No phone' : contact.phone}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'primary') _setPrimary(index);
              if (value == 'edit') _openContactSheet(contact: contact, index: index);
              if (value == 'delete') _deleteContact(index);
            },
            itemBuilder: (context) => [
              if (!contact.isPrimary)
                const PopupMenuItem(value: 'primary', child: Text('Make primary')),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSafetyWordsCard() {
    return _buildCard(
      children: [
        const Text(
          'Safety Words & Commands',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        _input(
          controller: _safeWordController,
          label: 'Cancel safe word',
          icon: Icons.verified_user_rounded,
        ),
        const SizedBox(height: 12),
        _input(
          controller: _sosCommandController,
          label: 'SOS voice command',
          icon: Icons.sos_rounded,
        ),
        const SizedBox(height: 12),
        _input(
          controller: _fakeCallCommandController,
          label: 'Fake call command',
          icon: Icons.call_rounded,
        ),
      ],
    );
  }

  Widget _buildPreferencesCard() {
    return _buildCard(
      children: [
        const Text(
          'Emergency Preferences',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        _switchTile(
          icon: Icons.location_on_rounded,
          title: 'Auto-share live location',
          value: _autoShareLocation,
          onChanged: (value) => setState(() => _autoShareLocation = value),
        ),
        _switchTile(
          icon: Icons.videocam_rounded,
          title: 'Start evidence mode after SOS',
          value: _autoStartEvidence,
          onChanged: (value) => setState(() => _autoStartEvidence = value),
        ),
        _switchTile(
          icon: Icons.bubble_chart_rounded,
          title: 'Show floating safety bubble',
          value: _enableOverlayBubble,
          onChanged: (value) => setState(() => _enableOverlayBubble = value),
        ),
      ],
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: const Color(0xFF2563EB)),
      title: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF0F172A),
          fontWeight: FontWeight.w700,
        ),
      ),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF15803D),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _input({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: _inputDecoration(label).copyWith(prefixIcon: Icon(icon)),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
    );
  }
}

class _ContactSheet extends StatefulWidget {
  final List<String> relations;
  final EmergencyContact? initial;
  final bool makePrimary;

  const _ContactSheet({
    required this.relations,
    this.initial,
    required this.makePrimary,
  });

  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _whatsappController;
  late String _relation;
  late bool _isPrimary;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _phoneController = TextEditingController(text: initial?.phone ?? '');
    _whatsappController = TextEditingController(text: initial?.whatsapp ?? '');
    _relation = widget.relations.contains(initial?.relation)
        ? initial!.relation
        : 'Mom';
    _isPrimary = widget.makePrimary || (initial?.isPrimary ?? false);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _whatsappController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact name is required')),
      );
      return;
    }
    Navigator.pop(
      context,
      EmergencyContact(
        name: _nameController.text.trim(),
        relation: _relation,
        phone: _phoneController.text.trim(),
        whatsapp: _whatsappController.text.trim(),
        isPrimary: _isPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                widget.initial == null ? 'Add Emergency Contact' : 'Edit Contact',
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _relation,
                decoration: _inputDecoration('Relation'),
                items: widget.relations
                    .map(
                      (item) => DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _relation = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: _inputDecoration('Contact name').copyWith(
                  prefixIcon: const Icon(Icons.person_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration('Phone number').copyWith(
                  prefixIcon: const Icon(Icons.call_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _whatsappController,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration('WhatsApp number').copyWith(
                  prefixIcon: const Icon(Icons.chat_rounded),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _isPrimary,
                onChanged: (value) => setState(() => _isPrimary = value),
                title: const Text(
                  'Use as primary SOS contact',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Save Contact'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
      ),
    );
  }
}

class EmergencyContact {
  final String name;
  final String relation;
  final String phone;
  final String whatsapp;
  final bool isPrimary;

  const EmergencyContact({
    required this.name,
    required this.relation,
    required this.phone,
    required this.whatsapp,
    required this.isPrimary,
  });

  EmergencyContact copyWith({
    String? name,
    String? relation,
    String? phone,
    String? whatsapp,
    bool? isPrimary,
  }) {
    return EmergencyContact(
      name: name ?? this.name,
      relation: relation ?? this.relation,
      phone: phone ?? this.phone,
      whatsapp: whatsapp ?? this.whatsapp,
      isPrimary: isPrimary ?? this.isPrimary,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'relation': relation,
        'phone': phone,
        'whatsapp': whatsapp,
        'isPrimary': isPrimary,
      };

  factory EmergencyContact.fromJson(dynamic json) {
    final data = json as Map<String, dynamic>;
    return EmergencyContact(
      name: data['name']?.toString() ?? '',
      relation: data['relation']?.toString() ?? 'Mom',
      phone: data['phone']?.toString() ?? '',
      whatsapp: data['whatsapp']?.toString() ?? '',
      isPrimary: data['isPrimary'] == true,
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
