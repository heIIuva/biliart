--!strict
-- Loads mesh templates (Config.Assets.Meshes) into ReplicatedStorage.Assets for clients to clone.
-- MeshPart.MeshId cannot be set by scripts or synced by Rojo, so meshes come in as uploaded models.

local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Assets = require(ReplicatedStorage.Shared.Config.Assets)

local MeshService = {}

local function load(id: number): MeshPart?
	local ok, result = pcall(InsertService.LoadAsset, InsertService, id)
	if not ok then
		warn(`[MeshService] model {id} did not load: {result}`)
		return nil
	end
	local mesh = (result :: Model):FindFirstChildWhichIsA("MeshPart", true)
	if not mesh then
		warn(`[MeshService] model {id} has no MeshPart`)
	end
	return mesh
end

function MeshService:Init()
	local folder = Instance.new("Folder")
	folder.Name = "Assets"
	for name, id in Assets.Meshes do
		local mesh = load(id)
		if mesh then
			mesh.Name = name
			mesh.Parent = folder
		end
	end
	folder.Parent = ReplicatedStorage
end

return MeshService
