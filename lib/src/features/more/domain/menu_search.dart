/// Search aliases describe existing menu actions, never grant access to them.
/// The caller supplies only entries already permitted by the current UI state.
enum MenuSearchEntry {
  paymentChat,
  support,
  selfBuyout,
  translator,
  garage,
  purchaseBlanks,
  jointPurchases,
  unlinkedTrack,
  tariffs,
  calculator,
  training,
  profile,
  referral,
  partner,
  news,
  rules,
  updates,
  sentry,
}

const menuSearchAliases = <MenuSearchEntry, String>{
  MenuSearchEntry.paymentChat:
      'Чат по оплатам оплата счетов оплатить платеж платежи квитанция чек payment invoice 支付 付款 账单 支付账单 缴费',
  MenuSearchEntry.support:
      'Чат поддержки помощь менеджера связь вопрос написать сотрудник support help 联系 客服 帮助 经理',
  MenuSearchEntry.selfBuyout:
      'Самовыкуп самостоятельный выкуп оплатить юань юани alipay алипей 1688 taobao 自助采购 自购 自主采购 人民币 支付宝',
  MenuSearchEntry.translator:
      'Переводчик перевод экрана перевести китайский translate translator 翻译器 翻译 屏幕翻译',
  MenuSearchEntry.garage:
      'Гараж запчасти заказы автомобиль автомобили машина авто детали garage car 汽配 汽车 配件 车库',
  MenuSearchEntry.purchaseBlanks:
      'Выкуп по бланку заявки выкуп товаров по ссылкам ссылки заказать покупка бланки форма procurement 代购 采购单 采购申请 商品链接',
  MenuSearchEntry.jointPurchases:
      'Совместные покупки закупки СП организатор финансы участие совместная закупка joint group 团购 拼单 合购 组织者',
  MenuSearchEntry.unlinkedTrack:
      'Поиск трека без кода склад посылка непривязанный потерянный найти отыскать трек номер nocode 未关联 未认领 无客户代码 运单 查询包裹',
  MenuSearchEntry.tariffs:
      'Тарифы стоимость услуг доставка расценки цены цена тариф rates 运费 费用 价格 资费',
  MenuSearchEntry.calculator:
      'Калькулятор предварительный расчет сборки рассчитать посчитать стоимость доставка цены вес объем calculator 计算器 计算 运费计算 估算 集运',
  MenuSearchEntry.training:
      'Обучение инструкция инструкции как пользоваться возможности учебная сборка урок руководство training tutorial 学习 教程 使用说明 功能介绍 集运练习',
  MenuSearchEntry.profile:
      'Профиль аккаунт настройки личные данные имя телефон email пароль profile account 个人资料 账户 设置 密码 手机 邮箱',
  MenuSearchEntry.referral:
      'Реферальная программа бонусные килограммы приглашения пригласить друга реферал бонус referral 邀请好友 推荐 奖励 公斤',
  MenuSearchEntry.partner:
      'Партнерская программа приглашения комиссия выплаты партнер доход заработок partner 合作伙伴 佣金 收益 提现',
  MenuSearchEntry.news:
      'Новости обновления объявления новое новости news 新闻 公告 动态',
  MenuSearchEntry.rules:
      'Правила условия работы склада доставка договор оферта соглашение rules terms 规则 条款 协议 仓库',
  MenuSearchEntry.updates:
      'Проверить обновления новая версия приложения обновить update version 检查更新 版本 升级',
  MenuSearchEntry.sentry: 'Verify Sentry Setup тестовая ошибка проверка sentry',
};

String _normalize(String value) => value
    .toLowerCase()
    .replaceAll('ё', 'е')
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

// Bounded Russian inflection support, not fuzzy matching: retain >=4 letters.
// Explicit aliases above cover different roots (e.g. «расчет» / «посчитать»).
String _stem(String word) {
  if (!RegExp(r'^[а-я]+$').hasMatch(word)) return word;
  for (final ending in [
    'иями',
    'ами',
    'ями',
    'ого',
    'ему',
    'ому',
    'ыми',
    'ими',
    'ать',
    'ять',
    'ить',
    'ов',
    'ев',
    'ам',
    'ям',
    'ах',
    'ях',
    'ой',
    'ей',
    'ий',
    'ый',
    'ая',
    'яя',
    'ое',
    'ее',
    'ые',
    'ие',
    'ом',
    'ем',
    'у',
    'ю',
    'а',
    'я',
    'ы',
    'и',
    'е',
  ]) {
    if (word.endsWith(ending) && word.length - ending.length >= 4) {
      return word.substring(0, word.length - ending.length);
    }
  }
  return word;
}

bool matchesMenuSearch(
  String query,
  MenuSearchEntry entry, {
  String title = '',
  String subtitle = '',
}) {
  final normalized = _normalize(query);
  if (normalized.isEmpty) return true;
  final corpus = _normalize(
    '$title $subtitle ${menuSearchAliases[entry] ?? ''}',
  );
  final words = corpus.split(' ');
  return normalized.split(' ').every((token) {
    if (RegExp(r'[\u3400-\u9fff]').hasMatch(token)) {
      return corpus.contains(token);
    }
    final stem = _stem(token);
    return words.any(
      (word) =>
          word == token ||
          _stem(word) == stem ||
          (stem.length >= 3 && word.startsWith(stem)),
    );
  });
}
