package com.stelarith.xingli_music;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Intent;
import android.graphics.Bitmap;
import android.os.Bundle;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ProgressBar;

import java.util.HashSet;
import java.util.Set;

/**
 * 内嵌登录页（自写原生 WebView，零第三方依赖）。支持两种来源：
 *
 *  - 网易云（netease）：打开 https://music.163.com/login（桌面 UA），手机 App
 *    扫码并确认后，从 CookieManager 抓取**完整 cookie（含 httpOnly 的
 *    MUSIC_U）**回传 —— httpOnly cookie 网页 JS 读不到，必须在原生层取
 *    （webview_flutter 的 CookieManager 只有 set/clear，故自写）。
 *
 *  - 哔哩哔哩（bilibili）：打开 https://passport.bilibili.com/login（桌面 UA）
 *    的官方网页登录页，用户在网页里扫码（页面自带的标准 Web 二维码，B站 App
 *    可正常识别）或输账号登录，原生层从 CookieManager 抓取完整 cookie
 *    （含 httpOnly 的 SESSDATA）回传。
 *    注：原「qr_flutter 渲染 h5/app/passport 二维码」方案，手机 App 扫码后
 *    报「没有此界面」，故一律改为内嵌桌面模式网页登录（与网易云 12 号网页
 *    逻辑一致）。
 *
 * 结果：RESULT_OK + EXTRA_COOKIE（完整 cookie 串）；用户取消 → RESULT_CANCELED。
 * 底部「完成登录」按钮兜底：确认后页面若未自动跳转，手动点击同样抓取。
 *
 * 通过 Intent 的 EXTRA_LOGIN_TYPE 区分来源（缺省视为 netease，保持兼容）。
 */
public class CookieWebViewActivity extends Activity {

    public static final String EXTRA_COOKIE = "cookie";
    public static final String EXTRA_LOGIN_TYPE = "login_type";

    public static final String TYPE_NETEASE = "netease";
    public static final String TYPE_BILIBILI = "bilibili";

    private static final String NETEASE_LOGIN_URL = "https://music.163.com/login";
    private static final String BILIBILI_LOGIN_URL = "https://passport.bilibili.com/login";

    /** 桌面 UA：与 netease_api / bilibili_api 的桌面 UA 保持一致，避免风控/跳移动版。 */
    public static final String DESKTOP_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
          + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

    private WebView webView;
    private ProgressBar progressBar;

    /** 当前登录类型（决定登录页 URL / cookie 域名 / 成功标志）。 */
    private String mType;
    private String mLoginUrl;
    private String[] mCookieHosts;
    private String mSuccessFlag;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // 按类型装配配置（缺省 netease，兼容旧调用）。
        final String type = getIntent().getStringExtra(EXTRA_LOGIN_TYPE);
        if (TYPE_BILIBILI.equals(type)) {
            mType = TYPE_BILIBILI;
            mLoginUrl = BILIBILI_LOGIN_URL;
            // SESSDATA 通常落在 .bilibili.com；多域名兜底，避免漏抓。
            mCookieHosts = new String[] {
                    "https://www.bilibili.com",
                    "https://passport.bilibili.com",
                    "https://bilibili.com"
            };
            mSuccessFlag = "SESSDATA=";
        } else {
            mType = TYPE_NETEASE;
            mLoginUrl = NETEASE_LOGIN_URL;
            mCookieHosts = new String[] { "https://music.163.com" };
            mSuccessFlag = "MUSIC_U=";
        }

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);

        progressBar = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progressBar.setVisibility(ProgressBar.GONE);

        webView = new WebView(this);
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                // 始终在 WebView 内加载（登录页/跳转/二维码图片都走这里）
                return false;
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                progressBar.setVisibility(ProgressBar.VISIBLE);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                progressBar.setVisibility(ProgressBar.GONE);
                maybeFinishSuccess(view);
            }
        });

        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setUserAgentString(DESKTOP_UA);
        // 部分登录流程会种第三方 cookie，放行避免登录态不完整
        CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true);

        Button doneBtn = new Button(this);
        doneBtn.setText("完成登录（扫码/确认后若未自动跳转，点此）");
        doneBtn.setOnClickListener(v -> maybeFinishSuccess(webView));

        root.addView(webView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        root.addView(progressBar, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(doneBtn, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        setContentView(root);
        webView.loadUrl(mLoginUrl);
    }

    /**
     * cookie 已含登录主凭证（MUSIC_U / SESSDATA）且已离开登录页 → 成功返回
     * 完整 cookie。
     *
     * 仍停留在登录页时不自动返回：避免拿旧（或过期）cookie 误判，让用户
     * 完成登录；底部「完成登录」按钮可随时手动触发。
     */
    private void maybeFinishSuccess(WebView view) {
        final String url = view.getUrl();
        if (url != null && url.contains("/login")) return;

        final String cookie = collectCookie();
        if (cookie != null && cookie.contains(mSuccessFlag)) {
            setResult(RESULT_OK, new Intent().putExtra(EXTRA_COOKIE, cookie));
            finish();
        }
    }

    /**
     * 从多个域名汇总完整 cookie 串，按 cookie 名去重（同一字段只保留一份）。
     * SESSDATA / MUSIC_U 为 httpOnly，只能在此原生层取到。
     */
    private String collectCookie() {
        final StringBuilder sb = new StringBuilder();
        final Set<String> seen = new HashSet<>();
        for (final String host : mCookieHosts) {
            final String raw = CookieManager.getInstance().getCookie(host);
            if (raw == null || raw.isEmpty()) continue;
            for (final String part : raw.split(";")) {
                final String trimmed = part.trim();
                if (trimmed.isEmpty()) continue;
                final int eq = trimmed.indexOf('=');
                final String name = eq > 0 ? trimmed.substring(0, eq).trim() : trimmed;
                if (seen.add(name)) {
                    if (sb.length() > 0) sb.append("; ");
                    sb.append(trimmed);
                }
            }
        }
        return sb.length() > 0 ? sb.toString() : null;
    }

    @SuppressWarnings("deprecation")
    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack(); // 登录页内先返回上一页
        } else {
            super.onBackPressed(); // 退出 → RESULT_CANCELED
        }
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.destroy();
        }
        super.onDestroy();
    }
}
