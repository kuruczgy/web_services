#!/usr/bin/env python3
from flask import Flask, request, send_file
import tempfile
import os
import subprocess
import hashlib

temp_store = tempfile.mkdtemp()

app = Flask(__name__)
application = app

def filter_alpha(s):
    return ''.join(c for c in s if str.isalpha(c) or c == ' ')
def filter_alnum(s):
    return ''.join(c for c in s if str.isalnum(c) or c == ' ')

def gen_template(name, args):
    items = []
    name = filter_alpha(name)
    for k, v in args.items():
        if not k.startswith("my"): continue
        if not v: continue #empty
        items.append((filter_alpha(k), filter_alnum(v)))
    items.sort()

    print(f"New request: {name} / {items}")
    latex = ("% {name}\n\\documentclass{article}\n" +
        "\n".join(f"\\def \\{k} {{{v}}}" for k,v in items) + "\n")
    m = hashlib.sha256()
    m.update(latex.encode('utf-8'))
    filename = os.path.join(temp_store, f"{m.hexdigest()}.pdf")
    if os.path.isfile(filename):
        print(f"Sending cached response {filename}")
        return filename

    tmp = tempfile.mkdtemp()
    print(f"Compiling... temp dir: {tmp}");
    with open(f"./{name}.tex", 'r') as f:
        latex += f.read()
    latex_file = os.path.join(tmp, "latex.tex")
    with open(latex_file, 'w') as f:
        f.write(latex)
    
    try:
        res = subprocess.call(['pdflatex', '-halt-on-error',
            '-output-directory', tmp, latex_file], timeout = 3)
        if res != 0: return None
    except Exception:
        return None

    os.rename(os.path.join(tmp, "latex.pdf"), filename)

    for f in os.listdir(tmp): os.remove(os.path.join(tmp, f))
    os.rmdir(tmp)

    print(f"Compilation completed of {filename}, sending...")
    return filename

@app.route('/')
def index():
    return send_file("./index.html")

@app.route('/latex')
def template():
    template_name = request.args.get("name")
    fn = gen_template(template_name, request.args)
    if fn is None:
        return "An error occurred"
    return send_file(fn)

if __name__ == '__main__':
    app.run(debug=True)
