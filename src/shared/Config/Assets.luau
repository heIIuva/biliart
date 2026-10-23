--!strict
-- All Sound/Image/Mesh asset IDs by key. 0 = placeholder: code must fall back (print stub, no sound).
-- Keep in sync with docs/ASSETS.md.

-- A sound plays [start, start + length) of the clip (seconds) at volume `gain` x event volume.
export type SoundAsset = { id: number, start: number, length: number, gain: number }

return {
	-- Temporary picks from the Roblox Creator Store "Pro Sound Effects" library (free for experiences).
	-- Regions were found by measuring each clip's peak envelope in Studio (AudioAnalyzer, 60 Hz):
	-- they cut one hit out of clips that contain several. Replace with own recordings later.
	Sounds = {
		CueStrike = { id = 9113441098, start = 0, length = 0.2, gain = 4 }, -- Billiards Ball Hits Rolls With Cue Stick 3
		BallHit = { id = 9113440232, start = 0, length = 0.14, gain = 1 }, -- Billiard Balls Ball Hits Rolls 13
		CushionHit = { id = 9113440925, start = 0.24, length = 0.26, gain = 4 }, -- Billiards Ball Bounces Off Of Bumpers 8
		JawHit = { id = 9113440927, start = 0.17, length = 0.23, gain = 2.5 }, -- Billiards Ball Bounces Off Of Bumpers 7
		Pocket = { id = 9113442190, start = 0.65, length = 0.85, gain = 1.5 }, -- Billiards Shoot Balls Into Pockets 1
		Land = { id = 9113441345, start = 0.23, length = 0.27, gain = 4 }, -- Billiards Balls Rolling On Table 3
	} :: { [string]: SoundAsset },
	-- Image ids of assets/balls/textures/ball_XX.png, indexed by ball number. 0 = primitive ball.
	BallTextures = {
		[0] = 94582154597185,
		[1] = 94484194246352,
		[2] = 137300563916549,
		[3] = 125026440322148,
		[4] = 106935527211424,
		[5] = 94577084985054,
		[6] = 97222397539262,
		[7] = 131926019974463,
		[8] = 138919383928414,
		[9] = 86317855772132,
		[10] = 134682479878788,
		[11] = 130362129298563,
		[12] = 127578697825006,
		[13] = 78247925672085,
		[14] = 81772209018229,
		[15] = 134898959211875,
	} :: { [number]: number },
	CueTexture = 121590670390594, -- Image id of assets/cue/cue.png
	Images = {} :: { [string]: number },
	-- Model asset ids holding one MeshPart each; MeshService loads them into ReplicatedStorage.Assets.
	Meshes = {
		BallMesh = 101280782263579, -- assets/balls/pool_ball.obj as glTF, Z pre-mirrored (the importer mirrors Z)
	} :: { [string]: number },
}
