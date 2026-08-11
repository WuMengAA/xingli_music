#version 460 core
#include <flutter/runtime_effect.glsl>

// ════════════════════════════════════════════════════════════════════
// 液态玻璃 FragmentShader：仅边缘折射 + 色散
// ════════════════════════════════════════════════════════════════════
// 参照 shuding/liquid-glass：
//  - 折射/色散**只作用于玻璃边缘一圈窄带**（默认 5px），
//    玻璃中心区域完全透出背景，保持清晰（不整块扭曲）
//  - 边缘：采样沿法线向外微偏移（放大镜/水滴感）+ RGB 分离（彩虹边）
// 用法：把背景渲染成 Image，setImageSampler(0, bgImage) 传入。
uniform vec2 uSize;          // 玻璃区域尺寸（逻辑像素）
uniform float uRadius;       // 圆角半径
uniform float uRefraction;   // 边缘折射强度（0~12，建议 3~6）
uniform float uDispersion;   // 边缘色散强度（0~3，建议 1~1.5）
uniform sampler2D uTexture;  // 背景纹理

out vec4 fragColor;

// 圆角矩形 SDF（p 为局部坐标，b 为半尺寸，r 为圆角）
float sdRoundRect(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

void main() {
    vec2 frag = FlutterFragCoord().xy;
    vec2 uv = frag / uSize;
    vec2 p = uv - 0.5;
    vec2 halfB = vec2(0.5);

    float d = sdRoundRect(p * uSize, halfB * uSize - vec2(2.0), uRadius);

    // 玻璃内部判定（d<0 在圆角矩形内）
    float inside = smoothstep(1.0, -1.0, d);

    // 边缘窄带：仅 d 在 [-5, 1] 范围内有折射/色散（约 5px 一圈）
    float edgeAmt = (1.0 - smoothstep(-5.0, 1.0, d)) * inside;

    // 折射位移：沿法线（径向）向外微偏移，只影响边缘带
    vec2 dir = normalize(p + vec2(1e-4));
    float disp = edgeAmt * uRefraction;
    vec2 baseUV = uv + dir * disp / uSize;

    // 色散：RGB 三通道分离，仅在边缘带
    float dsp = edgeAmt * uDispersion;
    vec2 rUV = baseUV + dir * (dsp * 1.5) / uSize;
    vec2 gUV = baseUV;
    vec2 bUV = baseUV - dir * (dsp * 1.5) / uSize;

    vec4 r = texture(uTexture, rUV);
    vec4 g = texture(uTexture, gUV);
    vec4 b = texture(uTexture, bUV);

    // 中心区域：完全透出背景（无偏移），只有边缘带用折射结果
    vec4 refracted = vec4(r.r, g.g, b.b, 1.0);
    vec4 bg = texture(uTexture, uv);
    fragColor = mix(bg, refracted, edgeAmt);
}
