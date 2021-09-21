Shader "Custom/Caustics"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,1)
        _MainTex ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0

        [Header(Caustics)]
        _CausticsTex("Caustics (RGB)", 2D) = "white" {}
        _Caustics_ST1("Caustics Tiling XY, Offset XY", Vector) = (1,1,0,0)
        _Caustics_ST2("Caustics Tiling XY, Offset XY", Vector) = (1,1,0,0)
        _Speed1("Speed1", Vector) = (1,1,0,0)
        _Speed2("Speed2", Vector) = (1,1,0,0)
        _SplitRGB("SplitRGB", Float) = 10
        _MaxHeight("Maximum Height", Float) = 10
    }
    SubShader
    {
        Tags { "RenderType"="Opaque"}
        LOD 200

        CGPROGRAM
        // Physically based Standard lighting model, and enable shadows on all light types
        #pragma surface surf Standard fullforwardshadows

        // Use shader model 3.0 target, to get nicer looking lighting
        #pragma target 3.0
        #include "Caustics.cginc"

        sampler2D _MainTex, _CausticsTex;
        float4 _Caustics_ST1, _Caustics_ST2;
        float2 _Speed1, _Speed2;
        float _SplitRGB, _MaxHeight;

        struct Input
        {
            float2 uv_MainTex;
            float3 worldPos;
        };

        half _Glossiness;
        half _Metallic;
        fixed4 _Color;

        // Add instancing support for this shader. You need to check 'Enable Instancing' on materials that use the shader.
        // See https://docs.unity3d.com/Manual/GPUInstancing.html for more information about instancing.
        // #pragma instancing_options assumeuniformscaling
        UNITY_INSTANCING_BUFFER_START(Props)
            // put more per-instance properties here
        UNITY_INSTANCING_BUFFER_END(Props)

        float3 caustics(float2 uvTex) {
            // Caustics sampling
            fixed2 uv = uvTex * _Caustics_ST1.xy + _Caustics_ST1.zw;
            uv += _Speed1 * _Time.y;
            // RGB split
            fixed s = _SplitRGB / 10;
            fixed r = tex2D(_CausticsTex, uv + fixed2(+s, +s)).r;
            fixed g = tex2D(_CausticsTex, uv + fixed2(+s, -s)).g;
            fixed b = tex2D(_CausticsTex, uv + fixed2(-s, -s)).b;
            fixed3 caustics1 = fixed3(r, g, b);
            //2
            uv = uvTex * _Caustics_ST2.xy + _Caustics_ST2.zw;
            uv += _Speed2 * _Time.y;
            r = tex2D(_CausticsTex, uv + fixed2(+s, +s)).r;
            g = tex2D(_CausticsTex, uv + fixed2(+s, -s)).g;
            b = tex2D(_CausticsTex, uv + fixed2(-s, -s)).b;
            fixed3 caustics2 = fixed3(r, g, b);
            // Blend
            return min(caustics1, caustics2);
        }

        void surf (Input IN, inout SurfaceOutputStandard o)
        {
            // Albedo comes from a texture tinted by color
            fixed4 c = tex2D (_MainTex, IN.uv_MainTex) * _Color;
            o.Albedo = c.rgb;
            if (IN.worldPos.y < _MaxHeight)
                o.Albedo.rgb += caustics(IN.uv_MainTex) * abs(min(1, ((_MaxHeight - IN.worldPos.y) / _MaxHeight))) * 2;
            /*if (IN.worldPos.y < (_MaxHeight - 0.1)) {
                o.Albedo.rgb += caustics(IN.uv_MainTex);
            }
            else {
                o.Albedo.rgb += blend(caustics(IN.uv_MainTex));
            }*/

            // Metallic and smoothness come from slider variables
            o.Metallic = _Metallic;
            o.Smoothness = _Glossiness;
            o.Alpha = c.a;
        }
        ENDCG
    }
    FallBack "Diffuse"
}
