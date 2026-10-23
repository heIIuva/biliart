--!strict
-- Tables placed in the world. Positions are studs on the floor (y = 0); sizes come from TableGeometry.

return {
	SurfaceHeight = 3, -- studs from the floor to the cloth
	-- Phase 2 test mode: free play, no rules. Replaced by matches in phase 3.
	FreePlay = {
		{ id = "free1", variant = "Standard", x = 0, z = -20 },
		{ id = "free2", variant = "Chinese8", x = 24, z = -20 },
	},
}
