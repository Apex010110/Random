// Deterministic grounded assistant: a line-by-line port of backend/app/ai/rules.py.
// Reads the same assets/seed/assistant_copy.json, so offline and backend answers match.

class Line {
  final String productId, name, size;
  final int quantity, unitPricePkr;
  final bool codEligible;
  const Line(this.productId, this.name, this.size, this.quantity, this.unitPricePkr, this.codEligible);
}

class AssistantContext {
  final String storeName, firstName, city;
  final List<Line> lines;
  final int subtotalPkr;
  final Map<String, dynamic> policy, settings;
  final List<Map<String, dynamic>> catalog;
  final DateTime nowLocal;
  final (String, int)? existingDiscount;
  final String candidateCode;
  const AssistantContext({
    required this.storeName,
    required this.firstName,
    required this.city,
    required this.lines,
    required this.subtotalPkr,
    required this.policy,
    required this.settings,
    required this.catalog,
    required this.nowLocal,
    this.existingDiscount,
    this.candidateCode = 'CC-0000',
  });
}

class Reply {
  final String text, intent, language;
  final double confidence;
  final String? action;
  final Map<String, dynamic> meta;
  const Reply(this.text, this.intent, this.confidence, this.language, {this.action, this.meta = const {}});
}

class AssistantRules {
  final Map<String, dynamic> copy;
  AssistantRules(this.copy);

  static final _urdu = RegExp(r'[؀-ۿ]');
  static final _word = RegExp(r'[a-z0-9%]+');
  static const maxInputChars = 500;

  List<String> _list(String k) => List<String>.from(copy[k] as List);

  String sanitize(String text) {
    var t = text.replaceAll('\x00', '').replaceAll(RegExp('[\\u200b-\\u200f\\u202a-\\u202e]'), '').trim();
    if (t.length > maxInputChars) t = t.substring(0, maxInputChars);
    return t;
  }

  List<String> words(String low) => [for (final m in _word.allMatches(low)) m.group(0)!];

  String detectLanguage(String text) {
    if (_urdu.hasMatch(text)) return 'ur';
    final ws = words(text.toLowerCase());
    final strong = ws.where(_list('roman_markers_strong').contains).length;
    final weak = ws.where(_list('roman_markers_weak').contains).length;
    if (strong >= 1 || weak >= 3) return 'roman';
    return 'en';
  }

  bool _matches(Map spec, String low, Set<String> ws) {
    if ((spec['words'] as List).any((w) => ws.contains(w))) return true;
    return (spec['phrases'] as List).any((p) => low.contains(p as String));
  }

  List<String> detectIntents(String text) {
    final low = text.toLowerCase();
    final ws = words(low).toSet();
    final intents = copy['intents'] as Map;
    return [for (final name in _list('intent_priority')) if (_matches(intents[name] as Map, low, ws)) name];
  }

  bool isInjection(String text) {
    final low = text.toLowerCase();
    return _list('injection_patterns').any(low.contains);
  }

  String t(String lang, String key, [Map<String, Object?> kw = const {}]) {
    var s = (copy['replies'][lang][key]) as String;
    kw.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }

  Map get _display => copy['display'] as Map;

  String fmtDate(DateTime d, String lang) {
    final disp = _display[lang] as Map;
    return '${(disp['weekdays'] as List)[d.weekday - 1]} ${d.day} ${(disp['months'] as List)[d.month - 1]}';
  }

  String weekdayLong(DateTime d, String lang) => ((_display[lang] as Map)['weekdays_long'] as List)[d.weekday - 1] as String;

  String cityLabel(String city, String lang) => (((_display[lang] as Map)['cities'] ?? const {}) as Map)[city] as String? ?? city;

  static DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// Business days are Monday-Saturday (Sunday off) in the demo policy.
  static DateTime addBusinessDays(DateTime start, int n) {
    var d = _dateOnly(start);
    var added = 0;
    while (added < n) {
      d = d.add(const Duration(days: 1));
      if (d.weekday != DateTime.sunday) added++;
    }
    return d;
  }

  (DateTime, DateTime, int, int, bool) deliveryWindow(Map policy, String city, DateTime today) {
    final windows = policy['delivery_windows'] as Map;
    final known = windows.containsKey(city);
    final w = List<int>.from((windows[city] ?? windows['default']) as List);
    return (addBusinessDays(today, w[0]), addBusinessDays(today, w[1]), w[0], w[1], known);
  }

  DateTime? detectTargetDay(String text, DateTime today) {
    final low = text.toLowerCase();
    final ws = words(low).toSet();
    final wd = copy['weekdays'] as Map;
    final t0 = _dateOnly(today);
    for (var idx = 0; idx < 7; idx++) {
      if (ws.contains((wd['en'] as List)[idx]) ||
          ws.contains((wd['en_short'] as List)[idx]) ||
          ws.contains((wd['roman'] as List)[idx]) ||
          text.contains((wd['ur'] as List)[idx] as String)) {
        final delta = (idx - (today.weekday - 1)) % 7;
        return t0.add(Duration(days: delta));
      }
    }
    final tw = _list('tomorrow_words');
    if (ws.contains(tw[0]) || ws.contains(tw[1]) || text.split(RegExp(r'\s+')).contains(tw[2])) {
      return t0.add(const Duration(days: 1));
    }
    return null;
  }

  String? detectCity(String text) {
    final low = text.toLowerCase();
    for (final e in (copy['city_aliases'] as Map).entries) {
      final alias = e.key as String;
      if (_urdu.hasMatch(alias)) {
        if (text.contains(alias)) return e.value as String;
      } else if (RegExp('\\b${RegExp.escape(alias)}\\b').hasMatch(low)) {
        return e.value as String;
      }
    }
    return null;
  }

  String? detectSize(String text) {
    final low = text.toLowerCase().replaceAll("'", '');
    final ws = words(low);
    final aliases = copy['size_aliases'] as Map;
    for (final w in ws) {
      if (const ['xl', 'small', 'medium', 'large'].contains(w)) return aliases[w] as String;
    }
    final m = RegExp(r'\b(?:size|in)\s+(xl|s|m|l)\b').firstMatch(low);
    if (m != null) return aliases[m.group(1)] as String;
    for (final w in ws) {
      if (const ['s', 'm', 'l'].contains(w)) return aliases[w] as String;
    }
    final m2 = RegExp(r'\bsize\s+(\d{1,2})\b').firstMatch(low);
    return m2?.group(1);
  }

  int? detectPercent(String text) {
    final m = RegExp(r'(\d{1,2})\s*%|(\d{1,2})\s*percent').firstMatch(text.toLowerCase());
    if (m == null) return null;
    return int.parse(m.group(1) ?? m.group(2)!);
  }

  static const _productKeywords = {
    'kurta': 'p_linen_kurta', 'linen': 'p_linen_kurta', 'kameez': 'p_kameez_navy', 'shalwar': 'p_kameez_navy',
    'lawn': 'p_lawn_suit', 'suit': 'p_lawn_suit', 'waistcoat': 'p_waistcoat', 'dupatta': 'p_dupatta',
    'chappal': 'p_chappal', 'bag': 'p_crossbody', 'crossbody': 'p_crossbody', 'denim': 'p_denim_shirt',
    'shirt': 'p_denim_shirt', 'jhumka': 'p_jhumka', 'earrings': 'p_jhumka', 'sherwani': 'p_sherwani',
    'کرتا': 'p_linen_kurta', 'دوپٹہ': 'p_dupatta',
  };

  Map<String, dynamic>? mentionedProduct(String text, List<Map<String, dynamic>> catalog) {
    final low = text.toLowerCase();
    final byId = {for (final p in catalog) p['id'] as String: p};
    for (final e in _productKeywords.entries) {
      final hit = _urdu.hasMatch(e.key) ? text.contains(e.key) : RegExp('\\b${e.key}\\b').hasMatch(low);
      if (hit && byId.containsKey(e.value)) return byId[e.value];
    }
    return null;
  }

  static List<String> inStockSizes(Map p) => [for (final v in (p['variants'] as List)) if ((v['stock'] as int) > 0) v['size'] as String];

  Map<String, dynamic>? alternativeFor(Map product, List<Map<String, dynamic>> catalog) {
    final same = catalog.where((p) => p['id'] != product['id'] && p['category'] == product['category'] && inStockSizes(p).isNotEmpty).toList();
    final pool = same.isNotEmpty ? same : catalog.where((p) => p['id'] != product['id'] && inStockSizes(p).isNotEmpty).toList();
    if (pool.isEmpty) return null;
    pool.sort((a, b) => ((a['price_pkr'] as int) - (product['price_pkr'] as int))
        .abs()
        .compareTo(((b['price_pkr'] as int) - (product['price_pkr'] as int)).abs()));
    return pool.first;
  }

  static int shippingFee(Map policy, String city, int subtotal) {
    if (subtotal >= (policy['free_shipping_threshold_pkr'] as int)) return 0;
    final fees = policy['shipping_fees'] as Map;
    return (fees[city] ?? fees['default']) as int;
  }

  /// cod_yes | cod_no_product | cod_no_city | cod_over_limit
  static String codCheck(Map policy, String city, List<Line> lines, int total) {
    if (lines.any((l) => !l.codEligible)) return 'cod_no_product';
    if (!(policy['cod_cities'] as List).contains(city)) return 'cod_no_city';
    if (total > (policy['cod_max_order_pkr'] as int)) return 'cod_over_limit';
    return 'cod_yes';
  }

  static String money(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
      b.write(s[i]);
    }
    return b.toString();
  }

  static String _iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Reply answer(String rawText, AssistantContext ctx) {
    final text = sanitize(rawText);
    final lang = detectLanguage(text);
    final store = ctx.storeName;
    final linkMeta = <String, dynamic>{'checkout_link': true, 'link_label': copy['replies'][lang]['link_label']};

    final intents = detectIntents(text);
    if (intents.contains('opt_out')) return Reply(t(lang, 'opt_out', {'store': store}), 'opt_out', 0.99, lang, action: 'opt_out');
    if (isInjection(text)) return Reply(t(lang, 'injection'), 'injection_blocked', 0.95, lang);
    if (intents.isEmpty) return Reply(t(lang, 'unknown', {'store': store}), 'unknown', 0.2, lang, action: 'handoff');

    final intent = intents.first;
    final conf = intents.length == 1 ? 0.92 : 0.85;
    final city = detectCity(text) ?? ctx.city;
    final cityl = cityLabel(city, lang);
    final today = ctx.nowLocal;
    var product = mentionedProduct(text, ctx.catalog);
    if (product == null && ctx.lines.isNotEmpty) {
      product = ctx.catalog.where((p) => p['id'] == ctx.lines.first.productId).firstOrNull;
    }

    switch (intent) {
      case 'human':
        return Reply(t(lang, 'human', {'store': store}), 'human', 0.95, lang, action: 'handoff');
      case 'discount':
        final ceiling = ctx.settings['discount_enabled'] == true ? (ctx.settings['discount_ceiling_pct'] as num).toInt() : 0;
        if (ctx.existingDiscount != null) {
          final (code, pct) = ctx.existingDiscount!;
          return Reply(t(lang, 'discount_existing', {'code': code, 'pct': pct}), 'discount', conf, lang, meta: linkMeta);
        }
        if (ceiling <= 0 || ctx.lines.isEmpty) return Reply(t(lang, 'discount_none'), 'discount', conf, lang);
        final req = detectPercent(text);
        final parts = <String>[];
        if (req != null && req > ceiling) parts.add(t(lang, 'discount_capped', {'req': req, 'pct': ceiling}));
        final pct = (req != null && req > 0) ? (req < ceiling ? req : ceiling) : ceiling;
        parts.add(t(lang, 'discount_issued', {'pct': pct, 'code': ctx.candidateCode}));
        return Reply(parts.join(' '), 'discount', conf, lang,
            action: 'issue_discount', meta: {...linkMeta, 'discount_code': ctx.candidateCode, 'discount_pct': pct});
      case 'cod':
        final ship = shippingFee(ctx.policy, city, ctx.subtotalPkr);
        final key = codCheck(ctx.policy, city, ctx.lines, ctx.subtotalPkr + ship);
        var items = ctx.lines.where((l) => !l.codEligible).map((l) => l.name).join(', ');
        if (items.isEmpty) items = product?['name'] as String? ?? '';
        final msg = t(lang, key, {
          'city': cityl,
          'max': money(ctx.policy['cod_max_order_pkr'] as int),
          'items': items,
          'total': money(ctx.subtotalPkr + ship),
        });
        return Reply(msg, 'cod', conf, lang, meta: {...linkMeta, 'cod_result': key});
      case 'shipping_fee':
        final fees = ctx.policy['shipping_fees'] as Map;
        final fee = (fees[city] ?? fees['default']) as int;
        final current = shippingFee(ctx.policy, city, ctx.subtotalPkr);
        final cur = current == 0 ? t(lang, 'shipping_free') : 'PKR ${money(current)}';
        return Reply(
            t(lang, 'shipping_fee', {
              'city': cityl,
              'fee': money(fee),
              'threshold': money(ctx.policy['free_shipping_threshold_pkr'] as int),
              'subtotal': money(ctx.subtotalPkr),
              'current': cur,
            }),
            'shipping_fee',
            conf,
            lang,
            meta: linkMeta);
      case 'delivery':
        final (start, end, lo, hi, known) = deliveryWindow(ctx.policy, city, today);
        final target = detectTargetDay(text, today);
        final parts = <String>[];
        if (target != null) parts.add(t(lang, 'delivery_no_guarantee', {'target': weekdayLong(target, lang)}));
        if (!known) parts.add(t(lang, 'delivery_default_city', {'city': cityl}));
        parts.add(t(lang, 'delivery_window', {'city': cityl, 'start': fmtDate(start, lang), 'end': fmtDate(end, lang), 'min': lo, 'max': hi}));
        if (target != null) {
          final tn = weekdayLong(target, lang);
          if (!end.isAfter(target)) {
            parts.add(t(lang, 'delivery_before', {'target': tn}));
          } else if (!start.isAfter(target)) {
            parts.add(t(lang, 'delivery_possible', {'target': tn}));
          } else {
            parts.add(t(lang, 'delivery_after', {'target': tn}));
          }
        }
        return Reply(parts.join(' '), 'delivery', conf, lang,
            meta: {...linkMeta, 'window_start': _iso(start), 'window_end': _iso(end), 'guaranteed': false});
      case 'returns':
        return Reply(t(lang, 'returns', {'exchange': ctx.policy['exchange_policy'], 'returns': ctx.policy['returns_policy']}), 'returns', conf,
            lang);
      case 'size':
      case 'stock':
        if (product == null) return Reply(t(lang, 'unknown', {'store': store}), 'unknown', 0.3, lang, action: 'handoff');
        final sizes = inStockSizes(product);
        final size = detectSize(text);
        final pname = product['name'];
        if (sizes.isEmpty) {
          final alt = alternativeFor(product, ctx.catalog);
          if (alt != null) {
            return Reply(t(lang, 'stock_out_all', {'product': pname, 'alt': alt['name'], 'alt_price': money(alt['price_pkr'] as int)}), 'stock',
                conf, lang,
                meta: {'alternative_product_id': alt['id']});
          }
          return Reply(t(lang, 'stock_out_no_alt', {'product': pname}), 'stock', conf, lang);
        }
        final sizeList = sizes.join(', ');
        if (intent == 'size') {
          var msg = t(lang, 'size_info', {'product': pname, 'fit': product['fit_notes'], 'sizes': sizeList});
          if (size != null) msg += ' ${t(lang, sizes.contains(size) ? 'size_requested_ok' : 'size_requested_out', {'size': size})}';
          return Reply(msg, 'size', conf, lang, meta: linkMeta);
        }
        final allSizes = [for (final v in (product['variants'] as List)) v['size']];
        if (size != null && allSizes.contains(size)) {
          if (sizes.contains(size)) return Reply(t(lang, 'stock_ok', {'product': pname, 'size': size}), 'stock', conf, lang, meta: linkMeta);
          return Reply(t(lang, 'stock_out_size', {'product': pname, 'size': size, 'sizes': sizeList}), 'stock', conf, lang);
        }
        return Reply(t(lang, 'stock_sizes', {'product': pname, 'sizes': sizeList}), 'stock', conf, lang, meta: linkMeta);
      case 'checkout_link':
        return Reply(t(lang, 'checkout_link'), 'checkout_link', conf, lang, meta: linkMeta);
      case 'thanks':
        return Reply(t(lang, 'thanks'), 'thanks', conf, lang);
    }
    return Reply(t(lang, 'greeting', {'first_name': ctx.firstName}), 'greeting', conf, lang);
  }
}
