Shader "Custom/WavesDirectional"
{
    Properties
    {
        [Header(Main)]
        _Color("Color", Color) = (1,1,1,1)
        _Glossiness("Smoothness", Range(0,1)) = 0.5
        _Metallic("Metallic", Range(0,1)) = 0.0

        [Header(Waves)]
        _WaveA("Wave A (dir, steepness, wavelength)", Vector) = (1, 0, 0.5, 10)
        _WaveB("Wave B (dir, steepness, wavelength)", Vector) = (0, 1, 0.25, 20)
        _WaveC("Wave C (dir, steepness, wavelength)", Vector) = (1, 1, 0.15, 10)
        _WaveD("Wave D (dir, steepness, wavelength)", Vector) = (1, 1, 0.5, 10)

        [Header(Fog)]
        _WaterFogColor("Water Fog Color", Color) = (0, 0, 0, 0)
        _WaterFogDensity("Water Fog Density", Range(0, 2)) = 0.1

        [Header(Refraction)]
        _RefractionStrength("Refraction Strength", Range(0, 1)) = 0.25

        [Header(Distortion)]
        [NoScaleOffset] _MainTex("Deriv (AG) Height (B)", 2D) = "black" {}
        [NoScaleOffset] _FlowMap("Flow (RG)", 2D) = "black" {}
        _Tiling("Tiling", Float) = 1
        _TilingModulated("Tiling, Modulated", Float) = 1
        _Speed("Speed", Float) = 1
        _FlowStrength("Flow Strength", Float) = 1
        _HeightScale("Height Scale, Constant", Float) = 0.25
        _HeightScaleModulated("Height Scale, Modulated", Float) = 0.75
        _GridResolution("Grid Resolution", Float) = 10

    }
        SubShader 
        {
            Tags { "RenderType" = "Transparent" "Queue" = "Transparent"}
            LOD 200
            CULL OFF

            GrabPass{"_WaterBackground"}
            CGPROGRAM
            // Physically based Standard lighting model, and enable shadows on all light types
            #pragma surface surf Standard  alpha finalcolor:ResetAlpha vertex:vert addshadow

            // Use shader model 3.0 target, to get nicer looking lighting
            #pragma target 3.0

            #include "Flow.cginc"
            #include "LookingThroughWater.cginc"

            sampler2D _MainTex, _FlowMap;
            float _Tiling, _Speed, _FlowStrength, _HeightScale, _TilingModulated, _HeightScaleModulated, _GridResolution;

            float4 _WaveA, _WaveB, _WaveC, _WaveD;

            struct Input
            {
                //We take screen position on input for refraction and tex coords for flow
                float2 uv_MainTex;
                float4 screenPos;
            };

            half _Glossiness;
            half _Metallic;
            fixed4 _Color;

            float3 GerstnerWave(float4 wave, float3 p, inout float3 tangent, inout float3 binormal) {
                float2 dir = wave.xy;
                float steepness = wave.z;
                float wavelength = wave.w;

                float k = 2 * UNITY_PI / wavelength;
                float a = steepness / k;
                float c = sqrt(9.8 / k);
                float2 d = normalize(dir);
                float f = k * (dot(d, p.xz) - c * _Time.y);

                tangent += float3(
                    -d.x * d.x * (steepness * sin(f)),
                    d.x * (steepness * cos(f)),
                    -d.x * d.y * (steepness * sin(f)));
                binormal += float3(
                    -d.x * d.y * (steepness * sin(f)),
                    d.y * (steepness * cos(f)),
                    -d.y * d.y * (steepness * sin(f)));

                return float3(
                    d.x * (a * cos(f)),
                    a * sin(f),
                    d.y * (a * cos(f)));
            }

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

                float3 flow = tex2D(_FlowMap, uvTiled * 1).rgb;
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

            void ResetAlpha(Input IN, SurfaceOutputStandard o, inout fixed4 color) {
                color.a = 1;
            }

            void vert(inout appdata_full vertexData) {
                float3 p = vertexData.vertex.xyz;
                float3 tangent = float3(1, 0, 0);
                float3 binormal = float3(0, 0, 1);

                p += GerstnerWave(_WaveA, vertexData.vertex.xyz, tangent, binormal);
                p += GerstnerWave(_WaveB, vertexData.vertex.xyz, tangent, binormal);
                p += GerstnerWave(_WaveC, vertexData.vertex.xyz, tangent, binormal);
                p += GerstnerWave(_WaveD, vertexData.vertex.xyz, tangent, binormal);

                float3 normal = normalize(cross(binormal, tangent));

                vertexData.vertex.xyz = p;
                vertexData.normal = normal;
            }

            void surf(Input IN, inout SurfaceOutputStandard o)
            {
                // Get tex coordinates and scaled to _Tiling - bigger the _Tiling, bigger the uv, more details 
                float2 uv = IN.uv_MainTex;
                float time = _Time.y * _Speed;

                float3 dh = FlowGrid(uv, time, false);
                dh = (dh + FlowGrid(uv, time, true)) * 0.5;
                // Output color is height of waves ^ 2 * Color from inspector
                fixed4 c = dh.z * dh.z * _Color * 2;
                c.a = _Color.a;

                o.Albedo = c.rgb;
                // Output normals are normalized scaled derivatives from derivative-height ong image
                o.Normal = normalize(float3(-dh.xy, 1));
                // Metallic and smoothness come from slider variables
                o.Metallic = _Metallic;
                o.Smoothness = _Glossiness;
                o.Alpha = c.a;

                o.Emission = ColorBelowWater(IN.screenPos, o.Normal * 50) * (1 - c.a);
            }
            ENDCG
        }
            FallBack "Diffuse"
}
