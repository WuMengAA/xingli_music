/// OTA 安装入口（cl74 / cl77）：按平台走对应安装链路。
///
/// - Android：调用原生安装器安装已下载并校验通过的 APK。
///   为什么走原生 MethodChannel 而非 Dart 直接起 Intent：
///   1. Android 7+ 禁止 `file://` 暴露给外部应用（FileUriExposedException），
///      必须用 `FileProvider` 生成 `content://` URI；
///   2. Android 8+ 安装未知来源 APK 需 `REQUEST_INSTALL_PACKAGES` 权限；
///   3. Dart 侧构造 content URI + 调系统安装器最干净的做法是经原生
///      `FileProvider.getUriForFile` + `Intent.ACTION_VIEW`（见 MainActivity）。
///   通道名与权限 authority 必须和 AndroidManifest / MainActivity 完全一致。
///
/// - Windows 电脑版（cl77）：运行中的 exe 被独占锁定无法原地覆盖，采用
///   「staging 解压 + 延迟替换 bat」两段式：
///   1. 把 zip 解压到应用私有目录的 staging 子目录（archive 库，平铺）；
///   2. 在安装目录写 `xingli_ota_apply.bat`：等待 2s → xcopy 覆盖
///      （此时旧进程已退出，exe 解锁）→ 启动新 exe → 删除 bat；
///   3. 分离启动该 bat（不等待），立即 `exit(0)` 结束当前进程，
///      由 bat 接管替换与重启，用户无感完成自更新。
library;

import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../core/paths.dart';
import 'ota_service.dart';

/// 与原生约定一致的通道名 / authority。
const String kOtaInstallChannel = 'com.stelarith.xingli_music/ota_install';
const String kOtaFileProviderAuthority = 'com.stelarith.xingli_music.fileprovider';

/// OTA 安装入口：按平台分发安装链路。
class OtaInstall {
  OtaInstall._();

  static const MethodChannel _channel = MethodChannel(kOtaInstallChannel);

  /// 安装已下载并校验通过的更新包（[filePath] 由 [OtaService.downloadAndVerify]
  /// 返回）。Android → 系统安装器；Windows → 解压替换自启；其它平台抛
  /// [OtaException]（消息可直接展示）。
  static Future<void> install(String filePath) async {
    if (Platform.isWindows) {
      await installWindows(filePath);
      return;
    }
    if (!Platform.isAndroid) {
      throw OtaException('当前平台不支持应用内安装更新');
    }
    final File f = File(filePath);
    if (!f.existsSync()) {
      throw OtaException('安装包不存在：$filePath');
    }
    try {
      await _channel.invokeMethod<void>('install', filePath);
    } on PlatformException catch (e) {
      throw OtaException('安装失败：${e.message ?? e.code}');
    }
  }

  /// Windows 电脑版自更新（cl77）：解压 zip → bat 延迟替换 → 重启。
  ///
  /// zip 由发布脚本打包 `build\windows\x64\runner\Release\` 目录内容
  /// （exe + dll + data/ 等平铺、无顶层目录）。staging 目录带版本号，
  /// 覆盖已有 staging（防止残留旧版本文件）。
  static Future<void> installWindows(String zipPath) async {
    final File zip = File(zipPath);
    if (!zip.existsSync()) {
      throw OtaException('更新包不存在：$zipPath');
    }

    // ── 1) 解压到 staging ──
    final Directory appData = await appDataDir();
    final String tag = _tagFromZipName(p.basename(zipPath));
    final Directory staging = Directory(
      p.join(appData.path, 'xingli_ota_staging_$tag'),
    );
    await _extractZip(zip, staging);

    // ── 2) 定位安装目录（当前 exe 所在目录）与目标 exe ──
    final String installDir = p.dirname(Platform.resolvedExecutable);
    final String exeName = p.basename(Platform.resolvedExecutable);
    final File newExe = File(p.join(staging.path, exeName));
    if (!newExe.existsSync()) {
      throw OtaException('更新包缺少可执行文件：$exeName');
    }

    // ── 3) 写延迟替换 bat ──
    final String batPath = p.join(installDir, 'xingli_ota_apply.bat');
    final String script = _applyScript(staging.path, installDir, exeName);
    await File(batPath).writeAsString(script, flush: true);

    // ── 4) 分离启动 bat，然后退出当前进程 ──
    try {
      await Process.start(
        'cmd.exe',
        <String>['/c', batPath],
        mode: ProcessStartMode.detached,
      );
    } on ProcessException catch (e) {
      throw OtaException('启动更新脚本失败：${e.message}');
    }
    exit(0);
  }

  /// 从 zip 文件名 `ota_<tag>_xingli_music_windows_x64.zip` 提取 tag。
  static String _tagFromZipName(String name) {
    final String suffix = '_${otaWindowsAssetName()}';
    String base = p.basename(name);
    if (base.endsWith(suffix)) {
      base = base.substring(0, base.length - suffix.length);
    }
    base = p.basenameWithoutExtension(base);
    return base.startsWith('ota_') ? base.substring(4) : base;
  }

  /// 用 archive 库把 zip 平铺解压到 [staging]（先清空重建）。
  static Future<void> _extractZip(File zip, Directory staging) async {
    try {
      if (await staging.exists()) {
        await staging.delete(recursive: true);
      }
      await staging.create(recursive: true);
      final Archive archive =
          ZipDecoder().decodeBytes(await zip.readAsBytes());
      for (final ArchiveFile file in archive.files) {
        if (!file.isFile) continue;
        // 防路径穿越：拒绝绝对路径与 .. 段。
        final String rel = p.normalize(file.name);
        if (p.isAbsolute(rel) || rel == '..' || rel.startsWith('../')) {
          throw const OtaException('更新包含非法路径，已中止');
        }
        final File out = File(p.join(staging.path, rel));
        await out.parent.create(recursive: true);
        await out.writeAsBytes(file.content as List<int>, flush: true);
      }
    } on OtaException {
      rethrow;
    } on Exception catch (e) {
      throw OtaException('解压更新包失败：$e');
    }
  }

  /// 生成延迟替换 bat：等旧进程退出 → 覆盖 → 重启 → 自删。
  static String _applyScript(String staging, String installDir, String exe) {
    // 注意 echo 命令已处理；xcopy 失败重试目录锁。
    return [
      '@echo off',
      'rem xingli OTA apply (generated)',
      'timeout /t 2 /nobreak >nul',
      ':retry',
      'xcopy /y /e /q /i "$staging\\*" "$installDir\\" >nul 2>&1',
      'if errorlevel 1 (',
      '  timeout /t 1 /nobreak >nul',
      '  goto retry',
      ')',
      'start "" "$installDir\\$exe"',
      'del "%~f0"',
      '',
    ].join('\r\n');
  }
}