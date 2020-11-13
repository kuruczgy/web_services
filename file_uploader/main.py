#!/usr/bin/env python3
import sys, os, secrets
from flask import Flask, request, send_file, make_response
from werkzeug.utils import secure_filename

storage_dir = sys.argv[1]

app = Flask(__name__)
application = app

@app.route('/upload', methods=['POST'])
def upload():
    code = secrets.token_urlsafe(6)
    d = os.path.join(storage_dir, code)
    if os.path.exists(d):
        return make_response("failed", 500)
    os.mkdir(d)

    print(request.files)
    msg = ""
    for f in request.files.getlist('file'):
        fname = secure_filename(f.filename)
        name = os.path.join(code, fname)
        path = os.path.join(storage_dir, name)
        f.save(path)
        msg += f"saved: {name}\n"
    resp = make_response(msg, 200)
    resp.mimetype = "text/plain"
    return resp

@app.route('/')
def index():
    return send_file("./index.html")


if __name__ == '__main__':
    app.run(debug=True)
