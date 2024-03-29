#!/usr/bin/env python3
from flask import Flask, request, send_file, make_response
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
    return ''.join(c for c in s if str.isalnum(c) or c == ' ' or c == '-')

def filter_latex_multiline(s):
    return (
        ''.join(c for c in s if str.isalnum(c) or c in ' -%!.()=+\n')
        .replace("%", "\\%")
        .replace("\n", " \\\\\n")
    )

def gen_template(name, args):
    global temp_store
    items = []
    name = filter_alpha(name)
    for k, v in args.items():
        if not k.startswith("my"): continue
        if not v: continue #empty

        san_k = filter_alpha(k)
        if san_k.startswith("mystr"):
            items.append((san_k, filter_latex_multiline(v)))
        else:
            items.append((san_k, filter_alnum(v)))
    items.sort()

    print(f"New request: {name} / {items}")
    latex = ("% {name}\n\\documentclass{article}\n" +
        "\\def\\assetpath{{" + str(os.getcwd()) + "/}}\n" +
        "\n".join(f"\\def \\{k} {{{v}}}" for k,v in items) + "\n")
    m = hashlib.sha256()
    m.update(latex.encode('utf-8'))
    filename = os.path.join(temp_store, f"{m.hexdigest()}.pdf")
    if os.path.isfile(filename):
        print(f"Sending cached response {filename}")
        return filename

    with tempfile.TemporaryDirectory() as tmp:
        print(f"Compiling... temp dir: {tmp}")
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

        if not os.path.isdir(temp_store):
            # For some reason sometimes `temp_store` just disappears. This
            # should be debugged properly sometime, but for now let's just
            # handle this gracefully and recreate it.
            temp_store = tempfile.mkdtemp()
        os.rename(os.path.join(tmp, "latex.pdf"), filename)

    print(f"Compilation completed of {filename}, sending...")
    return filename

@app.after_request
def after_request(response):
    if str(request.path).startswith('/latex') and response.status_code == 200:
        response.headers['Content-Disposition'] = ('attachment; ' +
            'filename="result.pdf"')
    return response

@app.route('/')
def befott():
    return send_file("./befott.html")

@app.route('/schbeviteli')
def schbeviteli():
    return send_file("./schbeviteli.html")

@app.route('/style.css')
def style_css():
    return send_file("./style.css")

@app.route('/latex')
def template():
    template_name = request.args.get("name")
    fn = gen_template(template_name, request.args)
    if fn is None:
        return make_response("An error occurred", 500)
    return send_file(fn)

if __name__ == '__main__':
    app.run(debug=True)
