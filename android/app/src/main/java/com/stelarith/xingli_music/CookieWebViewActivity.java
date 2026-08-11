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

/**
 * 网易云内嵌登录页（自写原生 WebView，零第三方依赖）。
 *
 * 打开 https://music.163.com/login（桌面 UA），用户手机网易云 App 扫码并确认后
 * 网页跳转回主页；此时从 CookieManager 抓取**完整 cookie（含 httpOnly 的
 * MUSIC_U）**回传给 Flutter 存 SecureBox —— httpOnly cookie 网页 JS 读不到，
 * 必须在原生层取（webview_flutter 的 CookieManager 只有 set/clear，故自写）。
 *
 * 结果：RESULT_OK + EXTRA_COOKIE（完整 cookie 串）；用户取消 → RESULT_CANCELED。
 * 底部「完成登录」按钮兜底：扫码确认后页面若未自动跳转，手动点击同样抓取。
 */
public class CookieWebViewActivity extends Activity {

    public static final String EXTRA_COOKIE = "cookie";
    public static final String LOGIN_URL = "https://music.163.com/login";

    /** 桌面 UA：与 netease_api.dart 的 kNeteaseUserAgent 保持一致，避免风控/跳移动版。 */
    public static final String DESKTOP_UA =
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
          + "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

    private WebView webView;
    private ProgressBar progressBar;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

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
        doneBtn.setText("完成登录（扫码确认后若未跳转，点此）");
        doneBtn.setOnClickListener(v -> maybeFinishSuccess(webView));

        root.addView(webView, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        root.addView(progressBar, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
        root.addView(doneBtn, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        setContentView(root);
        webView.loadUrl(LOGIN_URL);
    }

    /**
     * cookie 已含登录主凭证 MUSIC_U 且已离开登录页 → 成功返回完整 cookie。
     *
     * 仍停留在登录页时不自动返回：避免拿旧（或过期）cookie 误判，让用户
     * 完成新一次扫码；底部「完成登录」按钮可随时手动触发。
     */
    private void maybeFinishSuccess(WebView view) {
        String url = view.getUrl();
        if (url != null && url.contains("/login")) return;

        String cookie = CookieManager.getInstance().getCookie("https://music.163.com");
        if (cookie != null && cookie.contains("MUSIC_U=")) {
            setResult(RESULT_OK, new Intent().putExtra(EXTRA_COOKIE, cookie));
            finish();
        }
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
