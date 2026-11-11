import 'package:flutter_test/flutter_test.dart';
import 'package:twoalogisticcabineuser/src/features/more/domain/menu_search.dart';

void main() {
  const cases = <MenuSearchEntry, List<String>>{
    MenuSearchEntry.paymentChat: ['СЧЁТ', 'оплатить', 'платежи', '账单', '支付账单'],
    MenuSearchEntry.support: ['менеджеру', 'помощь', '客服'],
    MenuSearchEntry.selfBuyout: ['самостоятельный выкуп', 'alipay', '自助采购'],
    MenuSearchEntry.translator: ['перевести', 'экрана перевод', '屏幕翻译'],
    MenuSearchEntry.garage: ['автомобиль', 'запчасти', '汽配'],
    MenuSearchEntry.purchaseBlanks: ['бланки', 'по ссылкам', '采购单'],
    MenuSearchEntry.jointPurchases: ['СП', 'закупки совместные', '团购'],
    MenuSearchEntry.unlinkedTrack: ['без кода', 'трек потерянный', '未认领'],
    MenuSearchEntry.tariffs: ['тарифах', 'расценки', '运费'],
    MenuSearchEntry.calculator: [
      'расчёт',
      'посчитать',
      'сборки расчет',
      'рассчитать доставку',
      '计算器',
      '运费计算',
    ],
    MenuSearchEntry.training: ['инструкции', 'как пользоваться', '使用说明'],
    MenuSearchEntry.profile: ['настройки', 'личные данные', '个人资料'],
    MenuSearchEntry.referral: [
      'пригласить друга',
      'бонусные килограммы',
      '邀请好友',
    ],
    MenuSearchEntry.partner: ['комиссию', 'выплаты', '合作伙伴'],
    MenuSearchEntry.news: ['объявления', 'новости', '新闻'],
    MenuSearchEntry.rules: ['оферта', 'условия склада', '条款'],
    MenuSearchEntry.updates: ['версия', 'обновить', '检查更新'],
    MenuSearchEntry.sentry: ['verify sentry', 'setup'],
  };
  test('inventory covers every existing action', () {
    expect(cases.keys.toSet(), MenuSearchEntry.values.toSet());
    expect(menuSearchAliases.keys.toSet(), MenuSearchEntry.values.toSet());
  });
  for (final entry in cases.entries) {
    test('synonyms and languages ${entry.key.name}', () {
      for (final query in entry.value) {
        expect(matchesMenuSearch(query, entry.key), isTrue, reason: query);
      }
    });
  }
  test('all tokens required, boundaries protect short abbreviations', () {
    expect(matchesMenuSearch('СП', MenuSearchEntry.rules), isFalse);
    expect(
      matchesMenuSearch('расчет телефон', MenuSearchEntry.calculator),
      isFalse,
    );
    expect(
      matchesMenuSearch(
        'полностью неизвестный запрос',
        MenuSearchEntry.profile,
      ),
      isFalse,
    );
    expect(
      matchesMenuSearch('  РАСЧЁТ,   СБОРКИ! ', MenuSearchEntry.calculator),
      isTrue,
    );
    expect(matchesMenuSearch('та', MenuSearchEntry.tariffs), isFalse);
    expect(matchesMenuSearch('   ', MenuSearchEntry.profile), isTrue);
    expect(
      matchesMenuSearch(
        'Дополнительный уникальный текст',
        MenuSearchEntry.profile,
        subtitle: 'Дополнительный уникальный текст',
      ),
      isTrue,
    );
  });
}
