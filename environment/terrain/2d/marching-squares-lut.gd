class_name MarchingSqauresLUT

# Marching Squares lookup tables
# Convention (must match how you sample corners and interpolate edges):
#   Corners, counter-clockwise from bottom-left:
#     c0 = bottom-left, c1 = bottom-right, c2 = top-right, c3 = top-left
#   Edges, each between two adjacent corners:
#     e0 = bottom (c0-c1), e1 = right (c1-c2), e2 = top (c2-c3), e3 = left (c3-c0)
#   case = c0*1 + c1*2 + c2*4 + c3*8   (bit set when that corner is inside)

# c3-----e2-----c2
# |              |
# |              |
# e3            e1
# |              |
# |              |
# c0-----e0-----c1

## EDGE_MASK[case] -> 4-bit mask of which edges the contour crosses
const EDGE_MASK := [
	0x0, 0x9, 0x3, 0xa, 0x6, 0xf, 0x5, 0xc, 0xc, 0x5, 0xf, 0x6, 0xa, 0x3, 0x9, 0x0
]

## SEGMENT_TABLE[case] -> edge indices in PAIRS; each pair is one line segment. Read two at a time until you hit -1. A point is placed on each listed edge (midpoint first, then interpolate), and the pair is connected by a line. Cases 5 and 10 are ambiguous (diagonal); this table keeps the two inside corners SEPARATE. Swap those two rows to flip the resolution, or pick per-cell using the center/average sample (asymptotic decider) for fewer artifacts.
const SEGMENT_TABLE := [
	[-1, -1, -1, -1, -1],
	[0, 3, -1, -1, -1],
	[0, 1, -1, -1, -1],
	[1, 3, -1, -1, -1],
	[1, 2, -1, -1, -1],
	[3, 0, 1, 2, -1],
	[0, 2, -1, -1, -1],
	[2, 3, -1, -1, -1],
	[2, 3, -1, -1, -1],
	[0, 2, -1, -1, -1],
	[0, 1, 2, 3, -1],
	[1, 2, -1, -1, -1],
	[1, 3, -1, -1, -1],
	[0, 1, -1, -1, -1],
	[0, 3, -1, -1, -1],
	[-1, -1, -1, -1, -1],
]
