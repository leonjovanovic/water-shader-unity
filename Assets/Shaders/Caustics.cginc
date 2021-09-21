#if !defined(CAUSTISCS_INCLUDED)
#define CAUSTICS_INCLUDED

sampler2D _CameraDepthTexture;


//Returns rgb of fragments under the water
bool BelowWater(float4 screenPos) {

	float2 uv = screenPos.xy / screenPos.w;

	// depth relative to the screen
	float backgroundDepth = LinearEyeDepth(SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, uv));
	// surface water depth
	float surfaceDepth = UNITY_Z_0_FAR_FROM_CLIPSPACE(screenPos.z);
	// depth - water surface = depth from surface to object

	if (backgroundDepth < surfaceDepth)
		return false;
	return true;
}

#endif