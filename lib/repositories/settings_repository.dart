import 'dart:convert';

import 'dart:io' show Platform;

import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_version.dart' show AppVersion, UpdateChannel;
import '../widgets/voxel/voxel_renderer.dart' show LodQuality;

/// ════════════════════════════════════════════════════════════════════════
/// 全局设置仓库（R10/R11）
/// ════════════════════════════════════════════════════════════════════════
///
/// 所有用户操作的**唯一持久化入口**（收口 shared_preferences，禁止散落
/// 直接调用 SP）。冷启动时由 main() 读取并恢复（R10），运行中由
/// [SettingsSync] 监听各 provider 写回（R11）。
///
/// 持久化清单（R10 八项 + 扩展）：
///  - 音量：musicVolume / soundscapeVolume / musicMuted / soundscapeMuted
///  - 白噪音：whiteNoiseEnabled / whiteNoiseVolume
///  - 当前场景：currentSceneId
///  - 播放模式：playMode
///  - 主题：themeMode / themeSkin
///  - EQ：eqEnabled / eqPresetId / eqGains
///  - 均衡模式：balanceMode
///  - 上次曲目：lastTrackUri / lastTrackTitle / lastTrackArtist / lastPositionMs
class SettingsRepository {
  SettingsRepository(this._prefs);

  final SharedPreferences _prefs;

  static const String kMusicVolume = 'settings.musicVolume';
  static const String kSoundscapeVolume = 'settings.soundscapeVolume';
  static const String kMasterVolume = 'settings.masterVolume';
  static const String kSfxVolume = 'settings.sfxVolume';
  static const String kMusicSpeed = 'settings.musicSpeed';
  static const String kMusicMuted = 'settings.musicMuted';
  static const String kSoundscapeMuted = 'settings.soundscapeMuted';
  static const String kWhiteNoiseEnabled = 'settings.whiteNoiseEnabled';
  static const String kWhiteNoiseVolume = 'settings.whiteNoiseVolume';
  static const String kWhiteNoiseFollowsScene =
      'settings.whiteNoiseFollowsScene';
  static const String kWorldSfxVolume = 'settings.worldSfxVolume';
  static const String kUiCueVolume = 'settings.uiCueVolume';
  static const String kCurrentSceneId = 'settings.currentSceneId';
  static const String kPlayMode = 'settings.playMode';
  static const String kThemeMode = 'settings.themeMode';
  static const String kThemeSkin = 'settings.themeSkin';
  static const String kEqEnabled = 'settings.eqEnabled';
  static const String kEqPresetId = 'settings.eqPresetId';
  static const String kEqGains = 'settings.eqGains';
  static const String kBalanceMode = 'settings.balanceMode';
  static const String kPerformanceMode = 'settings.performanceMode';
  static const String kFpsLimit = 'settings.fpsLimit';
  static const String kViewDistanceChunks = 'settings.voxel.viewDistanceChunks';
  static const String kGraphicsQuality = 'settings.voxel.graphicsQuality';
  static const String kLodStartChunks = 'settings.voxel.lodStartChunks';
  static const String kLodStepChunks = 'settings.voxel.lodStepChunks';
  static const String kLodQuality = 'settings.voxel.lodQuality';
  static const String kLodFrustumCull = 'settings.voxel.lodFrustumCull';
  static const String kFaceCull = 'settings.voxel.faceCull';
  static const String kOcclusionCull = 'settings.voxel.occlusionCull';
  static const String kBackFaceCull = 'settings.voxel.backFaceCull';
  static const String kFrustumCull = 'settings.voxel.frustumCull';
  static const String kUnderwaterFilter = 'settings.voxel.underwaterFilter';
  static const String kWaterFlow = 'settings.voxel.waterFlow';
  static const String kFlashlight = 'settings.voxel.flashlight';
  static const String kLodEnabled = 'settings.voxel.lodEnabled';
  static const String kLodStepBlocks = 'settings.voxel.lodStepBlocks';
  static const String kLodSampleBase = 'settings.voxel.lodSampleBase';
  static const String kLodMaxChunks = 'settings.voxel.lodMaxChunks';
  static const String kShadowRender = 'settings.voxel.shadowRender';
  static const String kAoEnabled = 'settings.voxel.aoEnabled';
  static const String kOutlineEnabled = 'settings.voxel.outlineEnabled';
  static const String kBoundaryFog = 'settings.voxel.boundaryFog';
  static const String kRenderPrecisionScale = 'settings.voxel.renderPrecisionScale';
  static const String kRenderPrecision = 'settings.voxel.renderPrecision';
  static const String kPicturePreset = 'settings.picturePreset';
  static const String kOobeDone = 'settings.oobeDone';
  /// F4：最近一次完成 OOBE 的构建号（升级检测用——版本升级后弹询问是否重走）。
  static const String kOobeLastBuild = 'settings.oobeLastBuild';
  /// 2026-08-17 渠道化：当前更新渠道（beta 稳定 默认 / alpha 尝鲜）。
  static const String kUpdateChannel = 'settings.updateChannel';
  /// 渠道切换待重启标记：切换渠道后置 true，重启后 App 进入 OOBE·升级阶段。
  static const String kChannelSwitchPending = 'settings.channelSwitchPending';
  static const String kEngineBackend = 'settings.engineBackend';
  static const String kNoiseOverride = 'settings.effects.noise';
  static const String kGlassBlurOverride = 'settings.effects.glassBlur';
  static const String kBgAnimationOverride = 'settings.effects.bgAnimation';
  static const String kLiquidGlassOverride = 'settings.effects.liquidGlass';
  static const String kUiDensity = 'settings.uiDensity';
  static const String kUiScale = 'settings.uiScale';
  static const String kMusicEngine = 'settings.musicEngine';
  static const String kLastTrackUri = 'settings.lastTrackUri';
  static const String kLastTrackTitle = 'settings.lastTrackTitle';
  static const String kLastTrackArtist = 'settings.lastTrackArtist';
  static const String kLastPositionMs = 'settings.lastPositionMs';
  static const String kLogUploadEnabled = 'settings.logUploadEnabled';
  static const String kLogUploadEndpoint = 'settings.logUploadEndpoint';

  // ── 音量 ─────────────────────────────────────────
  double get musicVolume => _prefs.getDouble(kMusicVolume) ?? 0.7;
  Future<void> setMusicVolume(double v) => _prefs.setDouble(kMusicVolume, v);

  /// 倍速（R26skel：播放体验优化，默认 1.0 = 原速）。
  double get musicSpeed => _prefs.getDouble(kMusicSpeed) ?? 1.0;
  Future<void> setMusicSpeed(double v) =>
      _prefs.setDouble(kMusicSpeed, v.clamp(0.25, 4.0));

  double get soundscapeVolume => _prefs.getDouble(kSoundscapeVolume) ?? 0.12;
  Future<void> setSoundscapeVolume(double v) =>
      _prefs.setDouble(kSoundscapeVolume, v);

  /// 主音量（Master，R23i：全局整体音量，默认 1.0 = 100%）。
  double get masterVolume => _prefs.getDouble(kMasterVolume) ?? 1.0;
  Future<void> setMasterVolume(double v) =>
      _prefs.setDouble(kMasterVolume, v);

  /// 音效（SFX）通道音量（R23i：默认 0.5）。
  double get sfxVolume => _prefs.getDouble(kSfxVolume) ?? 0.5;
  Future<void> setSfxVolume(double v) =>
      _prefs.setDouble(kSfxVolume, v);

  bool get musicMuted => _prefs.getBool(kMusicMuted) ?? false;
  Future<void> setMusicMuted(bool v) => _prefs.setBool(kMusicMuted, v);

  bool get soundscapeMuted => _prefs.getBool(kSoundscapeMuted) ?? false;
  Future<void> setSoundscapeMuted(bool v) =>
      _prefs.setBool(kSoundscapeMuted, v);

  // ── 白噪音 ───────────────────────────────────────
  /// 默认关闭（2026-09-04 用户要求默认不播白噪；老用户已开启的不受影响）。
  bool get whiteNoiseEnabled => _prefs.getBool(kWhiteNoiseEnabled) ?? false;
  Future<void> setWhiteNoiseEnabled(bool v) =>
      _prefs.setBool(kWhiteNoiseEnabled, v);

  double get whiteNoiseVolume => _prefs.getDouble(kWhiteNoiseVolume) ?? 0.15;
  Future<void> setWhiteNoiseVolume(double v) =>
      _prefs.setDouble(kWhiteNoiseVolume, v);

  /// #167：白噪音是否跟随当前场景（默认 true = 跟随场景）。
  bool get whiteNoiseFollowsScene =>
      _prefs.getBool(kWhiteNoiseFollowsScene) ?? true;
  Future<void> setWhiteNoiseFollowsScene(bool v) =>
      _prefs.setBool(kWhiteNoiseFollowsScene, v);

  // ── 世界空间音效 / 提示音（#170）────────────────────
  /// 世界空间音效通道音量（默认 0.6）。
  double get worldSfxVolume => _prefs.getDouble(kWorldSfxVolume) ?? 0.6;
  Future<void> setWorldSfxVolume(double v) =>
      _prefs.setDouble(kWorldSfxVolume, v);

  /// 提示音通道音量（默认 0.5）。
  double get uiCueVolume => _prefs.getDouble(kUiCueVolume) ?? 0.5;
  Future<void> setUiCueVolume(double v) => _prefs.setDouble(kUiCueVolume, v);

  // ── 场景 / 播放 ──────────────────────────────────
  String? get currentSceneId => _prefs.getString(kCurrentSceneId);
  Future<void> setCurrentSceneId(String? id) =>
      id == null ? _prefs.remove(kCurrentSceneId) : _prefs.setString(kCurrentSceneId, id);

  String get playMode => _prefs.getString(kPlayMode) ?? 'order';
  Future<void> setPlayMode(String v) => _prefs.setString(kPlayMode, v);

  // ── 主题 ─────────────────────────────────────────
  String get themeMode => _prefs.getString(kThemeMode) ?? 'light';
  Future<void> setThemeMode(String v) => _prefs.setString(kThemeMode, v);

  String get themeSkin => _prefs.getString(kThemeSkin) ?? 'starlight';
  Future<void> setThemeSkin(String v) => _prefs.setString(kThemeSkin, v);

  // ── EQ ───────────────────────────────────────────
  bool get eqEnabled => _prefs.getBool(kEqEnabled) ?? false;
  Future<void> setEqEnabled(bool v) => _prefs.setBool(kEqEnabled, v);

  String get eqPresetId => _prefs.getString(kEqPresetId) ?? 'flat';
  Future<void> setEqPresetId(String v) => _prefs.setString(kEqPresetId, v);

  List<double> get eqGains {
    final String? raw = _prefs.getString(kEqGains);
    if (raw == null) return const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list.map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return const <double>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
    }
  }

  Future<void> setEqGains(List<double> gains) =>
      _prefs.setString(kEqGains, jsonEncode(gains));

  // ── 均衡模式 ─────────────────────────────────────
  String get balanceMode => _prefs.getString(kBalanceMode) ?? 'normal';
  Future<void> setBalanceMode(String v) => _prefs.setString(kBalanceMode, v);

  // ── 性能与质量体系（R21）─────────────────────────
  /// 性能档位（performance / quality；旧三档值自动迁移见 provider 侧）。
  String get performanceMode =>
      _prefs.getString(kPerformanceMode) ?? 'quality';
  Future<void> setPerformanceMode(String v) =>
      _prefs.setString(kPerformanceMode, v);

  /// 帧率限制（24/30/60/120 字符串）。
  String get fpsLimit => _prefs.getString(kFpsLimit) ?? '60';
  Future<void> setFpsLimit(String v) => _prefs.setString(kFpsLimit, v);

  // ── 体素区块 / LOD（R23m）─────────────────────────
  int get viewDistanceChunks => _prefs.getInt(kViewDistanceChunks) ?? 4;
  Future<void> setViewDistanceChunks(int v) =>
      _prefs.setInt(kViewDistanceChunks, v);

  /// R26m：3D 画质档索引（GraphicsQuality.values 序：0=性能 1=流畅 2=标准 3=高清；默认 1=流畅）。
  int get graphicsQuality => _prefs.getInt(kGraphicsQuality) ?? 1;
  Future<void> setGraphicsQuality(int v) =>
      _prefs.setInt(kGraphicsQuality, v);

  int get lodStartChunks => _prefs.getInt(kLodStartChunks) ?? 2;
  Future<void> setLodStartChunks(int v) =>
      _prefs.setInt(kLodStartChunks, v);

  int get lodStepChunks => _prefs.getInt(kLodStepChunks) ?? 1;
  Future<void> setLodStepChunks(int v) =>
      _prefs.setInt(kLodStepChunks, v);

  /// P6·R26r18：LOD 质量档位（int 索引持久化；R26r33 默认 off，见性能 provider）。
  LodQuality get lodQuality => LodQuality.values[
      (_prefs.getInt(kLodQuality) ?? LodQuality.off.index)
          .clamp(0, LodQuality.values.length - 1)];
  Future<void> setLodQuality(LodQuality v) =>
      _prefs.setInt(kLodQuality, v.index);

  /// P3·R26r18：LOD 通道区块级视锥剔除开关（默认开）。
  bool get lodFrustumCull => _prefs.getBool(kLodFrustumCull) ?? true;
  Future<void> setLodFrustumCull(bool v) =>
      _prefs.setBool(kLodFrustumCull, v);

  /// 图形渲染后端（auto / skiaOpengl / impellerD3D11 / impellerVulkan / software）。
  /// 默认：Windows = impellerD3D11（DX11，用户定版），其余 = auto（OpenGL/Impeller）。
  String get engineBackend =>
      _prefs.getString(kEngineBackend) ??
      (Platform.isWindows ? 'impellerD3D11' : 'auto');
  Future<void> setEngineBackend(String v) =>
      _prefs.setString(kEngineBackend, v);

  /// 特效开关覆盖（null = 跟随档位默认）。
  bool? get noiseOverride => _prefs.getBool(kNoiseOverride);
  Future<void> setNoiseOverride(bool? v) => v == null
      ? _prefs.remove(kNoiseOverride)
      : _prefs.setBool(kNoiseOverride, v);

  bool? get faceCull => _prefs.getBool(kFaceCull);
  Future<void> setFaceCull(bool? v) => v == null
      ? _prefs.remove(kFaceCull)
      : _prefs.setBool(kFaceCull, v);
  bool? get occlusionCull => _prefs.getBool(kOcclusionCull);
  Future<void> setOcclusionCull(bool? v) => v == null
      ? _prefs.remove(kOcclusionCull)
      : _prefs.setBool(kOcclusionCull, v);
  bool? get backFaceCull => _prefs.getBool(kBackFaceCull);
  Future<void> setBackFaceCull(bool? v) => v == null
      ? _prefs.remove(kBackFaceCull)
      : _prefs.setBool(kBackFaceCull, v);
  bool? get frustumCull => _prefs.getBool(kFrustumCull);
  Future<void> setFrustumCull(bool? v) => v == null
      ? _prefs.remove(kFrustumCull)
      : _prefs.setBool(kFrustumCull, v);
  bool? get underwaterFilter => _prefs.getBool(kUnderwaterFilter);
  Future<void> setUnderwaterFilter(bool? v) => v == null
      ? _prefs.remove(kUnderwaterFilter)
      : _prefs.setBool(kUnderwaterFilter, v);
  bool? get waterFlow => _prefs.getBool(kWaterFlow);
  Future<void> setWaterFlow(bool? v) => v == null
      ? _prefs.remove(kWaterFlow)
      : _prefs.setBool(kWaterFlow, v);
  bool? get flashlight => _prefs.getBool(kFlashlight);
  Future<void> setFlashlight(bool? v) => v == null
      ? _prefs.remove(kFlashlight)
      : _prefs.setBool(kFlashlight, v);
  bool? get lodEnabled => _prefs.getBool(kLodEnabled);
  Future<void> setLodEnabled(bool? v) => v == null
      ? _prefs.remove(kLodEnabled)
      : _prefs.setBool(kLodEnabled, v);
  int? get lodStepBlocks => _prefs.getInt(kLodStepBlocks);
  Future<void> setLodStepBlocks(int? v) => v == null
      ? _prefs.remove(kLodStepBlocks)
      : _prefs.setInt(kLodStepBlocks, v);
  int? get lodSampleBase => _prefs.getInt(kLodSampleBase);
  Future<void> setLodSampleBase(int? v) => v == null
      ? _prefs.remove(kLodSampleBase)
      : _prefs.setInt(kLodSampleBase, v);
  int? get lodMaxChunks => _prefs.getInt(kLodMaxChunks);
  Future<void> setLodMaxChunks(int? v) => v == null
      ? _prefs.remove(kLodMaxChunks)
      : _prefs.setInt(kLodMaxChunks, v);
  bool? get shadowRender => _prefs.getBool(kShadowRender);
  Future<void> setShadowRender(bool? v) => v == null
      ? _prefs.remove(kShadowRender)
      : _prefs.setBool(kShadowRender, v);
  bool? get aoEnabled => _prefs.getBool(kAoEnabled);
  Future<void> setAoEnabled(bool? v) => v == null
      ? _prefs.remove(kAoEnabled)
      : _prefs.setBool(kAoEnabled, v);
  bool? get outlineEnabled => _prefs.getBool(kOutlineEnabled);
  Future<void> setOutlineEnabled(bool? v) => v == null
      ? _prefs.remove(kOutlineEnabled)
      : _prefs.setBool(kOutlineEnabled, v);
  bool? get boundaryFog => _prefs.getBool(kBoundaryFog);
  Future<void> setBoundaryFog(bool? v) => v == null
      ? _prefs.remove(kBoundaryFog)
      : _prefs.setBool(kBoundaryFog, v);
  double? get renderPrecisionScale => _prefs.getDouble(kRenderPrecisionScale);
  Future<void> setRenderPrecisionScale(double? v) => v == null
      ? _prefs.remove(kRenderPrecisionScale)
      : _prefs.setDouble(kRenderPrecisionScale, v);
  double? get renderPrecision => _prefs.getDouble(kRenderPrecision);
  Future<void> setRenderPrecision(double? v) => v == null
      ? _prefs.remove(kRenderPrecision)
      : _prefs.setDouble(kRenderPrecision, v);
  String? get picturePreset => _prefs.getString(kPicturePreset);
  Future<void> setPicturePreset(String? v) => v == null
      ? _prefs.remove(kPicturePreset)
      : _prefs.setString(kPicturePreset, v);
  /// cl76_hotfix：是否存在升级前（cl75 之前）的历史设置——用于判断「老用户」。
  /// 有历史键 = 老用户升级（跳过 OOBE）；全新安装 = 新人（走 OOBE）。
  bool get hasLegacySettings => _prefs.containsKey(kGraphicsQuality);

  bool? get oobeDone => _prefs.getBool(kOobeDone);
  Future<void> setOobeDone(bool? v) => v == null
      ? _prefs.remove(kOobeDone)
      : _prefs.setBool(kOobeDone, v);

  /// F4：最近完成 OOBE 的构建号（int 存 string）。
  int? get oobeLastBuild => _prefs.getInt(kOobeLastBuild);
  Future<void> setOobeLastBuild(int? v) => v == null
      ? _prefs.remove(kOobeLastBuild)
      : _prefs.setInt(kOobeLastBuild, v);

  /// 当前更新渠道（默认跟随编译渠道；2026-08-17 渠道化，2026-08-17 晚修正：
  /// 原硬编码回落 beta，导致 alpha 编译包 OTA 也只查 beta → 收不到 alpha。
  /// 改回「未手动切换时跟随 [AppVersion.channel]」，alpha 包自动查 alpha）。
  UpdateChannel get updateChannel {
    final String? saved = _prefs.getString(kUpdateChannel);
    if (saved == null || saved.isEmpty) return AppVersion.channel;
    return UpdateChannel.fromTag(saved);
  }
  Future<void> setUpdateChannel(UpdateChannel c) =>
      _prefs.setString(kUpdateChannel, c.tag);

  /// 渠道切换待重启标记（重启后进入 OOBE·升级阶段）。
  bool get channelSwitchPending => _prefs.getBool(kChannelSwitchPending) ?? false;
  Future<void> setChannelSwitchPending(bool v) =>
      _prefs.setBool(kChannelSwitchPending, v);

  double? get glassBlurOverride => _prefs.getDouble(kGlassBlurOverride);
  Future<void> setGlassBlurOverride(double? v) => v == null
      ? _prefs.remove(kGlassBlurOverride)
      : _prefs.setDouble(kGlassBlurOverride, v);

  bool? get bgAnimationOverride => _prefs.getBool(kBgAnimationOverride);
  Future<void> setBgAnimationOverride(bool? v) => v == null
      ? _prefs.remove(kBgAnimationOverride)
      : _prefs.setBool(kBgAnimationOverride, v);

  bool? get liquidGlassOverride => _prefs.getBool(kLiquidGlassOverride);
  Future<void> setLiquidGlassOverride(bool? v) => v == null
      ? _prefs.remove(kLiquidGlassOverride)
      : _prefs.setBool(kLiquidGlassOverride, v);

  /// 界面密度（compact / standard）。
  String get uiDensity => _prefs.getString(kUiDensity) ?? 'standard';
  Future<void> setUiDensity(String v) => _prefs.setString(kUiDensity, v);

  /// 全局 UI 大小（0.8~1.2；缺省 1.0）。
  double get uiScale => _prefs.getDouble(kUiScale) ?? 1.0;
  Future<void> setUiScale(double v) =>
      _prefs.setDouble(kUiScale, v.clamp(0.8, 1.2));

  /// 播放引擎（justAudio / mediaKit，S2）。
  /// 未显式设置过（空串）时，由 [musicEngineProvider] 按平台给默认值
  /// （Android 默认 media_kit 以规避 ExoPlayer 切歌崩溃，其余平台 just_audio）。
  String get musicEngine => _prefs.getString(kMusicEngine) ?? '';
  Future<void> setMusicEngine(String v) => _prefs.setString(kMusicEngine, v);

  // ── 上次曲目 ─────────────────────────────────────
  String? get lastTrackUri => _prefs.getString(kLastTrackUri);
  String? get lastTrackTitle => _prefs.getString(kLastTrackTitle);
  String? get lastTrackArtist => _prefs.getString(kLastTrackArtist);
  int get lastPositionMs => _prefs.getInt(kLastPositionMs) ?? 0;
  Future<void> setLastTrack({
    required String uri,
    required String title,
    String? artist,
    int positionMs = 0,
  }) async {
    await _prefs.setString(kLastTrackUri, uri);
    await _prefs.setString(kLastTrackTitle, title);
    if (artist != null) await _prefs.setString(kLastTrackArtist, artist);
    await _prefs.setInt(kLastPositionMs, positionMs);
  }

  // ── 日志上报（云端日志，默认关闭）─────────────────
  bool get logUploadEnabled => _prefs.getBool(kLogUploadEnabled) ?? false;
  Future<void> setLogUploadEnabled(bool v) =>
      _prefs.setBool(kLogUploadEnabled, v);

  String get logUploadEndpoint => _prefs.getString(kLogUploadEndpoint) ?? '';
  Future<void> setLogUploadEndpoint(String v) =>
      _prefs.setString(kLogUploadEndpoint, v);

  static const String kLogDebugEnabled = 'settings.logDebugEnabled';
  bool get logDebugEnabled => _prefs.getBool(kLogDebugEnabled) ?? true;
  Future<void> setLogDebugEnabled(bool v) =>
      _prefs.setBool(kLogDebugEnabled, v);

  // ── 第三方大模型（地址 / 模型名不敏感；API Key 走 SecureBox）──
  static const String kLlmBaseUrl = 'settings.llmBaseUrl';
  static const String kLlmModel = 'settings.llmModel';

  String get llmBaseUrl =>
      _prefs.getString(kLlmBaseUrl) ?? 'https://api.openai.com/v1';
  Future<void> setLlmBaseUrl(String v) => _prefs.setString(kLlmBaseUrl, v);

  String get llmModel => _prefs.getString(kLlmModel) ?? '';
  Future<void> setLlmModel(String v) => _prefs.setString(kLlmModel, v);

  // ── OOBE 选择 / 询问（cl75：初始化「选择·询问」即时落库）──
  static const String kAudioQuality = 'settings.audioQuality';
  static const String kAnalyticsConsent = 'settings.analyticsConsent';
  static const String kListenSources = 'settings.listenSources'; // 多选逗号拼接

  /// 音频质量偏好（0=高品 · 1=标准 · 2=省流；默认 1=标准）。
  /// 对应网易云 `level`（standard/higher/exhigh/lossless），源层可据此选档。
  int get audioQuality => _prefs.getInt(kAudioQuality) ?? 1;
  Future<void> setAudioQuality(int v) => _prefs.setInt(kAudioQuality, v);

  /// 是否允许匿名体验改进（默认 false = 不发送任何统计）。
  bool get analyticsConsent => _prefs.getBool(kAnalyticsConsent) ?? false;
  Future<void> setAnalyticsConsent(bool v) =>
      _prefs.setBool(kAnalyticsConsent, v);

  /// 主要聆听场景（多选，逗号拼接；空串 = 未选）。
  String get listenSources => _prefs.getString(kListenSources) ?? '';
  Future<void> setListenSources(String v) => _prefs.setString(kListenSources, v);

  // ── ClassIsland 联动（方案 docs/方案_ClassIsland联动.md §8，v1.1 可选鉴权）──
  static const String kNowPlayingToken = 'settings.nowPlayingToken';

  /// 联动鉴权 token（空串 = 关闭鉴权，v1 冻结行为；非空则服务端需
  /// `?token=` 或 `Authorization: Bearer`，且 `/control` 放行异机）。
  String get nowPlayingToken => _prefs.getString(kNowPlayingToken) ?? '';
  Future<void> setNowPlayingToken(String v) =>
      _prefs.setString(kNowPlayingToken, v);
}
