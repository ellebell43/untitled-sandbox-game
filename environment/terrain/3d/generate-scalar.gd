class_name GenerateScalar

func generate(seed: int) -> void:
	var noise_type := FastNoiseLite.NoiseType.TYPE_PERLIN # possibly upgrade to Cellular when implementing caves
	# determines the size of the terrain features. Low means slow changes and gradual features. High is the opposite
	# Needs to be matched to the size of the desired mesh
	var frequency := 0.025
	# The number of copies 
	var octaves := 5
	
