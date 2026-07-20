extends GutTest

var chunk = Chunk.new(20, WorldNoise.new(1, 100), Vector3.ZERO, 4)

func test_check_minus_x_shift():
	var shifted_vector = chunk._apply_shift(Vector3(0, 40, 40), 8)
	assert_eq(shifted_vector, Vector3(1, 40, 40))

func test_check_positive_x_shift():
	var shifted_vector = chunk._apply_shift(Vector3(0, 40, 40), 0)
	assert_eq(shifted_vector, Vector3(0, 40, 40))
