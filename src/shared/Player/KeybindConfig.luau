local KeybindConfig = {
    ORDER = {"Fire", "Special", "Ultimate", "Summon", "Command", "Reload", "EndTurn"},

    DisplayNames = {
        Fire = "Fire Shotgun",
        Special = "Special",
        Ultimate = "Ultimate",
        Summon = "Summon",
        Command = "Command",
        Reload = "Reload",
        EndTurn = "End Turn",
    },

    -- Enum.KeyCode names
    Defaults = {
        Fire = "Q",
        Special = "E",
        Ultimate = "F",
        Summon = "W",
        Command = "A",
        Reload = "R",
        EndTurn = "X",
    },

    -- Short badge labels for keys whose names are too long
    KeyLabels = {
        Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
        Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
        LeftShift = "LShift", RightShift = "RShift",
        LeftControl = "LCtrl", RightControl = "RCtrl",
        LeftAlt = "LAlt", RightAlt = "RAlt",
        Space = "Space", Tab = "Tab", Return = "Enter", Backspace = "Bksp",
        CapsLock = "Caps", Backquote = "`", Minus = "-", Equals = "=",
        LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'",
        Comma = ",", Period = ".", Slash = "/", BackSlash = "\\",
        Up = "Up", Down = "Down", Left = "Left", Right = "Right",
    },

    -- Keys that can't be bound
    RESERVED = {"Escape", "Unknown"},
}

return KeybindConfig
