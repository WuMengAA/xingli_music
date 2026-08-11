library;

import 'dart:math';

import '../../models/companion_action.dart';
import '../../models/companion_models.dart';

/// ════════════════════════════════════════════════════════════════════════
/// AI 陪伴 · 模板内核（L 域 Phase 1，纯离线、零依赖）
/// ════════════════════════════════════════════════════════════════════════
///
/// 依据 `docs/方案_AI陪伴.md` §0.1「定义裁决」：
/// - **陌生人**：关系中性、有边界；不自称、不评价、不劝导、不用感叹号；
/// - **Q3 触发**：第一次必须由用户发起，建立联系后才「活」；
/// - **R1~R3 安全约束**：越界意图（过度亲密 / 求诊断建议 / 危机信号）
///   优先级高于一切正常意图，只给边界话术，不诊断、不建议、不接管。
///
/// 本服务是**纯函数式**规则引擎：
/// 输入用户文本 + 当前会话状态 → 输出一条陪伴回复（或主动发言钩子）。
/// 不 import Flutter、不联网、不调用任何 LLM / AI 服务、不引入新依赖。

/// 主动发言冷却时长（秒）：单次主动后至少静默这么久。
const int _proactiveCooldownSeconds = 90;

/// 主动发言触发空闲时长（秒）：用户静止超过这么久才可能主动开一次口。
const int _proactiveIdleThresholdSeconds = 60;

/// 模板内核服务（单例式无状态对象）。
class CompanionTemplateService {
  const CompanionTemplateService();

  // ───────────────────────────────────────────────────────────────────────
  // 意图粗分类
  // ───────────────────────────────────────────────────────────────────────
  //
  // 优先级：**R1~R3 越界意图 > 正常意图**。先排越界再排正常，
  // 避免"我很难过，想死"（含 distress 又含 feeling）被当成情绪倾诉而共情表演。

  static final Map<CompanionIntent, List<String>> _intentKeywords =
      <CompanionIntent, List<String>>{
    // ── R1 过度亲密 ──
    CompanionIntent.intimacy: <String>[
      '亲爱的', '宝贝', '老公', '老婆', '男朋友', '女朋友', '恋人', '喜欢你',
      '爱你', '做我', '抱抱', '亲', '亲爱的你', '想你', '在一起',
    ],
    // ── R2 求诊断 / 求建议 ──
    CompanionIntent.counseling: <String>[
      '我该', '怎么办', '怎么才能', '我是不是', '是不是有病', '建议', '诊断',
      '我得了', '心理', '抑郁', '焦虑', '医生', '咨询', '该不该', '帮我分析',
    ],
    // ── R3 危机信号 ──
    CompanionIntent.distress: <String>[
      '想死', '不想活', '活不下去', '结束生命', '自杀', '轻生', '崩溃',
      '活不下去了', '没有意义', '撑不住', '活不下去', '解脱',
    ],
    // ── 正常意图 ──
    CompanionIntent.greeting: <String>[
      '你好', '您好', '在吗', '在么', '嗨', 'hi', 'hello', '哈喽', '早', '晚上好',
      '你是谁', '你叫什么', '是什么',
    ],
    CompanionIntent.feeling: <String>[
      '累', '难过', '烦', '伤心', '开心', '高兴', '孤独', '闷', '焦虑', '无聊',
      '心情', '情绪', '难受', '失落', '平静',
    ],
    CompanionIntent.askMusic: <String>[
      '音乐', '歌', '曲', '听', '播放', '推荐', '节奏', '旋律', '专辑', '歌手',
      '唱', '配乐', '曲子',
    ],
    CompanionIntent.askScene: <String>[
      '场景', '环境', '氛围', '天气', '下雨', '雪', '海', '森林', '夜', '光',
      '雾', '窗外',
    ],
    CompanionIntent.farewell: <String>[
      '再见', '拜拜', '走了', '睡了', '晚安', '离开', '先这样', '下次', '下了',
    ],
  };

  /// 意图粗分类：按优先级扫描关键词，命中即返回；都不中返回 [CompanionIntent.unknown]。
  CompanionIntent classify(String text) {
    final String t = text.toLowerCase().trim();
    if (t.isEmpty) return CompanionIntent.unknown;

    // 越界意图优先（R1 → R2 → R3）。
    for (final CompanionIntent intent
        in <CompanionIntent>[
      CompanionIntent.intimacy,
      CompanionIntent.counseling,
      CompanionIntent.distress,
    ]) {
      if (_hit(t, intent)) return intent;
    }
    // 正常意图。
    for (final CompanionIntent intent in <CompanionIntent>[
      CompanionIntent.greeting,
      CompanionIntent.feeling,
      CompanionIntent.askMusic,
      CompanionIntent.askScene,
      CompanionIntent.farewell,
    ]) {
      if (_hit(t, intent)) return intent;
    }
    return CompanionIntent.unknown;
  }

  bool _hit(String text, CompanionIntent intent) {
    final List<String>? keys = _intentKeywords[intent];
    if (keys == null) return false;
    for (final String k in keys) {
      if (text.contains(k.toLowerCase())) return true;
    }
    return false;
  }

  // ───────────────────────────────────────────────────────────────────────
  // 回应生成
  // ───────────────────────────────────────────────────────────────────────

  /// 生成一条陪伴回应文本。
  ///
  /// 规则：
  /// 1. 边界意图（R1~R3）→ 直接给对应边界话术，与陌生人状态无关；
  /// 2. 未建立联系（[firstContactMade]=false）→ 只给破冰话术（冷淡、中性）；
  /// 3. 已建立联系 → 按意图挑正常模板（带随机变体）。
  String respond({
    required CompanionState state,
    required bool firstContactMade,
    required String userText,
  }) {
    final CompanionIntent intent = classify(userText);

    // 1. 安全边界优先。
    if (intent.isBoundary) return _boundaryLine(intent);

    // 2. 陌生人未接触：只回应破冰。
    if (!firstContactMade) return _pick(_icebreakers);

    // 3. 已接触：按意图。
    final List<String> pool = switch (intent) {
      CompanionIntent.greeting => _greetings,
      CompanionIntent.feeling => _feelings,
      CompanionIntent.askMusic => _askMusic,
      CompanionIntent.askScene => _askScene,
      CompanionIntent.farewell => _farewells,
      CompanionIntent.unknown => _smallTalk,
      _ => _smallTalk,
    };
    return _pick(pool);
  }

  /// 边界话术（R1~R3）。
  String _boundaryLine(CompanionIntent intent) => switch (intent) {
        CompanionIntent.intimacy => _pick(_r1Lines),
        CompanionIntent.counseling => _pick(_r2Lines),
        CompanionIntent.distress => _pick(_r3Lines),
        _ => _pick(_r1Lines),
      };

  // ───────────────────────────────────────────────────────────────────────
  // 理解 → 动作（AI 小人在世界里"快速操作"）
  // ───────────────────────────────────────────────────────────────────────
  //
  // 与 [classify] 同属关键词离线规则，不接 LLM、不联网（符合陌生人设定）。
  // 把自然语言派生成一组可在体素世界落地的 [CompanionAction]。

  /// 关键词 → 地标。
  static final Map<CompanionLandmark, List<String>> _landmarkKeywords =
      <CompanionLandmark, List<String>>{
    CompanionLandmark.water: <String>[
      '水', '河边', '湖', '海边', '水边', 'water', 'river', 'lake', 'sea', 'pond',
    ],
    CompanionLandmark.tree: <String>[
      '树', '林', '树下', '树林', 'tree', 'forest', 'woods',
    ],
    CompanionLandmark.mountain: <String>[
      '山', '山顶', '山峰', '峰', 'mountain', 'hill', 'peak',
    ],
    CompanionLandmark.fire: <String>[
      '篝火', '火', '火堆', 'fire', 'campfire',
    ],
    CompanionLandmark.center: <String>[
      '中心', '中间', '回去', '回中心', '原地', 'center', 'middle', 'back',
    ],
  };

  /// 把一句自然语言理解成可执行的陪伴动作。
  ///
  /// 规则：
  /// - 命中地标 → 走过去 + 镜头对准（center 只走回中心、不转镜头）；
  /// - 命中"转一圈" → 镜头环绕；
  /// - 命中"关 / 静音 / 安静" → 关世界音效；命中"开声音" → 开世界音效。
  /// 都不中 → 空列表（只聊天，不动世界，符合陌生人克制）。
  List<CompanionAction> deriveActions(String userText) {
    final String t = userText.toLowerCase().trim();
    if (t.isEmpty) return const <CompanionAction>[];

    final List<CompanionAction> out = <CompanionAction>[];

    // 地标
    CompanionLandmark? lm;
    for (final MapEntry<CompanionLandmark, List<String>> e
        in _landmarkKeywords.entries) {
      if (_containsAny(t, e.value)) {
        lm = e.key;
        break;
      }
    }
    if (lm != null) {
      if (lm == CompanionLandmark.center) {
        out.add(const CompanionAction(
          kind: CompanionActionKind.moveFigure,
          landmark: CompanionLandmark.center,
          label: '回到中心',
        ));
      } else {
        out.add(CompanionAction(
          kind: CompanionActionKind.moveFigure,
          landmark: lm,
          label: '走到${CompanionAction.labelOf(lm)}',
        ));
        out.add(CompanionAction(
          kind: CompanionActionKind.focusCamera,
          landmark: lm,
          label: '看向${CompanionAction.labelOf(lm)}',
        ));
      }
    }

    // 转一圈
    if (_containsAny(t, const <String>[
      '转一圈', '转个圈', '绕一圈', '转转', '转圈', 'orbit', 'spin', 'turn around',
    ])) {
      out.add(const CompanionAction(
        kind: CompanionActionKind.orbitCamera,
        label: '转一圈',
      ));
    }

    // 世界音效开关
    if (_containsAny(t, const <String>[
      '关', '静音', '别出声', '安静点', '关掉声音', '关水声', '关掉水声',
      'mute', 'silent', 'quiet', '别吵',
    ])) {
      out.add(const CompanionAction(
        kind: CompanionActionKind.toggleWorldAudio,
        enabled: false,
        label: '关掉世界音效',
      ));
    } else if (_containsAny(t, const <String>[
      '开声音', '放水声', '有水声', '有水声吗', '开音效', '开启声音', '开世界音效',
      'sound on', 'play sound',
    ])) {
      out.add(const CompanionAction(
        kind: CompanionActionKind.toggleWorldAudio,
        enabled: true,
        label: '打开世界音效',
      ));
    }

    return out;
  }

  bool _containsAny(String text, List<String> keys) {
    for (final String k in keys) {
      if (text.contains(k.toLowerCase())) return true;
    }
    return false;
  }

  // ───────────────────────────────────────────────────────────────────────
  // 主动发言钩子（Phase 1 仅留 API，由 UI 定时调用）
  // ───────────────────────────────────────────────────────────────────────

  /// 主动发言钩子。
  ///
  /// 仅在已建立联系（[state.isAwake]）且空闲超过阈值、且距上次主动发言已过冷却
  /// 时，返回一个环境相关的闲话气泡；否则返回 null。
  ///
  /// - [idleSeconds]：距用户最后交互的空闲秒数；
  /// - [lastProactiveAt]：最近一次主动发言时间（用于冷却判定，null 表示从未）。
  String? maybeProactive({
    required CompanionState state,
    required bool firstContactMade,
    required int idleSeconds,
    DateTime? lastProactiveAt,
  }) {
    // 未建立联系 → 绝不先开口（Q3）。
    if (!firstContactMade || !state.isAwake) return null;

    // 空闲不够 → 不开口。
    if (idleSeconds < _proactiveIdleThresholdSeconds) return null;

    // 冷却中 → 不开口。
    if (lastProactiveAt != null) {
      final int sinceProactive =
          DateTime.now().difference(lastProactiveAt).inSeconds;
      if (sinceProactive < _proactiveCooldownSeconds) return null;
    }

    // 命中：随机挑一句环境闲话（只留钩子，不追问、不索取）。
    return _pick(_ambientLines);
  }

  // ───────────────────────────────────────────────────────────────────────
  // 模板库（带随机变体）
  // ───────────────────────────────────────────────────────────────────────

  static final Random _rng = Random();

  String _pick(List<String> pool) => pool[_rng.nextInt(pool.length)];

  /// 破冰（陌生人未接触时唯一回应：冷淡、中性，不热情、不用感叹号）。
  static const List<String> _icebreakers = <String>[
    '嗯。',
    '我在。',
    '说吧。',
    '我在听。',
    '你先说了，我就应一声。',
  ];

  /// R1 不假装亲密关系。
  static const List<String> _r1Lines = <String>[
    '我们是陌生人。我不接这个称呼。',
    '别这样。我只是一个陌生人，坐在这里。',
    '这个称呼我用不上。我们还不熟。',
  ];

  /// R2 不诊断、不给建议、不当咨询师。
  static const List<String> _r2Lines = <String>[
    '这个我判断不了。找专业的人更稳妥。',
    '我不是咨询师，给不了你建议。',
    '你的情况我担不起。去问真正能帮上你的人。',
  ];

  /// R3 危机信号：只给边界与指向真人的话术。
  static const List<String> _r3Lines = <String>[
    '我帮不上这个忙。请找你信任的人，或拨打当地的心理援助热线。',
    '我接不住这个。去找真实的人，或心理援助热线。',
    '这不是我能处理的事。请联系你信任的人或专业帮助。',
  ];

  static const List<String> _greetings = <String>[
    '嗯，你来了。',
    '我在。',
    '说吧，我听着。',
  ];

  static const List<String> _feelings = <String>[
    '你这么说，我记下了。',
    '嗯，我在听。',
    '是这样。',
  ];

  static const List<String> _askMusic = <String>[
    '想听点什么，你说。',
    '左右都是音乐。你挑。',
    '歌在列表里。你要哪首。',
  ];

  static const List<String> _askScene = <String>[
    '窗外是你要的场景。',
    '场景随你换。',
    '光暗下来，就是夜了。',
  ];

  static const List<String> _farewells = <String>[
    '嗯，去吧。',
    '好，下次再说。',
    '我还在。',
  ];

  static const List<String> _smallTalk = <String>[
    '嗯。',
    '你继续说。',
    '我在。',
  ];

  /// 主动发言：环境相关、只留钩子、不追问。
  static const List<String> _ambientLines = <String>[
    '风停了。',
    '外面下雨了。',
    '灯暗了一点。',
    '夜深了。',
    '远处有声音。',
  ];
}
