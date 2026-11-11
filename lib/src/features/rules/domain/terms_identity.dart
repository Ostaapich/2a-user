import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'rule_item.dart';

class TermsIdentity {
  TermsIdentity({
    required this.agentId,
    required this.clientId,
    required Iterable<RuleItem> rules,
  }) {
    final sorted = rules.toList()..sort((a, b) => a.slug.compareTo(b.slug));
    revision = sha256
        .convert(
          utf8.encode(
            jsonEncode(
              sorted
                  .map(
                    (r) => [
                      r.slug,
                      r.title,
                      r.content,
                      r.order,
                      r.updatedAt?.toUtc().toIso8601String(),
                    ],
                  )
                  .toList(),
            ),
          ),
        )
        .toString();
    for (final rule in sorted) {
      final date = rule.updatedAt;
      if (date != null && (updatedAt == null || date.isAfter(updatedAt!))) {
        updatedAt = date;
      }
    }
  }
  TermsIdentity.fromServer({
    required this.agentId,
    required this.clientId,
    required this.revision,
    required Iterable<RuleItem> rules,
  }) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(revision)) {
      throw const FormatException('Invalid server revision');
    }
    for (final rule in rules) {
      final date = rule.updatedAt;
      if (date != null && (updatedAt == null || date.isAfter(updatedAt!))) {
        updatedAt = date;
      }
    }
  }
  final int agentId, clientId;
  late final String revision;
  DateTime? updatedAt;
  String get accountScope => '$agentId:$clientId';
  String get displayVersion => revision.substring(0, 8);
}
