Shader "Custom/WavesNoTransparent"
{
    Properties
    {
        _Color("Color", Color) = (1,1,1,1)
        _MainTex("Albedo (RGB)", 2D) = "white" {}
        _Glossiness("Smoothness", Range(0,1)) = 0.5
        _Metallic("Metallic", Range(0,1)) = 0.0

        _WaveA("Wave A (dir, steepness, wavelength)", Vector) = (1, 0, 0.5, 10)
        _WaveB("Wave B (dir, steepness, wavelength)", Vector) = (0, 1, 0.25, 20)
        _WaveC("Wave C (dir, steepness, wavelength)", Vector) = (1, 1, 0.15, 10)
        _WaveD("Wave D (dir, steepness, wavelength)", Vector) = (1, 1, 0.5, 10)
    }
        SubShader
        {
            Tags { "RenderType" = "Opaque" }
            LOD 200
            CULL OFF

            CGPROGRAM
            // Physically based Standard lighting model, and enable shadows on all light types
            #pragma surface surf Standard fullforwardshadows vertex:vert addshadow

            // Use shader model 3.0 target, to get nicer looking lighting
            #pragma target 3.0

            sampler2D _MainTex;
            float4 _WaveA, _WaveB, _WaveC, _WaveD;

            struct Input
            {
                float2 uv_MainTex;
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
                // Albedo comes from a texture tinted by color
                fixed4 c = tex2D(_MainTex, IN.uv_MainTex) * _Color;
                o.Albedo = c.rgb;
                // Metallic and smoothness come from slider variables
                o.Metallic = _Metallic;
                o.Smoothness = _Glossiness;
                o.Alpha = c.a;
            }
            ENDCG
        }
            FallBack "Diffuse"
}
