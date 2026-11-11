import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twoalogisticcabineuser/src/core/services/showcase_service.dart';
import 'package:twoalogisticcabineuser/src/features/rules/domain/rule_item.dart';
import 'package:twoalogisticcabineuser/src/features/rules/domain/terms_identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'acceptance is isolated by agent, account and actual document revision',
    () async {
      SharedPreferences.setMockInitialValues({'terms_accepted': true});
      final service = ShowcaseService(await SharedPreferences.getInstance());
      const first = RuleItem(
        slug: '1',
        title: 'Terms',
        excerpt: '',
        content: 'Original terms',
        order: 1,
      );
      const second = RuleItem(
        slug: '1',
        title: 'Terms',
        excerpt: '',
        content: 'Updated terms',
        order: 1,
      );
      final a = TermsIdentity(agentId: 1, clientId: 45, rules: [first]);
      final b = TermsIdentity(agentId: 1, clientId: 46, rules: [first]);
      final c = TermsIdentity(agentId: 2, clientId: 45, rules: [first]);
      final update = TermsIdentity(agentId: 1, clientId: 45, rules: [second]);
      expect(
        service.hasAcceptedTermsFor(
          accountScope: a.accountScope,
          revision: a.revision,
        ),
        isFalse,
      );
      await service.acceptTermsFor(
        accountScope: a.accountScope,
        revision: a.revision,
      );
      expect(
        service.hasAcceptedTermsFor(
          accountScope: a.accountScope,
          revision: a.revision,
        ),
        isTrue,
      );
      for (final different in [b, c, update]) {
        expect(
          service.hasAcceptedTermsFor(
            accountScope: different.accountScope,
            revision: different.revision,
          ),
          isFalse,
        );
      }
    },
  );
}
