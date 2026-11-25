-- Enemies listed in the Armory's Index, in card order
-- Health, damage and movement are read from PieceConfig, PieceRules and ShotgunConfig, so only the text lives here
-- Piece is the sprite and rules to use; Outfit dresses a King in a class; Region ties a King to the campaign region he rules
local IndexConfig = {
    -- Card slots shown in the grid; empty ones wait for enemies added later
    SLOTS = 20,

    Entries = {
        {Id = "Pawn", Name = "Pawn", Piece = "Pawn", Where = "Every battle",
            Notes = "Steps one tile toward you and strikes diagonally. Becomes a Knight, Bishop or Rook if it reaches your back row."},
        {Id = "Knight", Name = "Knight", Piece = "Knight", Where = "Every battle",
            Notes = "Jumps in an L shape, straight over other pieces."},
        {Id = "Bishop", Name = "Bishop", Piece = "Bishop", Where = "Every battle",
            Notes = "Slides any distance diagonally until something is in the way."},
        {Id = "Rook", Name = "Rook", Piece = "Rook", Where = "Every battle",
            Notes = "Slides any distance in straight lines until something is in the way."},
        {Id = "Queen", Name = "Queen", Piece = "Queen", Where = "Queen and King fights",
            Notes = "Slides any distance in any direction. Every region's Queen guards the road to its King."},
        {Id = "FallenKnight", Name = "Fallen Knight", Piece = "FallenKnight", Where = "Mystery: Fallen Knight",
            Notes = "Moves and strikes like both a King and a Knight. Still loyal to his fallen King."},
        {Id = "FallenPawn", Name = "Fallen Pawn", Piece = "FallenPawn", Where = "Mystery: Fallen Knight",
            Notes = "Guards the Fallen Knight's throne. Fights like a Pawn."},
        {Id = "MonarchKing", Name = "Monarch King", Piece = "King", Outfit = "Monarch", Region = "Training"},
        {Id = "HunterKing", Name = "Hunter King", Piece = "King", Outfit = "Hunter", Region = "Forest"},
        {Id = "BanditKing", Name = "Bandit King", Piece = "King", Outfit = "Outlaw", Region = "Cliffside"},
        {Id = "GunslingerKing", Name = "Gunslinger King", Piece = "King", Outfit = "Gunslinger", Region = "Outskirts"},
        {Id = "ReaperKing", Name = "Reaper King", Piece = "King", Outfit = "Reaper", Region = "Gravehollow"},
    },
}

return IndexConfig
