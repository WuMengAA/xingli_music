package com.stelarith.xingli_music;

import android.content.Context;
import android.content.Intent;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;

import androidx.annotation.NonNull;

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
