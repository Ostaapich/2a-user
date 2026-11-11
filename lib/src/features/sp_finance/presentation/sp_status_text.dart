import 'package:flutter/widgets.dart';
import '../../../core/utils/locale_text.dart';

/// Display metadata mirrors the existing SP API codes; never changes their values.
String spStatusText(BuildContext context, String value) {
  const labels = <String, (String, String)>{
    'draft': ('Черновик', '草稿'),
    'open': ('Принимает товары', '接收商品'),
    'closed_for_items': ('Приём закрыт', '已停止接收'),
    'purchasing': ('Выкуп', '采购中'),
    'purchased': ('Выкуплено', '已采购'),
    'in_transit': ('В пути', '运输中'),
    'arrived_msk': ('Прибыло в МСК', '已到莫斯科'),
    'sorting': ('Разбор товаров', '商品分拣'),
    'calculating': ('Расчёт доставки', '计算运费'),
    'collecting_payments': ('Сбор оплат', '收款中'),
    'shipping_to_customers': ('Отправка клиентам', '发货给客户'),
    'completed': ('Завершено', '已完成'),
    'cancelled': ('Отменено', '已取消'),
    'requested': ('Запрошен', '已申请'),
    'need_info': ('Нужны данные', '需要信息'),
    'approved': ('Подтверждён', '已确认'),
    'not_purchased': ('Не выкуплен', '未采购'),
    'arrived': ('Прибыл', '已到达'),
    'sorted': ('Разобран', '已分拣'),
    'ready_to_ship': ('Готов к отправке', '待发货'),
    'sent_to_customer': ('Отправлен клиенту', '已发给客户'),
    'delivered': ('Доставлен', '已送达'),
    'goods_payment': ('Оплата товаров', '商品付款'),
    'delivery_payment': ('Оплата доставки', '运费付款'),
    'extra_payment': ('Доплата', '补款'),
    'planned': ('Ожидает оплаты', '待付款'),
    'paid': ('Оплачено', '已付款'),
    'pending': ('Ожидает обработки', '待处理'),
  };
  final label = labels[value];
  return label == null
      ? value.replaceAll('_', ' ').trim()
      : tr(context, ru: label.$1, zh: label.$2);
}
