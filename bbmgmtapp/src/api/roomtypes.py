from flask import Blueprint, jsonify, abort 
from ..models import db , RoomTypes

bp = Blueprint('RoomTypes', __name__, url_prefix='/roomtypes')

#_________________________GET____________________________#
@bp.route('', methods=['GET'])    # Decorator takes path and list of HTTP verbs
def index():
    room_types = RoomTypes.query.all()    # ORM performs SELECT query
    result = []
    for u in room_types:
        result.append(u.serialize())   # Build list of Users as dictionaries
    return jsonify(result)             # Returns a JSON response

@bp.route('/<int:room_type_id>', methods=['GET'])
def show(room_type_id: int):
    u = RoomTypes.query.get(room_type_id)
    if u is None:
        return abort(404, 'Room type not found.')
    return jsonify(u.serialize())

@bp.route('/<int:room_type_id>/rateschedules', methods=['GET'])
def likes(room_type_id: int):
    u = RoomTypes.query.get(room_type_id)
    if u is None:
        return abort(404, 'Room type not found.')
    # Check if amenities exist
    if u.room_type_rates is None:
        return abort(404, 'No rate schedules found for this room.')
    # Return amenities    
    result = []
    for s in u.room_type_rates:
        result.append(s.serialize())
    return jsonify(result)
