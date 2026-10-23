--!strict
-- Tables placed in the world. Positions are studs on the floor (y = 0); sizes come from TableGeometry.

return {
	SurfaceHeight = 3, -- studs from the floor to the cloth
	KingTableId = "king",
	Placements = {
		{ id = "table1", variant = "Standard", x = 0, z = -20, king = false },
		{ id = "table2", variant = "Chinese8", x = 24, z = -20, king = false },
		{ id = "table3", variant = "Standard", x = -24, z = -20, king = false },
		-- The Tiger table in the middle of the lobby: King of the table.
		{ id = "king", variant = "Chinese8", x = 0, z = -46, king = true },
	},
	BigScreen = { x = 0, y = 14, z = -62 }, -- spectator screen behind the King table
}
