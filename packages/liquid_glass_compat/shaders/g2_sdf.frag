// ════════════════════════════════════════════════════════════════════
// G2 SDF 液态玻璃 FragmentShader
// ════════════════════════════════════════════════════════════════════
// 移植自 liquid-glass-webgl 的 element shader：
//  - 用 G2 连续曲率 SDF 纹理（负内正外，[-1,1]）做形状判定，
//    大圆角精确 G2 角形（非朴素圆角矩形）
//  - 边缘窄带折射 + RGB 色差（chromatic aberration），忠实
//    lens(chromaticAberration=true) 的折射透镜
//  - 顶部高光带 + 边缘内阴影由 SDF 距离驱动
//
// 用法（Flutter）：
//   final program = await FragmentProgram.fromAsset('shaders/g2_sdf.frag');
//   final shader = program.fragmentShader()
//     ..setImageSampler(0, sdfImage)      // SDF RGBA8 纹理（R 通道）
//     ..setImageSampler(1, backgroundImage)
//     ..setFloat(0, w) ..setFloat(1, h)
//     ..setFloat(2, radiusPx)
//     ..setFloat(3, refraction) ..setFloat(4, dispersion);
// ════════════════════════════════════════════════════════════════════
#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;        // 玻璃区域尺寸（逻辑 px）
uniform float uRadius;     // 圆角半径（逻辑 px，用于比率换算）
uniform float uRefraction; // 边缘折射强度 0~12
uniform float uDispersion; // 色散强度 0~3
uniform float uHighlight;  // 高光强度 0~1
uniform sampler2D uSdf;    // G2 SDF 纹理（R 通道，[-1,1] → [0,1]）
uniform sampler2D uBg;     // 背景纹理

out vec4 fragColor;

void main() {
    vec2 frag = FlutterFragCoord().xy;
    vec2 uv = frag / uSize;

    // 采样 G2 SDF：值域 [0,1] → [-1,1]，负内正外。
    float d = texture(uSdf, uv).r * 2.0 - 1.0;

    // 形状内部判定。
    float inside = smoothstep(0.0, -0.01, d);

    // 边缘窄带：d ∈ [-5px/uSize 归一化……]，这里按纹理像素近似：
    // SDF 纹理是归一化的，边缘带宽度用归一化距离表示。
    float edgeBand = 0.02; // ≈ 2% of the element size
    float edgeAmt = (1.0 - smoothstep(-edgeBand, edgeBand * 0.15, d)) * inside;

    // 折射位移：沿径向（向元素中心反方向）。
    vec2 dir = normalize(uv - 0.5 + vec2(1e-4));
    float disp = edgeAmt * uRefraction / uSize.x;
    vec2 baseUV = uv + dir * disp;

    // 色差：RGB 分离，仅在边缘带。
    float dsp = edgeAmt * uDispersion / uSize.x;
    vec2 rUV = baseUV + dir * (dsp * 1.5);
    vec2 gUV = baseUV;
    vec2 bUV = baseUV - dir * (dsp * 1.5);

    vec4 r = texture(uBg, rUV);
    vec4 g = texture(uBg, gUV);
    vec4 b = texture(uBg, bUV);
    vec4 refracted = vec4(r.r, g.g, b.b, 1.0);
    vec4 bg = texture(uBg, uv);

    vec4 color = mix(bg, refracted, edgeAmt);

    // 顶部高光带：由 SDF 的 y 位置驱动（亮带只在元素上部）。
    float yNorm = uv.y;
    float highlightAmt = inside * uHighlight * (1.0 - smoothstep(0.15, 0.45, yNorm));
    color = color + vec4(highlightAmt, highlightAmt, highlightAmt, 0.0);

    fragColor = vec4(color.rgb, inside);
}