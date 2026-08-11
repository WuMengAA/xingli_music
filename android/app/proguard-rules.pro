# ─────────────────────────────────────────────────────────────
# 星璃音乐 · R8 / ProGuard 保活规则（release 档）
#
# 说明：Flutter 引擎自身的规则（io.flutter.**）由 flutter gradle 插件
# 自动注入，此处只补充本工程用到的、含反射/JNI/原生回调的第三方插件。
# 原则：宁可多留一点，也不要为省几百 KB 换来运行期 ClassNotFound。
# ─────────────────────────────────────────────────────────────

# ── 通用：保留原生方法与注解信息 ─────────────────────────────
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
# 不保留 SourceFile/LineNumberTable：它们会把全部行号表写进 dex（实测约
# +0.5MB）。崩溃栈的还原改用构建产物里的 mapping.txt，见报告说明。

-keepclasseswithmembernames class * {
    native <methods>;
}

# 保留枚举的 values/valueOf（多处插件按名反射取枚举）
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Parcelable CREATOR（跨进程传 MediaItem 等）
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# ── just_audio / audio_session：底层是 Media3(ExoPlayer) ──────
# Media3 与 ExoPlayer 的 AAR 内已附带 consumer-proguard-rules，R8 会自动
# 应用，官方已声明哪些类必须保活。这里**不做** `-keep ...** { *; }` 的
# 整库保留——那样等于让 R8 完全无法裁剪这两个大库，只留 dontwarn。
-dontwarn com.google.android.exoplayer2.**
-dontwarn androidx.media3.**
# 插件自身的 Flutter 通道实现由 Dart 侧按名调用，保留。
-keep class com.ryanheise.just_audio.** { *; }
-keep class com.ryanheise.audio_session.** { *; }

# ── audio_service：后台 Service + 媒体按键广播接收器 ─────────
# 这些组件由系统按类名实例化，必须整类保留。
# （AndroidManifest 里声明过的组件 AGP 会自动保活，但 audio_service 有
#  运行期动态注册的接收器，故显式保留整个包。）
-keep class com.ryanheise.audioservice.** { *; }
-dontwarn androidx.media.**

# ── audioplayers ─────────────────────────────────────────────
-keep class xyz.luan.audioplayers.** { *; }

# ── on_audio_query：MediaStore 查询 + 反射映射字段 ────────────
-keep class com.lucasjosino.on_audio_query.** { *; }
-dontwarn com.lucasjosino.on_audio_query.**

# ── media_kit（libmpv 播放引擎，S2）──────────────────────────
# media_kit_libs_android_video 的 JNI 桥（MediaKitAndroidHelper 持有 libmpv
# 的 native 方法）与插件注册类**不自带 consumer-proguard-rules**；工程开启
# R8(minifyEnabled) 后若被混淆改名/裁剪 → 安卓 release 播放即崩
# （ClassNotFound / JNI 方法找不到）——「安卓默认解码器播放崩溃」根因。
# 整包保留（类极少，体积代价可忽略），并抑制其警告。
-keep class com.alexmercerind.mediakitandroidhelper.** { *; }
-keep class com.alexmercerind.media_kit_libs_android_video.** { *; }
-keep class com.alexmercerind.media_kit.** { *; }
-dontwarn com.alexmercerind.**

# ── permission_handler ───────────────────────────────────────
-keep class com.baseflow.permissionhandler.** { *; }

# ── sqflite ──────────────────────────────────────────────────
-keep class com.tekartik.sqflite.** { *; }

# ── file_picker ──────────────────────────────────────────────
-keep class com.mr.flutter.plugin.filepicker.** { *; }
-dontwarn com.mr.flutter.plugin.filepicker.**

# ── sensors_plus ─────────────────────────────────────────────
-keep class dev.fluttercommunity.plus.sensors.** { *; }

# ── 本工程自写的原生通道（光线/心率传感器）────────────────────
# 由 Dart 侧按方法名调用，禁止改名或裁剪。
-keep class com.stelarith.xingli_music.** { *; }

# ── Kotlin 协程：内部使用反射查找 ServiceLoader ───────────────
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# ── 抑制无关警告（这些类只在编译期出现，运行期不需要）────────
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
