extends Node

# Global "signal bus".

signal ant_selected(ant: Node2D)
signal ant_deselected(ant: Node2D)
signal action_requested(ant: Node2D, action: Resource)
