#if !defined(LOOKING_THROUGH_WATER_INCLUDED)
#define LOOKING_THROUGH_WATER_INCLUDED

sampler2D _CameraDepthTexture, _WaterBackground;
float4 _CameraDepthTexture_TexelSize;

float3 _WaterFogColor;
float _WaterFogDensity, _RefractionStrength;

// fix blending when sampling the grabbed texture
// (to remove thin line of artifacts around the edge of the refraction)
float2 AlignWithGrabTexel(float2 uv) {
#if UNITY_UV_STARTS_AT_TOP
	if (_CameraDepthTexture_TexelSize.y < 0) {
		uv.y = 1 - uv.y;
	}
#endif
	return	(floor(uv * _CameraDepthTexture_TexelSize.zw) + 0.5) * abs(_CameraDepthTexture_TexelSize.xy);
}


//Returns rgb of fragments under the water
float3 ColorBelowWater(float4 screenPos, float3 tangentSpaceNormal) {
	//To make the offset wiggle, we'll use the XY coordinates of the tangent-space normal vector as the offset
	float2 uvOffset = tangentSpaceNormal.xy * _RefractionStrength;
	// not symmetrical. The vertical offset is less than the horizontal.
	// to equalize the offsets, we have to multiply the V offset by the image width divided by its height
	uvOffset.y *= _CameraDepthTexture_TexelSize.z * abs(_CameraDepthTexture_TexelSize.y);

	float2 uv = AlignWithGrabTexel((screenPos.xy + uvOffset) / screenPos.w);

	// depth relative to the screen
	float backgroundDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
	// surface depth
	float surfaceDepth = UNITY_Z_0_FAR_FROM_CLIPSPACE(screenPos.z);
	// water surface - depth = depth from surface to object
	float depthDifference = backgroundDepth - surfaceDepth;

	// Calculate new offset scaled by depth difference
	uvOffset *= saturate(depthDifference);
	// recalculate UV
	uv = AlignWithGrabTexel((screenPos.xy + uvOffset) / screenPos.w);
	// again sample depth difference with correct UV
	backgroundDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
	depthDifference = backgroundDepth - surfaceDepth;	

	// Get color from behind color
	float3 backgroundColor = tex2D(_WaterBackground, uv).rgb;
	// Calculate how much we want to apply fog
	float fogFactor = exp2(-_WaterFogDensity * depthDifference);
	return lerp(_WaterFogColor, backgroundColor, fogFactor);
}

#endif