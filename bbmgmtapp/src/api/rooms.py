from flask import Blueprint, jsonify, abort 
from ..models import db , Rooms

bp = Blueprint('Rooms', __name__, url_prefix='/rooms')

#_________________________GET____________________________#
@bp.route('', methods=['GET'])    # Decorator takes path and list of HTTP verbs
def index():
    guests = Rooms.query.all()    # ORM performs SELECT query
    result = []
    for u in guests:
        result.append(u.serialize())   # Build list of Users as dictionaries
    return jsonify(result)             # Returns a JSON response

@bp.route('/<room_number>', methods=['GET'])
def show(room_number: str):
    u = Rooms.query.get(room_number)
    if u is None:
        return abort(404, 'Room number not found.')
    return jsonify(u.serialize())

@bp.route('/<room_number>/amenities', methods=['GET'])
def likes(room_number: str):
    u = Rooms.query.get(room_number)
    if u is None:
        return abort(404, 'Room number not found.')
    # Check if amenities exist
    if u.rooms_amenities is None:
        return abort(404, 'No amenities found for this room.')
    # Return amenities    
    result = []
    for s in u.rooms_amenities:
        result.append(s.serialize())
    return jsonify(result)
