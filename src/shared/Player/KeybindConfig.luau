local KeybindConfig = {
    ORDER = {"Fire", "Special", "Ultimate", "Summon", "Command", "Reload", "EndTurn"},

    DisplayNames = {
        Fire = "FIRE SHOTGUN",
        Special = "SPECIAL",
        Ultimate = "ULTIMATE",
        Summon = "SUMMON",
        Command = "COMMAND",
        Reload = "RELOAD",
        EndTurn = "END TURN",
    },

    -- Enum.KeyCode names
    Defaults = {
        Fire = "One",
        Special = "E",
        Ultimate = "Three",
        Summon = "Four",
        Command = "Five",
        Reload = "R",
        EndTurn = "X",
    },

    -- Short badge labels for keys whose names are too long
    KeyLabels = {
        Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
        Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
        LeftShift = "LSHFT", RightShift = "RSHFT",
        LeftControl = "LCTRL", RightControl = "RCTRL",
        LeftAlt = "LALT", RightAlt = "RALT",
        Space = "SPACE", Tab = "TAB", Return = "ENTER", Backspace = "BKSP",
        CapsLock = "CAPS", Backquote = "`", Minus = "-", Equals = "=",
        LeftBracket = "[", RightBracket = "]", Semicolon = ";", Quote = "'",
        Comma = ",", Period = ".", Slash = "/", BackSlash = "\\",
        Up = "UP", Down = "DOWN", Left = "LEFT", Right = "RIGHT",
    },

    -- Keys that can't be bound
    RESERVED = {"Escape", "Unknown"},
}

return KeybindConfig
