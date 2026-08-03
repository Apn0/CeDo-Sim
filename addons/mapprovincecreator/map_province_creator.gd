@icon("res://addons/mapprovincecreator/MapProvinceIcon.svg")

## Extending from [Area2D], this node aims to make Province creation for map games simple and easy. The Map Province Creator can be used to create prototypes for map games, or even actually full games. For more information about the node's functions, methods, and properties, see below.
## [br] [br]
## Children (that get added through code) include: [br]
## [u]ProvincePolygon[/u] ([Polygon2D]),
## [br]
## [u]ProvinceCol[/u] ([CollisionPolygon2D])
## [br]
## [u]PopupScreen[/u] ([PopupMenu])
## [br] [br]
## [i]Note:[/i] [br]
## When adding the MapProvinceCreator node to a scene, there's a warning next to it, telling you to define a collision. Since the collision gets added via code, this warning message can be ignored safely.
## [br]
## Also, when looking at this documentation and see '[i]Code-specific variable[/i]', that means that the code is intended to be used in the code only. Theoretically, you could use the variables externally, but there should be no need.
class_name MapProvinceCreator
extends Area2D

enum ProvinceResources {
	NULL,
	Wood,
	Iron,
	Gold
}

# The reason why I add the 'as [Node]' keyword (in later code, specifically for adding new instances of nodes) is because you then aqquire code completion because the editor then notices which node's properties you are referring to.
# If you're modifying the code, it can come in quite handy, but if you're simply looking at the code, treat it as if it weren't there to begin with.

#region Class Variables
## The exported category for the 'Province General'.
@export_category("Province General")
## The province name. Will show up in the popup.
@export var province_name: String
## The vertices of the [b]Polygon Mesh[/b] and [b]Collision[/b].
## Using code, the MapProvinceCreator node automatically assigns the [i]vertices[/i] to the MapProvinceCreator's nodes, which include [u]ProvincePolygon[/u] (Polygon2D) and [u]ProvinceCol[/u] (CollisionPolygon2D).
@export var province_vertices: PackedVector2Array
## The user-defined color of the province.
@export var province_color: Color = Color.DEEP_SKY_BLUE

## The exported category for the 'Border Drawing'.
@export_category("Border Drawing")
## If you want borders (lines surrounding the province) then it should be [code]true[/code]. If not, then it should be [code]false[/code].
@export var borders: bool = true
## How wide you want the province border to be.
@export var border_width: float = 5.0
## With this variable you can choose the province color.
@export var border_color: Color = Color.BLACK
## With this, you can choose if you want the border color to be the same as the province_color but a little bit darker. If you want that, this should be [code]true[/code].
@export var match_province_color: bool = true
## The variable makes the border have antialiasing or not.
@export var border_antialiasing: bool = true

## The exported category for the in-game properties, like Resources, 
@export_category("Province In-Game Properties")
## The resource that the province has in-game. It has no current optical effect on the province. Note that the Godot [Resource] has nothing to do with the province resources, as one is a class which lots of nodes decend and inherit from and the other is a simple enum.
@export var province_resource: ProvinceResources
## The exported variable that allows you to decide if you don't want the province worth (or you do) to shwo up in the popup menu.
@export var province_worth_enable: bool
## The province's worth. It can be used in games that include the mechanic of buying and selling provinces.
@export var province_worth_cents: int = 0.0

# Sets the variables that will be added as children nodes to the MapProvinceCreator in the '_ready()' function.
## The variable which will, later in the code, have a unique instance of the node.
var ProvincePolygon: Polygon2D
## The variable which will, later in the code, have a unique instance of the node.
var ProvinceCol: CollisionPolygon2D
## The variable which will, later in the code, have a unique instance of the node.
var PopupScreen: PopupMenu


## [i]Code-specific variable[/i]. Only used to detect if the mouse is hovering over the province or not. If it's true, the mouse is hovering over the province. If it's false, the mouse is somewhere else.
var is_province_clickable: bool
## The variable that will be [b]true[/b] if the province is selected and [b]false[/b] if it isn't. That's it.
var is_province_selected: bool

## [i]Code-specific variable[/i]. It will be assigned the user-defined color. The reason for this is that the code will have a concrete color to change back to.
var ORIGINAL_COLOR: Color
## [i]Code-specific variable[/i]. It is used to pre-define a darkened version of the original color to be assigned to when the province has been selected.
var DARKENED_COLOR: Color
#endregion Class Variables

#region Vertices Set / Get Functions
## Use this function to assign new vertices to the province. The function automatically assigns the given PackedVector2Array ([param new_vertices]) to the MapProvince's Children (see Class description for information about its children).
func set_vertices(new_vertices: PackedVector2Array):
	# Duplicates the polygon's PackedVector2Arrays (that hold their vertices' positions) and assigns them to variables.
	var polymesh_vec2_array = ProvincePolygon.polygon.duplicate()
	var polycol_vec2_array = ProvinceCol.polygon.duplicate()
	
	# Assigns the duplicated PackedVector2Arrays to new PackedVector2Arrays
	polymesh_vec2_array = new_vertices
	polycol_vec2_array = new_vertices
	
	# Sets the vertices of the collision and mesh to the user-defined 'vertices'.
	ProvincePolygon.set_polygon(polymesh_vec2_array)
	ProvinceCol.set_polygon(polycol_vec2_array)
	
	province_vertices = new_vertices
	
	if borders:
		# Redraw the borders.
		redraw_borders()

## Returns the set vertices as a PackedVector2Array.
func get_vertices() -> PackedVector2Array:
	return province_vertices
#endregion Vertices Set / Get Functions

#region Color Management
## Used to darken the current mesh.
func darken_mesh() -> void:
	ProvincePolygon.set_color(DARKENED_COLOR)

## Used to lighten the current mesh.
func lighten_mesh() -> void:
	ProvincePolygon.set_color(ORIGINAL_COLOR)

## Used to set the new province's color. No extra code needed, you just enter the paramter [parameter new_color] and then there you go!
func set_province_color(new_color: Color) -> void:
	province_color = new_color
	ORIGINAL_COLOR = new_color
	DARKENED_COLOR = new_color.darkened(0.2)
	ProvincePolygon.set_color(ORIGINAL_COLOR)
	if borders:
		# Redraw the borders.
		redraw_borders()
	

## Used to get the current province color that is currently assigned to the Polygon2D child.
func get_province_color() -> Color:
	return ORIGINAL_COLOR
#endregion Color Management

#region Popup Management
## The function that opens the popup. Used when the left mouse button is registered.
func open_popup() -> void:
	# Makes it visible.
	(PopupScreen as PopupMenu).visible = true
	# Sets the correct position of the Popup.
	(PopupScreen as PopupMenu).position = get_viewport_rect().size - Vector2(PopupScreen.size)
	
## The function that closes and the popup. Used when the user-defined mouse button is registered.
func close_popup() -> void:
	# Makes it invisible.
	(PopupScreen as PopupMenu).visible = false
	# Sets the correct position of the Popup.
	(PopupScreen as PopupMenu).position = get_viewport_rect().size - Vector2(PopupScreen.size)
#endregion Popup Management

#region Border Drawing
## Redraw the province borders by simply calling the '_draw()' function again.
## [br]
## This function must be called, if you want to change the [member province_color] too, AND have the [member match_province_color] on, [b]AFTER[/b] you change the province_color, because the '_draw()' function uses the current province_color to change the borders.
func redraw_borders() -> void:
	queue_redraw()

# Draw (or redraw) the province borders.
func _draw() -> void:
	for vertex in len(province_vertices):
		if match_province_color:
			draw_line(province_vertices[vertex-1], province_vertices[vertex], province_color.darkened(0.3), border_width, border_antialiasing)
		elif !match_province_color:
			draw_line(province_vertices[vertex-1], province_vertices[vertex], province_color.darkened(0.3), border_width, border_antialiasing)
#endregion Border Drawing

func _ready() -> void:
	#region Adding Children via Code
	# Sets new child nodes.
	ProvincePolygon = Polygon2D.new()
	ProvinceCol = CollisionPolygon2D.new()
	
	PopupScreen = PopupMenu.new()
	
	# Adds the new nodes as children to the MapProvinceCreator (Area2D).
	add_child(ProvincePolygon)
	add_child(ProvinceCol)
	
	add_child(PopupScreen)
	# Managing the popupscreen's settings below.
	PopupScreen.always_on_top = true
	PopupScreen.hide_on_item_selection = false
	#endregion Adding Children via Code
	
	#region Other
	# Connect the appropriate signals (mouse_entered, mouse_exited to their corresponding methods / functions - "_on_mouse_entered" and "_on_mouse_exited") via code.
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	
	# Uses the defined function above to set the vertices of the province to the user's preference.
	set_vertices(province_vertices)
	
	# Assigns the color (exported variable) to the color of the ProvincePolygon (Polygon2D).
	ProvincePolygon.set_color(province_color)
	
	# Setting the first item to be the name label.
	(PopupScreen as PopupMenu).add_item("%s" % province_name)
	
	if province_worth_enable == true:
		var province_worth_eur_dol = (float(province_worth_cents) / 100.0) # Measures the rough worth of the province in Euro by dividing th cents by 100.
		# Setting the second item to be the worth label.
		(PopupScreen as PopupMenu).add_item("Province Worth: %s" % province_worth_eur_dol)
	else:
		pass
	
	if province_resource != ProvinceResources.NULL:
		# Setting the third item to be the resourcew label.
		(PopupScreen as PopupMenu).add_item("Province Resource: %s" % ProvinceResources.find_key(province_resource))

	# Setting the variables to be the orighinal (user-defined) color and the darkened version for non-faulty code. (Instead of lightening or darkening the CURRENTLY USED color, it's better to SET the color to pre-defined colors that alter based on user preference.)
	ORIGINAL_COLOR = province_color
	DARKENED_COLOR = province_color.darkened(0.2)
	#endregion Other

#region Province Selection
# Checks if the mouse has entered the polygon. If it has, then make the polygon clickable.
func _on_mouse_entered() -> void:
	is_province_clickable = true
	
# Checks if the mouse has exited the polygon. If it has, then make the polygon NOT clickable.
func _on_mouse_exited() -> void:
	is_province_clickable = false
	
func _unhandled_input(event: InputEvent) -> void: # Gets called when the user presses something.
	if event is InputEventMouseButton: # If the event is a mouse button press and the province is clickable,
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and (is_province_clickable):
			if !is_province_selected:
				darken_mesh()
				open_popup()
				is_province_selected = true
			elif is_province_selected:
				lighten_mesh()
				close_popup()
				is_province_selected = false
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed and (not is_province_clickable):
			lighten_mesh()
			is_province_selected = false
#endregion Province Selection
