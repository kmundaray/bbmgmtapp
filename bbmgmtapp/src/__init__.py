import os
from flask import Flask
from flask_migrate import Migrate

#from .api import roomtypes

# https://flask.palletsprojects.com/en/2.0.x/patterns/appfactories/


def create_app(test_config=None):
    app = Flask(__name__, instance_relative_config=True)
    app.config.from_mapping(
        SECRET_KEY='dev',
        SQLALCHEMY_DATABASE_URI='postgresql://postgres:bbmgmt4pp@localhost:5432/bbmgmtapp_db',
        SQLALCHEMY_TRACK_MODIFICATIONS=False,
        SQLALCHEMY_ECHO=True
    )

    if test_config is None:
        # load the instance config, if it exists, when not testing
        app.config.from_pyfile('config.py', silent=True)
    else:
        # load the test config if passed in
        app.config.from_mapping(test_config)

    # ensure the instance folder exists
    try:
        os.makedirs(app.instance_path)
    except OSError:
        pass

    from .models import db
    db.init_app(app)
    migrate = Migrate(app, db)

    from .api import guests, stays, rooms, roomtypes, transactions
    app.register_blueprint(guests.bp)
    app.register_blueprint(stays.bp)
    app.register_blueprint(rooms.bp)
    app.register_blueprint(roomtypes.bp)
    app.register_blueprint(transactions.bp)

    return app