local ActionPanelController = require(script.Parent.Controllers.ActionPanelController)
local BoardController = require(script.Parent.Controllers.BoardController)
local InputController = require(script.Parent.Controllers.InputController)
local MenuController = require(script.Parent.Controllers.MenuController)

ActionPanelController.Init()
BoardController.Init(ActionPanelController)
InputController.Init(ActionPanelController)
MenuController.Init(BoardController.StartMatch)
