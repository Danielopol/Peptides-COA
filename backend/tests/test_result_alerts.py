"""Unit tests for null-result content alerts ('Not Detected' / 'n/a')."""
from __future__ import annotations
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.checks import result_alerts  # noqa: E402


def test_vision_quantity_not_detected_is_critical():
    alerts = result_alerts.from_vision([
        {"analysis": "Quantity", "method": "HPLC-UV/VIS", "result": "Not Detected"},
        {"analysis": "Chromatographic Purity", "method": "HPLC-UV/VIS", "result": "n/a"},
    ])
    by_cat = {a["category"]: a for a in alerts}
    assert by_cat["quantity"]["kind"] == "not_detected"
    assert by_cat["quantity"]["severity"] == "critical"
    assert by_cat["purity"]["kind"] == "not_applicable"
    assert by_cat["purity"]["severity"] == "warning"


def test_vision_real_values_produce_no_alert():
    alerts = result_alerts.from_vision([
        {"analysis": "Purity", "method": "HPLC", "result": "99.1%"},
        {"analysis": "Assay", "method": "HPLC", "result": "5.2 mg"},
    ])
    assert alerts == []


def test_vision_ignores_null_on_non_headline_rows():
    # an empty 'Notes'/'Appearance' cell must not raise a content alert
    alerts = result_alerts.from_vision([
        {"analysis": "Appearance", "method": "", "result": "n/a"},
    ])
    assert alerts == []


def test_below_loq_and_nd_variants_detected():
    for token in ("ND", "below LOQ", "< LOD", "undetectable"):
        alerts = result_alerts.from_vision([
            {"analysis": "Assay / Content", "method": "HPLC", "result": token},
        ])
        assert alerts and alerts[0]["kind"] == "not_detected", token


def test_text_path_same_line_quantity():
    txt = "Analysis Method Result\nQuantity HPLC-UV/VIS Not Detected\n"
    alerts = result_alerts.from_text(txt)
    assert any(a["category"] == "quantity" and a["kind"] == "not_detected" for a in alerts)


def test_na_only_when_whole_cell():
    # "n/a" as the whole result -> alert; embedded in a longer value -> not
    assert result_alerts.from_vision(
        [{"analysis": "Purity", "result": "n/a"}])[0]["kind"] == "not_applicable"
    assert result_alerts.from_vision(
        [{"analysis": "Purity", "result": "98% (na batch ref AB/123 not applicable here too)"}]) == []


if __name__ == "__main__":
    fns = [f for n, f in sorted(globals().items()) if n.startswith("test_")]
    for fn in fns:
        fn(); print(f"PASS {fn.__name__}")
    print(f"\n{len(fns)} passed")
