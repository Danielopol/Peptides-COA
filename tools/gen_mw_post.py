"""Regenerate the peptide molecular weight blog post from the app's MW table.

The published article at /blog/peptide-molecular-weight-table/ must never drift
from Rules/peptide_mw_table.json, so its table is generated rather than written
by hand. Edit tools/mw_post_template.html for prose changes, then re-run:

    python tools/gen_mw_post.py

Writes web-landing/blog/peptide-molecular-weight-table/index.html.
"""
import io
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)

# Entries that are not research peptides but appear on the same COAs; footnoted
# in the article rather than silently listed as peptides.
NONPEP = {"MK-677", "5-Amino-1MQ", "NAD+", "Glutathione"}


def fmt(value, places):
    return "&mdash;" if value is None else "{:,.{p}f}".format(value, p=places)


def main():
    src = json.load(io.open(os.path.join(REPO, "Rules", "peptide_mw_table.json"), encoding="utf-8"))

    singles = sorted((p for p in src["peptides"] if not p.get("is_blend")),
                     key=lambda p: p["name"].lower())
    blends = [p for p in src["peptides"] if p.get("is_blend")]

    rows = []
    for p in singles:
        star = ' <span class="mw-note">*</span>' if p["name"] in NONPEP else ""
        rows.append(
            '<tr><td><strong>{name}</strong>{star}</td>'
            '<td class="mw-formula">{formula}</td>'
            "<td>{mono}</td><td>{avg}</td></tr>".format(
                name=p["name"], star=star, formula=p.get("formula") or "&mdash;",
                mono=fmt(p.get("monoisotopic_mass"), 4), avg=fmt(p.get("average_mass"), 2)))

    tol = src["tolerance_da"]
    trows = []
    for technique, value in tol["monoisotopic"].items():
        label = "Any (fallback)" if technique == "default" else technique
        trows.append("<tr><td>Monoisotopic</td><td>{}</td><td>&plusmn;{} Da</td></tr>".format(label, value))
    trows.append("<tr><td>Average</td><td>Any technique</td><td>&plusmn;{} Da</td></tr>".format(
        tol["average"]["default"]))

    blist = []
    for p in blends:
        note = (p.get("note") or p.get("source_note") or "").split(";")[0].strip().rstrip(".")
        blist.append("<li><strong>{}</strong> &mdash; {}.</li>".format(p["name"], note))

    template = io.open(os.path.join(HERE, "mw_post_template.html"), encoding="utf-8").read()
    out = (template
           .replace("__ROWS__", "\n              ".join(rows))
           .replace("__TROWS__", "\n              ".join(trows))
           .replace("__BLENDS__", "\n          ".join(blist)))

    for placeholder in ("__ROWS__", "__TROWS__", "__BLENDS__"):
        assert placeholder not in out, "placeholder {} left unreplaced".format(placeholder)

    dest = os.path.join(REPO, "web-landing", "blog", "peptide-molecular-weight-table", "index.html")
    if not os.path.isdir(os.path.dirname(dest)):
        os.makedirs(os.path.dirname(dest))
    with io.open(dest, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(out)

    print("MW table v{} ({}): {} compounds, {} tolerance rows, {} blends".format(
        src["version"], src["last_updated"], len(rows), len(trows), len(blist)))
    print("wrote", os.path.relpath(dest, REPO))


if __name__ == "__main__":
    main()
