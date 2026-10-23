--!strict
-- Builds a pool table from primitives, sized from TableGeometry (placeholder art).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Physics = require(Shared.Config.Physics)
local TableGeometry = require(Shared.Pool.TableGeometry)
local Tables = require(Shared.Config.Tables)
local TableSpace = require(Shared.World.TableSpace)

-- Meters, like the simulation.
local CUSHION_WIDTH = 0.05
local JAW_WIDTH = 0.015
local FRAME_WIDTH = 0.12
local FRAME_TOP = 0.06 -- frame top above the cloth
local CLOTH_THICKNESS = 0.03
local APRON_DEPTH = 0.15
local LEG_SIZE = 0.12
local HOLE_THICKNESS = 0.002

local CLOTH_COLORS: { [TableGeometry.Variant]: Color3 } = {
	Standard = Color3.fromRGB(28, 110, 64),
	Chinese8 = Color3.fromRGB(150, 24, 32),
}
local WOOD_COLOR = Color3.fromRGB(70, 38, 20)
local HOLE_COLOR = Color3.fromRGB(10, 10, 10)

export type Built = {
	model: Model,
	surface: CFrame, -- center of the cloth surface, see World/TableSpace
	seat: CFrame, -- HumanoidRootPart placement for a seated player
}

local function part(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material,
	parent: Instance
): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material
	p.Parent = parent
	return p
end

local TableBuilder = {}

-- `origin` is the floor point under the table center; the table's long side follows origin.XVector.
function TableBuilder.build(id: string, variant: TableGeometry.Variant, origin: CFrame): Built
	local geometry = TableGeometry.get(variant)
	local s = TableSpace.studs
	local hl, hw = geometry.halfLength, geometry.halfWidth
	local surface = origin * CFrame.new(0, Tables.SurfaceHeight, 0)
	local clothColor = CLOTH_COLORS[variant]
	local cushionColor = clothColor:Lerp(Color3.new(0, 0, 0), 0.25)

	local model = Instance.new("Model")
	model.Name = `PoolTable_{id}`
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	model:SetAttribute("TableId", id)
	model:SetAttribute("Variant", variant)

	local innerL, innerW = 2 * (hl + CUSHION_WIDTH), 2 * (hw + CUSHION_WIDTH)
	local cloth = part(
		"Cloth",
		Vector3.new(s(innerL), s(CLOTH_THICKNESS), s(innerW)),
		surface * CFrame.new(0, -s(CLOTH_THICKNESS) / 2, 0),
		clothColor,
		Enum.Material.Fabric,
		model
	)
	model.PrimaryPart = cloth

	-- Cushions and jaw walls sit behind their segment (opposite to the normal).
	for _, seg in geometry.segments do
		local width = if seg.cushionId > 0 then CUSHION_WIDTH else JAW_WIDTH
		local midX = (seg.ax + seg.bx) / 2 - seg.nx * width / 2
		local midY = (seg.ay + seg.by) / 2 - seg.ny * width / 2
		local center = TableSpace.toWorld(surface, midX, midY, Physics.RailHeight / 2)
		local along = TableSpace.direction(surface, seg.dx, seg.dy)
		part(
			if seg.cushionId > 0 then `Cushion{seg.cushionId}` else `Jaw{seg.pocketId}`,
			Vector3.new(s(seg.len), s(Physics.RailHeight), s(width)),
			CFrame.fromMatrix(center, along, surface.UpVector),
			cushionColor,
			Enum.Material.Fabric,
			model
		)
	end

	-- Pockets: black discs on the cloth (the jaws and the frame cover their outer part).
	for _, pocket in geometry.pockets do
		local diameter = s(2 * (pocket.radius + geometry.ballRadius))
		local center = TableSpace.toWorld(surface, pocket.x, pocket.y, HOLE_THICKNESS / 2)
		part(
			`Pocket{pocket.id}`,
			Vector3.new(s(HOLE_THICKNESS), diameter, diameter),
			CFrame.new(center) * surface.Rotation * CFrame.Angles(0, 0, math.pi / 2),
			HOLE_COLOR,
			Enum.Material.SmoothPlastic,
			model
		)
	end

	-- Wooden frame around the cushions, apron below the cloth, legs.
	local frameHeight = FRAME_TOP + CLOTH_THICKNESS
	local frameY = (FRAME_TOP - CLOTH_THICKNESS) / 2
	local outerL = innerL + 2 * FRAME_WIDTH
	for _, sign in { -1, 1 } do
		part(
			"FrameLong",
			Vector3.new(s(outerL), s(frameHeight), s(FRAME_WIDTH)),
			surface * CFrame.new(0, s(frameY), -sign * s(hw + CUSHION_WIDTH + FRAME_WIDTH / 2)),
			WOOD_COLOR,
			Enum.Material.Wood,
			model
		)
		part(
			"FrameShort",
			Vector3.new(s(FRAME_WIDTH), s(frameHeight), s(innerW)),
			surface * CFrame.new(sign * s(hl + CUSHION_WIDTH + FRAME_WIDTH / 2), s(frameY), 0),
			WOOD_COLOR,
			Enum.Material.Wood,
			model
		)
	end
	local outerW = innerW + 2 * FRAME_WIDTH
	local apronTop = -CLOTH_THICKNESS
	part(
		"Apron",
		Vector3.new(s(outerL), s(APRON_DEPTH), s(outerW)),
		surface * CFrame.new(0, s(apronTop - APRON_DEPTH / 2), 0),
		WOOD_COLOR,
		Enum.Material.Wood,
		model
	)
	local legHeight = Tables.SurfaceHeight - s(CLOTH_THICKNESS + APRON_DEPTH)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(
				"Leg",
				Vector3.new(s(LEG_SIZE), legHeight, s(LEG_SIZE)),
				origin * CFrame.new(sx * s(hl), legHeight / 2, sz * s(hw)),
				WOOD_COLOR,
				Enum.Material.Wood,
				model
			)
		end
	end

	-- Play prompt at the head end.
	local promptAttachment = Instance.new("Attachment")
	promptAttachment.Name = "PromptAttachment"
	promptAttachment.Position = Vector3.new(-s(hl + CUSHION_WIDTH + FRAME_WIDTH), s(FRAME_TOP), 0)
	promptAttachment.Parent = cloth
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PlayPrompt"
	prompt:SetAttribute("ActionKey", "PROMPT_PLAY") -- localized on the client
	prompt:SetAttribute("ObjectKey", "PROMPT_TABLE")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = promptAttachment

	local seatPosition = TableSpace.toWorld(surface, -(hl + CUSHION_WIDTH + FRAME_WIDTH + 0.35), 0, 0)
	seatPosition = Vector3.new(seatPosition.X, origin.Y + 3, seatPosition.Z)
	local seat = CFrame.lookAt(seatPosition, seatPosition + surface.XVector)

	return { model = model, surface = surface, seat = seat }
end

return TableBuilder
