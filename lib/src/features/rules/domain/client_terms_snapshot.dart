import 'rule_item.dart';
import 'terms_identity.dart';

/// Exact published bundle and acknowledgement returned by the authenticated
/// server. A device-local acceptance flag never grants server acceptance.
class ClientTermsSnapshot {
  const ClientTermsSnapshot({
    required this.clientId,
    required this.agentId,
    required this.available,
    required this.accepted,
    required this.rules,
    this.revision,
    this.acceptedAt,
  });
  final int clientId, agentId;
  final bool available, accepted;
  final String? revision;
  final DateTime? acceptedAt;
  final List<RuleItem> rules;

  factory ClientTermsSnapshot.fromJson(Map<String, dynamic> json) {
    final clientId = json['clientId'], agentId = json['agentId'];
    if (clientId is! int || agentId is! int || clientId < 1 || agentId < 1) {
      throw const FormatException('Missing terms owner');
    }
    final available = json['available'] == true;
    if (!available) {
      return ClientTermsSnapshot(
        clientId: clientId,
        agentId: agentId,
        available: false,
        accepted: false,
        rules: const [],
      );
    }
    final revision = json['revision'];
    final rawRules = json['rules'];
    if (revision is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(revision) ||
        rawRules is! List ||
        rawRules.isEmpty) {
      throw const FormatException('Incomplete terms bundle');
    }
    final rules = rawRules
        .map((raw) {
          final data = Map<String, dynamic>.from(raw as Map);
          if (data['agentId'] != agentId ||
              data['id'] == null ||
              data['title'] is! String ||
              data['content'] is! String) {
            throw const FormatException('Invalid terms document');
          }
          return RuleItem.fromJson(data);
        })
        .toList(growable: false);
    final acceptedAt = DateTime.tryParse(json['acceptedAt']?.toString() ?? '');
    if (json['accepted'] == true && acceptedAt == null) {
      throw const FormatException('Missing server acceptance');
    }
    return ClientTermsSnapshot(
      clientId: clientId,
      agentId: agentId,
      available: true,
      accepted: json['accepted'] == true,
      revision: revision,
      acceptedAt: acceptedAt,
      rules: rules,
    );
  }
  TermsIdentity get identity {
    if (!available || revision == null || rules.isEmpty) {
      throw StateError('Terms unavailable');
    }
    return TermsIdentity.fromServer(
      agentId: agentId,
      clientId: clientId,
      revision: revision!,
      rules: rules,
    );
  }
}
