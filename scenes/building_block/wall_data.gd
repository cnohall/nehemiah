extends Object
class_name WallData

## 12 gate/corner positions clockwise. Scale: ~1 unit = 15 m.
## These form the historical "pear-shaped" circuit of Nehemiah's Jerusalem.
## Coordinate system: X = east/west, Y = north(-)/south(+) mapped from 3D Z.
const CORNERS: Array[Vector2] = [
	Vector2(-16, -30),  # 0  NW  — Old/Jeshanah Gate
	Vector2( -6, -36),  # 1  N   — Fish Gate
	Vector2(  6, -36),  # 2  NE  — Sheep Gate  (Neh 3:1 start)
	Vector2( 20, -28),  # 3  NE  — Tower of Hananel / Miphkad Gate
	Vector2( 30, -14),  # 4  E   — East Gate
	Vector2( 30,   2),  # 5  E   — Horse Gate / Water Gate
	Vector2( 20,  20),  # 6  SE  — Fountain Gate
	Vector2(  6,  32),  # 7  S   — toward Dung Gate
	Vector2( -4,  36),  # 8  S   — Dung Gate (southernmost)
	Vector2(-16,  26),  # 9  SW  — Valley Gate
	Vector2(-28,   8),  # 10 W   — Tower of Ovens / Broad Wall
	Vector2(-28, -14),  # 11 WN  — Broad Wall north end
]

## 12 playable sections in Nehemiah 3 narrative order.
## "a" and "b" are CORNERS indices.
const SECTIONS: Array[Dictionary] = [
	{
		"name": "Sheep Gate", "neh": "3:1-2", "a": 2, "b": 3, "day_start": 1, "day_end": 4,
		"quote": "Eliashib the high priest arose with his brothers the priests and built the Sheep Gate."
	},
	{
		"name": "Fish Gate", "neh": "3:3-5", "a": 1, "b": 2, "day_start": 5, "day_end": 8,
		"quote": "The sons of Hassenaah built the Fish Gate with its beams and doors."
	},
	{
		"name": "Jeshanah Gate", "neh": "3:6-12", "a": 0, "b": 1, "day_start": 9, "day_end": 12,
		"quote": "Joiada and Meshullam repaired the Jeshanah Gate; goldsmiths worked alongside."
	},
	{
		"name": "Broad Wall", "neh": "3:8", "a": 11, "b": 0, "day_start": 13, "day_end": 17,
		"quote": "They restored Jerusalem as far as the Broad Wall."
	},
	{
		"name": "Tower of Ovens", "neh": "3:11-12", "a": 10, "b": 11, "day_start": 18, "day_end": 23,
		"quote": "Malkijah and Hasshub repaired another section and the Tower of Ovens."
	},
	{
		"name": "Valley Gate", "neh": "3:13", "a": 9, "b": 10, "day_start": 24, "day_end": 29,
		"quote": "Hanun and the inhabitants of Zanoah repaired the Valley Gate."
	},
	{
		"name": "Dung Gate", "neh": "3:13-14", "a": 8, "b": 9, "day_start": 30, "day_end": 33,
		"quote": "Malchijah son of Rechab repaired the Dung Gate; he rebuilt it and set its doors."
	},
	{
		"name": "Fountain Gate", "neh": "3:15", "a": 7, "b": 8, "day_start": 34, "day_end": 36,
		"quote": "Shallun repaired the Fountain Gate; he built it and covered it, and set its doors."
	},
	{
		"name": "Water Gate & Ophel", "neh": "3:26-27", "a": 6, "b": 7, "day_start": 37, "day_end": 41,
		"quote": "The temple servants living on Ophel made repairs as far as the Water Gate."
	},
	{
		"name": "Horse Gate", "neh": "3:28", "a": 5, "b": 6, "day_start": 42, "day_end": 47,
		"quote": "Above the Horse Gate the priests made repairs, each one opposite his own house."
	},
	{
		"name": "East Gate", "neh": "3:29", "a": 4, "b": 5, "day_start": 48, "day_end": 50,
		"quote": "Zadok son of Immer made repairs opposite his own house."
	},
	{
		"name": "Miphkad Gate", "neh": "3:31-32", "a": 3, "b": 4, "day_start": 51, "day_end": 52,
		"quote": "Goldsmiths and merchants completed the circuit, from the Miphkad Gate."
	},
]
