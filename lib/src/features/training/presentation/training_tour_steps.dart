import 'package:flutter/material.dart';

import 'training_lessons.dart';
import '../../../core/ui/app_layout.dart';
import '../../../core/utils/locale_text.dart';

/// A real control the client can use to reveal a step's exact target.
class TrainingTourPreparation {
  final String targetId;
  final String instruction;
  final String? title;
  final bool blocked;
  final int maxAutomaticActivations;

  const TrainingTourPreparation({
    required this.targetId,
    required this.instruction,
    this.title,
    this.blocked = false,
    this.maxAutomaticActivations = 1,
  });
}

/// A localized lesson step and the existing interface it explains.
/// Navigation and interaction are owned by the tour host.
class TrainingTourStep {
  final String lessonId;
  final int lessonStep;
  final String title;
  final String body;
  final String action;
  final String route;
  final String targetId;
  final String? capability;
  final List<TrainingTourPreparation> preparations;
  final List<String> allowedRoutePrefixes;
  final String? advanceTargetId;
  final bool waitForAction;
  final String? readyTargetId;
  final String? missingMessage;
  final bool autoActivateTarget;

  const TrainingTourStep({
    required this.lessonId,
    required this.lessonStep,
    required this.title,
    required this.body,
    required this.action,
    required this.route,
    required this.targetId,
    this.capability,
    this.preparations = const [],
    this.allowedRoutePrefixes = const [],
    this.advanceTargetId,
    this.waitForAction = false,
    this.readyTargetId,
    this.missingMessage,
    this.autoActivateTarget = false,
  });

  String get id => '$lessonId:$lessonStep';

  bool matchesPath(String path) =>
      path == route || allowedRoutePrefixes.any(path.startsWith);
}

// Each target is a specific control or value, never a route or whole card.
const _destinations = <String, List<(String, String, String?)>>{
  'cabinet': [
    ('/', 'nav.home', null),
    ('/', 'nav.code', null),
    ('/profile', 'profile.edit', null),
    ('/', 'nav.notifications', null),
  ],
  'warehouse': [
    ('/', 'warehouse.copy-address', null),
    ('/', 'warehouse.copy-phone', null),
    ('/', 'warehouse.check', null),
    ('/', 'warehouse.screenshot', null),
  ],
  'tracks': [
    ('/tracks', 'tracks.add.form', null),
    ('/tracks', 'track.status', null),
    ('/tracks', 'tracks.search', null),
    ('/tracks', 'track.product', null),
  ],
  'track_actions': [
    ('/tracks', 'track.open', null),
    ('/photos', 'photos.open', null),
    ('/tracks', 'track.question', null),
    ('/tracks', 'track.return', null),
    ('/tracks', 'track.transfer', null),
  ],
  'assembly': [
    ('/tracks', 'tracks.selection', null),
    ('/tracks', 'assembly.submit', null),
    ('/tracks', 'assembly.tariff', null),
    ('/tracks', 'assembly.packaging', null),
    ('/tracks', 'assembly.review', null),
    ('/tracks', 'assembly.open', null),
  ],
  'tariffs': [
    ('/tariffs', 'tariffs.name', null),
    ('/calculator', 'calculator.weight', null),
    ('/calculator', 'calculator.result', null),
  ],
  'delivery': [
    ('/tracks', 'assembly.tab.tracks', null),
    ('/tracks', 'assembly.tab.places', null),
    ('/tracks', 'assembly.tab.delivery', null),
    ('/tracks', 'assembly.status.details', null),
    ('/tracks', 'assembly.tab.video', null),
  ],
  'payments': [
    ('/invoices', 'invoice.amount', null),
    ('/invoices', 'invoice.pay', null),
    ('/payment-chat', 'payment.message', null),
    ('/referral', 'referral.balance', null),
  ],
  'self_buyout': [
    ('/', 'menu.self-buyout', 'self_buyout'),
    ('/self-buyout', 'selfbuyout.amount', 'self_buyout'),
    ('/self-buyout', 'selfbuyout.requisites', 'self_buyout'),
    ('/self-buyout', 'selfbuyout.terms', 'self_buyout'),
    ('/self-buyout', 'selfbuyout.submit', 'self_buyout'),
    ('/self-buyout', 'selfbuyout.request.open', 'self_buyout'),
    ('/self-buyout', 'selfbuyout.request.status', 'self_buyout'),
  ],
  'purchases': [
    ('/purchase-blanks', 'purchase.create', null),
    ('/shop', 'shop.product.open', 'shop'),
    ('/garage', 'garage.request.create', 'garage'),
    ('/purchase-blanks', 'purchase.request.open', null),
  ],
  'organizer': [
    ('/sp-finance', 'organizer.open', null),
    ('/sp-finance', 'organizer.tab.participants', null),
    ('/sp-finance', 'organizer.tab.finance', null),
    ('/sp-finance', 'organizer.tab.tracks', null),
  ],
  'help': [
    ('/partner-program', 'partner.invite', 'partner_program'),
    ('/search-nocode', 'nocode.search', null),
    ('/news', 'news.open', null),
    ('/rules', 'rules.open', null),
    ('/support', 'support.message', null),
  ],
};

List<TrainingTourPreparation> _preparations(
  BuildContext context,
  String lessonId,
  int index,
) {
  TrainingTourPreparation hint(
    String target,
    String ru,
    String zh, {
    bool blocked = false,
    int maxAutomaticActivations = 1,
  }) => TrainingTourPreparation(
    targetId: target,
    instruction: tr(context, ru: ru, zh: zh),
    blocked: blocked,
    maxAutomaticActivations: maxAutomaticActivations,
  );
  final more = hint(
    'nav.more',
    'Нажмите «Ещё», чтобы открыть меню.',
    '点击“更多”打开菜单。',
  );
  final groups = hint(
    'tracks.view.switch-to-groups',
    'Переключите представление на «Сборки».',
    '将列表切换为“集运单”。',
  );
  final singles = hint(
    'tracks.view.switch-to-singles',
    'Переключите представление на «Треки».',
    '将列表切换为“运单”。',
  );
  final assembly = hint(
    'assembly.open',
    'Нажмите номер сборки, чтобы открыть её вкладки.',
    '点击集运单号，打开详情选项卡。',
  );
  final dismissSheet = hint(
    'track.sheet.dismiss-handle',
    AppLayout.useSideNavigation(context)
        ? 'Закройте текущее окно: потяните выделенную ручку вправо.'
        : 'Закройте текущее окно: потяните выделенную ручку вниз.',
    AppLayout.useSideNavigation(context)
        ? '向右拖动高亮把手，关闭当前窗口。'
        : '向下拖动高亮把手，关闭当前窗口。',
  );
  final selection = hint(
    'tracks.selection',
    'Выберите флажком трек на складе. После выбора появится «Отправка на сборку».',
    '勾选已入库运单，随后会显示“提交集运”按钮。',
  );
  final wizard = [
    hint(
      'assembly.required.goods-description',
      'Заполните описание товара для выделенного трека. Без него форма не пропустит дальше.',
      '填写高亮运单的商品说明，否则无法继续。',
    ),
    hint(
      'assembly.required.places',
      'Выберите, объединять ли груз в одно место. После выбора можно продолжить.',
      '选择是否合并为一件，然后继续。',
    ),
    hint(
      'assembly.required.packaging',
      'Выберите основную упаковку из доступных вариантов.',
      '选择一种可用的主包装。',
    ),
    hint(
      'assembly.required.insurance-amount',
      'Укажите страховую стоимость, поскольку выбрано страхование груза.',
      '已选择保险，请填写投保金额。',
    ),
    for (var step = 0; step < 3; step++)
      hint(
        'assembly.wizard.ready.$step',
        'Параметры этого шага заполнены. Нажмите «Далее», чтобы перейти к следующей части формы.',
        '当前步骤已填写。点击“下一步”继续填写表单。',
      ),
    hint(
      'assembly.submit',
      'Нажмите «Отправка на сборку», чтобы открыть форму выбранных треков.',
      '点击“提交集运”，打开所选运单的表单。',
    ),
    selection,
    singles,
    dismissSheet,
  ];
  final selfBuyoutForm = [
    hint(
      'selfbuyout.instruction.continue',
      'Прочитайте инструкцию и нажмите выделенную кнопку продолжения, чтобы открыть заявку.',
      '阅读说明，点击高亮的继续按钮打开申请表。',
    ),
    hint(
      'selfbuyout.experience.yes',
      'Ответьте честно: пополняли ли вы Alipay ранее хотя бы 3 раза? Выберите «Да» или «Нет»; от ответа зависит инструкция.',
      '请如实回答：此前是否至少充值过支付宝3次？选择“是”或“否”，系统会显示对应说明。',
    ),
    hint(
      'selfbuyout.create',
      'Нажмите «Создать заявку» на странице самовыкупа. Сначала откроется инструкция, затем форма; отправка выполняется отдельной кнопкой в форме.',
      '点击自主采购页面的“创建申请”。先显示说明，再打开表单；提交需在表单内单独确认。',
    ),
    hint(
      'selfbuyout.create.unavailable',
      'Новая заявка пока недоступна: прочитайте причину рядом с кнопкой. Пропустите шаг или вернитесь после восстановления сервиса.',
      '暂时无法新建申请，请阅读按钮旁的原因。可跳过此步骤，待服务恢复后重试。',
      blocked: true,
    ),
    hint(
      'selfbuyout.operators.unavailable',
      'Операторы сейчас недоступны. Прочитайте сообщение сервиса и вернитесь к созданию заявки позднее.',
      '当前无操作员在线。请阅读服务提示，稍后再创建申请。',
      blocked: true,
    ),
  ];
  return switch ('$lessonId:$index') {
    'warehouse:0' => [
      hint(
        'notification.sheet.dismiss',
        'Закройте уведомления выделенной ручкой, чтобы увидеть адрес склада.',
        '拖动高亮把手关闭通知，查看仓库地址。',
      ),
    ],
    'warehouse:3' => [
      hint(
        'warehouse.check',
        'Нажмите «Проверить заполнение» и сразу выберите скриншот. Затем автоматически откроется проверка.',
        '点击“检查填写”后直接选择截图，随后会自动打开核对窗口。',
      ),
    ],
    'tracks:0' => [
      hint(
        'tracks.add',
        'Нажмите «+», чтобы открыть поле трек-номера.',
        '点击“+”打开运单号输入框。',
      ),
      singles,
      dismissSheet,
    ],
    'assembly:1' => [selection, singles, dismissSheet],
    'tracks:1' ||
    'tracks:2' ||
    'tracks:3' ||
    'track_actions:0' ||
    'track_actions:2' ||
    'track_actions:3' ||
    'track_actions:4' ||
    'assembly:0' => [singles, dismissSheet],
    'assembly:5' => [groups, dismissSheet],
    'assembly:2' => [
      hint(
        'assembly.wizard.back-to-tariff',
        'Нажмите «Назад», чтобы вернуться к выбору тарифа.',
        '点击“上一步”返回运价选择。',
        maxAutomaticActivations: 3,
      ),
      ...wizard,
    ],
    'assembly:3' => [
      hint(
        'assembly.wizard.back-to-packaging',
        'Нажмите «Назад», чтобы вернуться к упаковке.',
        '点击“上一步”返回包装设置。',
      ),
      ...wizard,
    ],
    'assembly:4' => wizard,
    'tariffs:2' => [
      hint(
        'calculator.missing.weight',
        'Введите вес груза в килограммах.',
        '输入货物重量（公斤）。',
      ),
      hint(
        'calculator.missing.volume',
        'Введите объём груза в кубических метрах.',
        '输入货物体积（立方米）。',
      ),
      hint(
        'calculator.missing.places',
        'Укажите количество грузовых мест.',
        '填写包裹件数。',
      ),
      hint(
        'calculator.missing.tracks',
        'Укажите количество треков.',
        '填写运单数量。',
      ),
      hint(
        'calculator.missing.photos',
        'Количество треков с фото должно быть от нуля до общего количества треков. Исправьте это поле.',
        '有照片的运单数必须在零到运单总数之间，请修正此字段。',
      ),
      hint(
        'calculator.missing.insurance',
        'Вы включили страхование. Укажите страховую стоимость больше нуля или отключите страхование, если оно не требуется.',
        '已启用保险，请填写大于零的投保金额；如不需要保险，可关闭此选项。',
      ),
      hint(
        'calculator.missing.packaging',
        'Выберите основную упаковку. После заполнения обязательных параметров появится расчёт.',
        '选择主包装。填写完必填参数后将显示计算结果。',
      ),
    ],
    'delivery:0' ||
    'delivery:1' ||
    'delivery:2' ||
    'delivery:4' => [assembly, groups, dismissSheet],
    'delivery:3' => [
      hint(
        'assembly.tab.main',
        'Откройте вкладку «Основное», чтобы увидеть статус сборки.',
        '打开“基本信息”选项卡查看集运状态。',
      ),
      assembly,
      groups,
      dismissSheet,
    ],
    'payments:0' => [
      hint(
        'invoice.open',
        'Нажмите номер счёта, чтобы открыть его сумму и состав.',
        '点击账单号，查看金额与明细。',
      ),
    ],
    'payments:1' => [
      hint(
        'invoice.open-payable',
        'Откройте счёт, который ещё нужно оплатить.',
        '打开尚需付款的账单。',
      ),
      hint(
        'invoice.pay.unavailable',
        'Приём оплаты сейчас недоступен: прочитайте сообщение операторов. Пропустите шаг и вернитесь, когда приём оплаты возобновится.',
        '当前暂不受理付款，请阅读操作员提示。可跳过此步骤，待付款服务恢复后返回。',
        blocked: true,
      ),
      hint(
        'invoice.sheet.dismiss',
        'Если текущий счёт уже оплачен, закройте его выделенной ручкой и откройте счёт к оплате.',
        '如果当前账单已付清，请拖动高亮把手关闭，然后打开待付款账单。',
      ),
    ],
    'self_buyout:0' || 'help:5' => [more],
    'self_buyout:1' ||
    'self_buyout:2' ||
    'self_buyout:3' ||
    'self_buyout:4' => selfBuyoutForm,
    'self_buyout:5' => [
      hint(
        'selfbuyout.sheet.dismiss',
        'Закройте текущее окно, потянув выделенную ручку вниз. В списке можно открыть существующую заявку по номеру.',
        '向下拖动高亮把手关闭窗口，然后在列表中按编号打开已有申请。',
      ),
    ],
    'self_buyout:6' => [
      hint(
        'selfbuyout.request.open',
        'Нажмите номер существующей заявки, чтобы открыть статус и дальнейшие действия.',
        '点击已有申请的编号，查看状态及后续操作。',
      ),
    ],
    'purchases:1' => [
      hint(
        'shop.search',
        'Выберите площадку и найдите товар через это поле поиска.',
        '选择平台并在此搜索商品。',
      ),
      hint(
        'shop.marketplace',
        'Выберите доступную площадку для поиска товара.',
        '选择可用平台以搜索商品。',
      ),
    ],
    'purchases:2' => [
      hint(
        'garage.vehicle.create',
        'Сначала нужен автомобиль. Здесь открывается его добавление; создавайте запись только для своего автомобиля.',
        '需要先添加车辆。此按钮打开添加表单，请填写自己的车辆。',
      ),
    ],
    'organizer:1' || 'organizer:2' || 'organizer:3' => [
      hint(
        'organizer.open',
        'Откройте закупку по её названию, чтобы увидеть вкладки участников, финансов и треков.',
        '点击采购名称，查看成员、财务及运单选项卡。',
      ),
    ],
    _ => const [],
  };
}

String? _missingMessage(BuildContext context, String lessonId, int index) {
  final ru = switch ('$lessonId:$index') {
    'self_buyout:5' || 'self_buyout:6' =>
      'Для этого шага нужна существующая заявка на самовыкуп. Если список пуст, пропустите шаг и вернитесь после создания своей заявки.',
    'payments:1' =>
      'Способы оплаты показываются в счёте с остатком к оплате. Если таких счетов нет, этот шаг можно пропустить.',
    'help:0' =>
      'Приглашение появится, когда для вашего аккаунта доступна партнёрская ссылка. Если ссылки нет, пропустите этот шаг.',
    _ => switch (lessonId) {
      'delivery' =>
        'Здесь нужна существующая сборка. Переключитесь на «Сборки» и откройте её номер. Если сборок ещё нет, пройдите учебную сборку в теме «Отправить треки на сборку».',
      'tracks' || 'track_actions' || 'assembly' =>
        'Нужен трек или сборка с доступным действием. Проверьте поиск и фильтры списка; нужная кнопка зависит от статуса. Если подходящих записей нет, пропустите шаг или пройдите учебную сборку.',
      'organizer' =>
        'Откройте существующую совместную закупку. Если список пуст, пропустите этот шаг и вернитесь, когда закупка появится.',
      'payments' =>
        'Данные появятся при наличии счёта или доступного сервиса. Если список пуст, пропустите шаг и вернитесь к нему позже.',
      'purchases' =>
        'Для этого шага нужна доступная карточка товара, автомобиль или заявка. Если список пуст, воспользуйтесь поиском либо пропустите шаг.',
      _ => null,
    },
  };
  return ru == null
      ? null
      : tr(
          context,
          ru: ru,
          zh: '此步骤需要已有且可用的记录。请检查列表、搜索及筛选条件；若尚无对应记录，可跳过并稍后返回。',
        );
}

/// Builds the full 12-lesson, 55-step tour without changing application state.
/// Fails on structural content drift rather than silently omitting a lesson or
/// assigning a new step the destination of another step.
List<TrainingTourStep> trainingTourSteps(BuildContext context) {
  final lessons = trainingLessons(context);
  final lessonIds = lessons.map((lesson) => lesson.id).toSet();
  if (lessons.length != 12 ||
      lessonIds.length != lessons.length ||
      lessonIds.length != _destinations.length ||
      !_destinations.keys.every(lessonIds.contains)) {
    throw StateError('Training lessons and tour destinations are out of sync.');
  }

  final steps = <TrainingTourStep>[];
  for (final lesson in lessons) {
    final destinations = _destinations[lesson.id]!;
    if (lesson.steps.length != destinations.length) {
      throw StateError(
        'Training lesson ${lesson.id} has ${lesson.steps.length} steps but '
        '${destinations.length} tour destinations.',
      );
    }
    for (var index = 0; index < lesson.steps.length; index++) {
      final content = lesson.steps[index];
      final (route, targetId, capability) = destinations[index];
      steps.add(
        TrainingTourStep(
          lessonId: lesson.id,
          lessonStep: index,
          title: content.title,
          body: content.body,
          action: content.action,
          route: route,
          targetId: targetId,
          capability: capability,
          preparations: _preparations(context, lesson.id, index),
          missingMessage: _missingMessage(context, lesson.id, index),
          autoActivateTarget:
              targetId.startsWith('assembly.tab.') ||
              targetId.startsWith('organizer.tab.'),
          allowedRoutePrefixes: lesson.id == 'organizer' && index > 0
              ? const ['/sp-finance/purchases/']
              : lesson.id == 'help' && index == 2
              ? const ['/news/']
              : lesson.id == 'help' && index == 3
              ? const ['/rules/']
              : const [],
        ),
      );
    }
  }
  if (steps.length != 55) {
    throw StateError('Expected 55 training tour steps, got ${steps.length}.');
  }
  return List.unmodifiable(steps);
}
