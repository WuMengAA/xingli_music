package com.stelarith.xingli_music;

import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.Manifest;

import androidx.annotation.NonNull;
import androidx.core.content.FileProvider;

import java.io.File;

import com.ryanheise.audioservice.AudioServiceActivity;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/**
 * 星璃音乐 · 主 Activity
 *
 * 继承 audio_service 的 AudioServiceActivity（后台播放/锁屏控件宿主），
 * 并注册自写 MethodChannel：
 *  - com.stelarith.xingli_music/sensors（传感器）：
 *      lightLux()   ：TYPE_LIGHT 环境光（lux），替代 light 插件（其 minSdk 21 挡 4.4）
 *      heartRate()  ：TYPE_HEART_RATE 心率（需 BODY_SENSORS 权限；多数设备无此传感器）
 *  - com.stelarith.xingli_music/webview_login（内嵌网页登录，网易云/B站共用）：
 *      startNeteaseLogin()  ：拉起 [CookieWebViewActivity]（netease 类型），
 *                            登录成功后返回完整 cookie 串（含 httpOnly
 *                            MUSIC_U）；取消返回 null
 *      startBilibiliLogin() ：同上（bilibili 类型），返回含 httpOnly SESSDATA
 *                            的完整 cookie 串
 *
 * minSdk 19 即可编译运行（SensorManager API 自 API 8 就有）。
 */
public class MainActivity extends AudioServiceActivity {
    private static final String CHANNEL = "com.stelarith.xingli_music/sensors";
    private static final String WEBVIEW_CHANNEL = "com.stelarith.xingli_music/webview_login";
    private static final String OTA_CHANNEL = "com.stelarith.xingli_music/ota_install";
    private static final String OTA_AUTHORITY = "com.stelarith.xingli_music.fileprovider";
    private static final String OPEN_URL_CHANNEL = "com.stelarith.xingli_music/open_url";
    private static final String APP_INFO_CHANNEL = "com.stelarith.xingli_music/app_info";
    private static final int REQ_WEBVIEW_LOGIN = 0x101;

    private SensorManager sensorManager;
    private MethodChannel.Result pendingWebViewResult;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        sensorManager = (SensorManager) getSystemService(Context.SENSOR_SERVICE);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "lightLux": {
                            readSensor(Sensor.TYPE_LIGHT, result, "lux");
                            break;
                        }
                        case "heartRate": {
                            readSensor(Sensor.TYPE_HEART_RATE, result, "bpm");
                            break;
                        }
                        default:
                            result.notImplemented();
                    }
                });

        // 内嵌网页登录（网易云 / B站共用）：拉起原生 WebView 登录页，等待 cookie 回传
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), WEBVIEW_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("startNeteaseLogin".equals(call.method)) {
                        launchWebViewLogin(result, CookieWebViewActivity.TYPE_NETEASE);
                    } else if ("startBilibiliLogin".equals(call.method)) {
                        launchWebViewLogin(result, CookieWebViewActivity.TYPE_BILIBILI);
                    } else {
                        result.notImplemented();
                    }
                });

        // OTA 安装：Dart 侧下载并校验完 APK 后，调系统安装器完成安装。
        // 必须用 FileProvider 生成 content:// URI（Android 7+ 禁止 file:// 暴露给
        // 外部应用），并带 FLAG_GRANT_READ_URI_PERMISSION（配合
        // REQUEST_INSTALL_PACKAGES 权限，Android 8+ 才能装未知来源 APK）。
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), OTA_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("install".equals(call.method)) {
                        installApk(call.arguments(), result);
                    } else {
                        result.notImplemented();
                    }
                });

        // 外部链接：Dart 侧拉起系统浏览器打开 http(s) 链接（OOBE 协议链接用）。
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), OPEN_URL_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("open".equals(call.method)) {
                        openUrl(call.arguments(), result);
                    } else {
                        result.notImplemented();
                    }
                });

        // cl76_hotfix5：应用自身安装包路径——OTA 增量补丁的「基线留存」用
        // （首次复制 sourceDir 到私有 files，补丁合成时 基线+patch = 新包）。
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), APP_INFO_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("sourceDir".equals(call.method)) {
                        try {
                            result.success(getApplicationInfo().sourceDir);
                        } catch (Exception e) {
                            result.error("no_source_dir", e.getMessage(), null);
                        }
                    } else {
                        result.notImplemented();
                    }
                });
    }

    /** 调系统安装器安装已下载的 APK（[args] 为 APK 绝对路径）。 */
    private void installApk(Object args, MethodChannel.Result result) {
        if (!(args instanceof String)) {
            result.error("bad_args", "apkPath 必须是字符串", null);
            return;
        }
        final File apk = new File((String) args);
        if (!apk.exists()) {
            result.error("no_file", "安装包不存在: " + args, null);
            return;
        }
        try {
            final Uri uri = FileProvider.getUriForFile(this, OTA_AUTHORITY, apk);
            final Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, "application/vnd.android.package-archive");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            result.success(true);
        } catch (Exception e) {
            // cl76_hotfix：附上文件存在性/大小，便于定位「未找到安装包」类问题
            // （FileProvider 未命中白名单 root 时抛 IllegalArgumentException）。
            result.error("install_failed",
                    "安装失败: " + e.getMessage()
                            + " (file=" + args
                            + ", exists=" + apk.exists()
                            + ", len=" + apk.length() + ")",
                    null);
        }
    }

    /** 调系统浏览器打开外部链接（[args] 为完整 URL 字符串）。 */
    private void openUrl(Object args, MethodChannel.Result result) {
        if (!(args instanceof String)) {
            result.error("bad_args", "url 必须是字符串", null);
            return;
        }
        try {
            final Uri uri = Uri.parse((String) args);
            final Intent intent = new Intent(Intent.ACTION_VIEW, uri);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            result.success(true);
        } catch (Exception e) {
            result.error("open_failed", e.getMessage(), null);
        }
    }

    /** 拉起内嵌登录页：先收尾上一次未消费的结果（避免悬挂），再启动对应类型。 */
    private void launchWebViewLogin(MethodChannel.Result result, String loginType) {
        if (pendingWebViewResult != null) {
            pendingWebViewResult.success(null);
        }
        pendingWebViewResult = result;
        final Intent intent = new Intent(this, CookieWebViewActivity.class);
        intent.putExtra(CookieWebViewActivity.EXTRA_LOGIN_TYPE, loginType);
        startActivityForResult(intent, REQ_WEBVIEW_LOGIN);
    }

    @SuppressWarnings("deprecation")
    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQ_WEBVIEW_LOGIN) return;
        MethodChannel.Result r = pendingWebViewResult;
        pendingWebViewResult = null;
        if (r == null) return;
        if (resultCode == RESULT_OK && data != null) {
            r.success(data.getStringExtra(CookieWebViewActivity.EXTRA_COOKIE));
        } else {
            r.success(null); // 用户取消 / 未取到
        }
    }

    /** 单次读取传感器值（异步回调；传感器缺失/无权限 → null）。 */
    private void readSensor(int sensorType, MethodChannel.Result result, String tag) {
        Sensor sensor = sensorManager == null ? null : sensorManager.getDefaultSensor(sensorType);
        if (sensor == null) {
            result.success(null);
            return;
        }
        sensorManager.registerListener(new SensorEventListener() {
            @Override
            public void onSensorChanged(SensorEvent event) {
                if (event.values != null && event.values.length > 0) {
                    result.success((double) event.values[0]);
                } else {
                    result.success(null);
                }
                // 读一次即注销，避免常驻耗电
                sensorManager.unregisterListener(this);
            }

            @Override
            public void onAccuracyChanged(Sensor sensor, int accuracy) {
                // 忽略
            }
        }, sensor, SensorManager.SENSOR_DELAY_UI);
    }
}
