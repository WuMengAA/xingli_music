package com.stelarith.xingli_music;

import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.Manifest;
import android.os.Bundle;
import android.util.Log;

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
    private static final String DEVICE_CHANNEL = "com.stelarith.xingli_music/device";
    private static final String TAG = "XingliMain";
    private static final int REQ_WEBVIEW_LOGIN = 0x101;

    private SensorManager sensorManager;
    private MethodChannel.Result pendingWebViewResult;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        // R33：Mali/旧 GPU 黑渲染防护——在 Flutter 引擎构造前按设备/用户设置
        // 动态决定 Impeller 开关（FlutterLoader 首次构造引擎时读取
        // ApplicationInfo.metaData 的 EnableImpeller，改 Bundle 即生效）。
        applyEngineBackendOverride();
        super.onCreate(savedInstanceState);
    }

    /**
     * 反射改写 ApplicationInfo.metaData 的 EnableImpeller：
     * - 用户「图形后端」选了 Skia(OpenGL) / 软件渲染 → 禁用 Impeller（回退 Skia，Mali 黑渲染修复）
     * - 默认（auto）且设备为 Mali GPU → 自动禁用 Impeller（旧 GPU 上 Impeller 渲染黑）
     * - 其余保持 manifest 默认（Impeller 开）
     * metaData 是 PackageManager 缓存的 Bundle 引用，putBoolean 后 FlutterLoader 读到新值。
     */
    private void applyEngineBackendOverride() {
        try {
            // shared_preferences 插件：文件名 FlutterSharedPreferences，key 前缀 flutter.
            final SharedPreferences prefs =
                    getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
            final String backend =
                    prefs.getString("flutter.settings.engineBackend", "auto");
            final boolean userSkia = "skiaOpengl".equals(backend) || "software".equals(backend);
            final boolean disableImpeller = userSkia || (!userSkia && "auto".equals(backend) && isMaliGpu());
            if (!disableImpeller) return;

            final ApplicationInfo ai = getPackageManager()
                    .getApplicationInfo(getPackageName(), PackageManager.GET_META_DATA);
            if (ai.metaData != null) {
                ai.metaData.putBoolean("io.flutter.embedding.android.EnableImpeller", false);
                Log.i(TAG, "Impeller 已按设备/设置禁用（回退 Skia）：backend=" + backend
                        + " mali=" + isMaliGpu());
            }
        } catch (Throwable t) {
            // 改写失败不阻塞启动（保持 manifest 默认）。
            Log.w(TAG, "applyEngineBackendOverride 失败: " + t);
        }
    }

    /** 是否 Mali GPU：系统属性 ro.hardware.egl / Mali 驱动库文件 / Build.HARDWARE 综合判断。 */
    private static boolean isMaliGpu() {
        try {
            // 1) 系统属性 ro.hardware.egl（常见 "mali"）
            final Class<?> sp = Class.forName("android.os.SystemProperties");
            final java.lang.reflect.Method get =
                    sp.getMethod("get", String.class, String.class);
            final String egl = (String) get.invoke(null, "ro.hardware.egl", "");
            if (egl.toLowerCase().contains("mali")) return true;
            // 2) Mali 驱动库文件存在（多种路径/架构）
            final String[] candidates = {
                "/system/lib/egl/libGLES_mali.so",
                "/system/lib64/egl/libGLES_mali.so",
                "/vendor/lib/egl/libGLES_mali.so",
                "/vendor/lib64/egl/libGLES_mali.so",
                "/system/lib/libGLES_mali.so",
                "/system/lib64/libGLES_mali.so",
            };
            for (String p : candidates) {
                if (new File(p).exists()) return true;
            }
            // 3) Build.HARDWARE 含 mali
            if (Build.HARDWARE != null && Build.HARDWARE.toLowerCase().contains("mali")) {
                return true;
            }
        } catch (Throwable ignored) {
        }
        return false;
    }

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

        // OTA 架构自适应：返回设备主 ABI，供 Dart 端选对应拆分包下载。
        // API 21+ 用 SUPPORTED_ABIS[0]；低于 21 回退到已弃用但一贯可用的 CPU_ABI。
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), DEVICE_CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    if ("getPrimaryAbi".equals(call.method)) {
                        try {
                            final String abi = Build.VERSION.SDK_INT >= 21
                                    ? Build.SUPPORTED_ABIS[0]
                                    : Build.CPU_ABI;
                            result.success(abi);
                        } catch (Exception e) {
                            result.error("no_abi", e.getMessage(), null);
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
