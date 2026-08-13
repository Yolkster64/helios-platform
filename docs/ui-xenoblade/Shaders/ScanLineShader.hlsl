// ScanLineShader.hlsl - Holographic Scan Line Effect
// Creates horizontal scan lines with semi-transparency for holographic appearance

Texture2D inputTexture : register(t0);
SamplerState inputSampler : register(s0);

cbuffer ShaderConstants : register(b0)
{
    float lineSpacing;     // Pixels between scan lines
    float lineHeight;      // Thickness of each line
    float lineOpacity;     // 0.0 - 1.0
    float scanSpeed;       // Animation speed (0.0 - 1.0)
};

float4 main(float2 uv : TEXCOORD0) : SV_TARGET
{
    float4 baseColor = inputTexture.Sample(inputSampler, uv);
    
    // Create scan line pattern
    float scanLine = abs(sin(uv.y * lineSpacing + scanSpeed)) < lineHeight ? 1.0 : 0.0;
    
    // Create holographic cyan color
    float4 scanColor = float4(0.0, 0.83, 1.0, lineOpacity * scanLine);
    
    // Blend with base
    float4 result = lerp(baseColor, scanColor, lineOpacity * scanLine * 0.3);
    
    return result;
}
