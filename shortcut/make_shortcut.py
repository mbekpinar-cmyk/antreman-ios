"""Antrenman Saglik kestirmesini (.shortcut, imzasiz plist) uretir.
Apple Health'ten dunku uyku, HRV, dinlenik nabiz ve solunumu okuyup
antrenman://health?d=... adresiyle Antrenman uygulamasina gonderir.
Imzalama GitHub'in macOS makinesinde `shortcuts sign` ile yapilir."""
import plistlib, sys, uuid

OBJ = "￼"
HOUR, DAY = 32, 16          # NSCalendarUnit
IN_THE_LAST = 1001
IS, IS_NOT = 4, 5

actions = []

def act(ident, params):
    actions.append({"WFWorkflowActionIdentifier": ident, "WFWorkflowActionParameters": params})

def find(type_name, amount, unit, extra=()):
    templates = [
        {"Bounded": True, "Operator": IS, "Property": "Type", "Removable": False,
         "Values": {"Enumeration": {"Value": type_name, "WFSerializationType": "WFStringSubstitutableState"}}},
        {"Bounded": True, "Operator": IN_THE_LAST, "Property": "Start Date", "Removable": True,
         "Values": {"Number": amount, "Unit": unit}},
    ]
    for prop, op, val in extra:
        templates.append({"Bounded": True, "Operator": op, "Property": prop, "Removable": True,
                          "Values": {"Enumeration": {"Value": val, "WFSerializationType": "WFStringSubstitutableState"}}})
    act("is.workflow.actions.filter.health.quantity", {
        "UUID": str(uuid.uuid4()).upper(),
        "WFContentItemFilter": {"Value": {"WFActionParameterFilterPrefix": 1,
                                          "WFContentPredicateBoundedDate": False,
                                          "WFActionParameterFilterTemplates": templates},
                                "WFSerializationType": "WFContentPredicateTableTemplate"},
        "WFContentItemLimitEnabled": False,
    })

def details(prop):
    act("is.workflow.actions.properties.health.quantity",
        {"UUID": str(uuid.uuid4()).upper(), "WFContentItemPropertyName": prop})

def stats(op):
    u = str(uuid.uuid4()).upper()
    act("is.workflow.actions.statistics", {"UUID": u, "WFStatisticsOperation": op})
    return u

def token_string(parts):
    """parts: list of str or (uuid, name) -> WFTextTokenString"""
    s, att = "", {}
    for p in parts:
        if isinstance(p, tuple):
            att["{%d, 1}" % len(s)] = {"OutputUUID": p[0], "OutputName": p[1], "Type": "ActionOutput"}
            s += OBJ
        else:
            s += p
    return {"Value": {"string": s, "attachmentsByRange": att}, "WFSerializationType": "WFTextTokenString"}

# 1) uyku
find("Sleep Analysis", 16, HOUR, [("Value", IS_NOT, "In Bed"), ("Value", IS_NOT, "Awake")])
details("Duration")
u_sleep = stats("Sum")
# 2) HRV
find("Heart Rate Variability", 12, HOUR)
details("Value")
u_hrv = stats("Average")
# 3) dinlenik nabiz
find("Resting Heart Rate", 1, DAY)
details("Value")
u_rhr = stats("Average")
# 4) solunum
find("Respiratory Rate", 12, HOUR)
details("Value")
u_resp = stats("Average")
# 5) metin
u_text = str(uuid.uuid4()).upper()
act("is.workflow.actions.gettext", {"UUID": u_text, "WFTextActionText": token_string([
    "sleep=", (u_sleep, "Statistics"), "\nhrv=", (u_hrv, "Statistics"),
    "\nrhr=", (u_rhr, "Statistics"), "\nresp=", (u_resp, "Statistics")])})
u_enc = str(uuid.uuid4()).upper()
act("is.workflow.actions.urlencode", {"UUID": u_enc, "WFEncodeMode": "Encode",
                                      "WFInput": token_string([(u_text, "Text")])})
act("is.workflow.actions.openurl", {"WFInput": token_string(["antrenman://health?d=", (u_enc, "URL Encoded Text")])})

shortcut = {
    "WFWorkflowClientVersion": "2605.0.5",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowIcon": {"WFWorkflowIconStartColor": 4282601983, "WFWorkflowIconGlyphNumber": 59511},
    "WFWorkflowImportQuestions": [],
    "WFWorkflowInputContentItemClasses": [],
    "WFWorkflowOutputContentItemClasses": [],
    "WFWorkflowTypes": [],
    "WFQuickActionSurfaces": [],
    "WFWorkflowHasShortcutInputVariables": False,
    "WFWorkflowActions": actions,
}
out = sys.argv[1] if len(sys.argv) > 1 else "Antrenman Saglik.shortcut"
with open(out, "wb") as f:
    plistlib.dump(shortcut, f, fmt=plistlib.FMT_BINARY)
print("yazildi:", out, len(actions), "eylem")
