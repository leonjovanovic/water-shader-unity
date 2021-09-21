Shader "Custom/DirectionalFlowNoTransparent"
{
    Properties
    {
        _Color("Color", Color) = (1,1,1,1)
        [NoScaleOffset] _MainTex("Deriv (AG) Height (B)", 2D) = "black" {}
        [NoScaleOffset] _FlowMap("Flow (RG)", 2D) = "black" {}
        _Tiling("Tiling", Float) = 1
        _TilingModulated("Tiling, Modulated", Float) = 1
        _Speed("Speed", Float) = 1
        _FlowStrength("Flow Strength", Float) = 1
        _HeightScale("Height Scale, Constant", Float) = 0.25
        _HeightScaleModulated("Height Scale, Modulated", Float) = 0.75
        _GridResolution("Grid Resolution", Float) = 10
        _Glossiness("Smoothness", Range(0,1)) = 0.5
        _Metallic("Metallic", Range(0,1)) = 0.0
    }
        SubShader
        {
            Tags { "RenderType" = "Opaque" }
            LOD 200

            CGPROGRAM
            // Physically based Standard lighting model, and enable shadows on all light types
            #pragma surface surf Standard fullforwardshadows

            #pragma target 3.0

            #include "Flow.cginc"

            sampler2D _MainTex, _FlowMap;
            float _Tiling, _Speed, _FlowStrength, _HeightScale, _TilingModulated, _HeightScaleModulated, _GridResolution;
            struct Input
            {
                float2 uv_MainTex;
            };

            half _Glossiness;
            half _Metallic;
            fixed4 _Color;


            float3 UnpackDerivativeHeight(float4 textureData) {
                float3 dh = textureData.agb;
                dh.xy = dh.xy * 2 - 1;
                return dh;
            }

            float3 FlowCell(float2 uv, float2 offset, float time, bool gridB) {
                float2 shift = 1 - offset;
                shift *= 0.5;
                offset *= 0.5;
                if (gridB) {
                    shift -= 0.25;
                    offset += 0.25;
                }
                float2x2 derivRotation;
                float2 uvTiled = (floor(uv * _GridResolution + offset) + shift) / _GridResolution;

                float3 flow = tex2D(_FlowMap, uvTiled * 0.1).rgb;
                flow.xy = flow.xy * 2 - 1;
                flow.z *= _FlowStrength;
                float tiling = flow.z * _TilingModulated + _Tiling;
                float2 uvFlow = DirectionalFlowUV(uv + offset, flow, tiling, time, derivRotation);
                // From RGBA color from texture MainTex to scaled derivatives (RG) and heigth of waves (B)
                float3 dh = UnpackDerivativeHeight(tex2D(_MainTex, uvFlow));
                dh.xy = mul(derivRotation, dh.xy);
                dh *= flow.z * _HeightScaleModulated + _HeightScale;
                return dh;
            }

            float3 FlowGrid(float2 uv, float time, bool gridB) {
                float3 dhA = FlowCell(uv, float2(0, 0), time, gridB);
                float3 dhB = FlowCell(uv, float2(1, 0), time, gridB);
                float3 dhC = FlowCell(uv, float2(0, 1), time, gridB);
                float3 dhD = FlowCell(uv, float2(1, 1), time, gridB);

                float2 t = uv * _GridResolution;
                if (gridB) {
                    t += 0.25;
                }
                t = abs(2 * frac(t) - 1);
                float wA = (1 - t.x) * (1 - t.y);
                float wB = t.x * (1 - t.y);
                float wC = (1 - t.x) * t.y;
                float wD = t.x * t.y;

                return dhA * wA + dhB * wB + dhC * wC + dhD * wD;
            }

            void surf(Input IN, inout SurfaceOutputStandard o)
            {
                // Get tex coordinates and scaled to _Tiling - bigger the _Tiling, bigger the uv, more details 
                float2 uv = IN.uv_MainTex;
                float time = _Time.y * _Speed;

                float3 dh = FlowGrid(uv, time, false);
                dh = (dh + FlowGrid(uv, time, true)) * 0.5;
                // Output color is height of waves ^ 2 * Color from inspector
                fixed4 c = dh.z * dh.z * _Color;
                o.Albedo = c.rgb;
                // Output normals are normalized scaled derivatives from derivative-height ong image
                o.Normal = normalize(float3(-dh.xy, 1));

                // Metallic and smoothness come from slider variables
                o.Metallic = _Metallic;
                o.Smoothness = _Glossiness;
                o.Alpha = c.a;
            }
            ENDCG
        }
            FallBack "Diffuse"
}
