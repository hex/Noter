# ABOUTME: Generates and signs the "Send to Noter" shortcut that drops shared items into iCloud Drive/Noter/Inbox.
# ABOUTME: Text, URLs and web pages become a JSON drop; images, PDFs and other files are saved beside it.

import plistlib, subprocess, uuid, pathlib

def uid():
    return str(uuid.uuid4()).upper()

def out(action_uid, name="Output"):
    """A magic-variable reference to another action's output."""
    return {"Type": "ActionOutput", "OutputUUID": action_uid, "OutputName": name}

def var(name):
    return {"Type": "Variable", "VariableName": name}

EXTENSION_INPUT = {"Type": "ExtensionInput"}
STAMP = {"Type": "CurrentDate", "Aggrandizements": [
    {"Type": "WFDateFormatVariableAggrandizement", "WFDateFormatStyle": "Custom", "WFDateFormat": "yyyyMMdd-HHmmss"}]}

def attachment(ref):
    return {"Value": ref, "WFSerializationType": "WFTextTokenAttachment"}

def token(refs, text):
    """A text field where each {} is replaced by the next reference."""
    by_range, rendered, pos = {}, "", 0
    pieces = text.split("{}")
    for i, piece in enumerate(pieces):
        rendered += piece
        pos += len(piece)
        if i < len(pieces) - 1:
            by_range[f"{{{pos}, 1}}"] = refs[i]
            rendered += "￼"
            pos += 1
    return {"Value": {"string": rendered, "attachmentsByRange": by_range}, "WFSerializationType": "WFTextTokenString"}

def action(identifier, action_uid=None, **params):
    params["UUID"] = action_uid or uid()
    return {"WFWorkflowActionIdentifier": identifier, "WFWorkflowActionParameters": params}

IS, IS_NOT = 4, 5

def if_block(subject_ref, condition, value, group):
    """Open an If block on a text subject; close it with end_if(group)."""
    return {"WFWorkflowActionIdentifier": "is.workflow.actions.conditional", "WFWorkflowActionParameters": {
        "GroupingIdentifier": group, "WFControlFlowMode": 0, "WFCondition": condition,
        "WFInput": {"Type": "Variable", "Variable": attachment(subject_ref)},
        "WFConditionalActionString": value, "UUID": uid()}}

def end_if(group):
    return {"WFWorkflowActionIdentifier": "is.workflow.actions.conditional",
            "WFWorkflowActionParameters": {"GroupingIdentifier": group, "WFControlFlowMode": 2, "UUID": uid()}}

kind, name, fileref, title, selection, urls, text_in, dictionary, json_text = (uid() for _ in range(9))
groups = [uid(), uid(), uid(), uid()]

actions = [
    action("is.workflow.actions.getitemtype", kind, WFInput=attachment(EXTENSION_INPUT)),

    # Files: anything that is not text, a URL, or a web page is saved next to the drop.
    if_block(out(kind), IS_NOT, "Text", groups[0]),
    if_block(out(kind), IS_NOT, "URL", groups[1]),
    if_block(out(kind), IS_NOT, "Safari web page", groups[2]),
    action("is.workflow.actions.getitemname", name, WFInput=attachment(EXTENSION_INPUT)),
    action("is.workflow.actions.gettext", fileref, WFTextActionText=token([STAMP, out(name)], "{}-{}")),
    action("is.workflow.actions.setvariable", WFVariableName="fileRef", WFInput=attachment(out(fileref))),
    action("is.workflow.actions.documentpicker.save", WFInput=attachment(EXTENSION_INPUT),
           WFAskWhereToSave=False, WFSaveFileOverwrite=True,
           WFFileDestinationPath=token([var("fileRef")], "/Noter/Inbox/{}")),
    end_if(groups[2]), end_if(groups[1]), end_if(groups[0]),

    # Page details exist only for Safari web pages; the action fails outright on other input.
    if_block(out(kind), IS, "Safari web page", groups[3]),
    action("is.workflow.actions.properties.safariwebpage", title, WFInput=attachment(EXTENSION_INPUT),
           WFContentItemPropertyName="Name"),
    action("is.workflow.actions.setvariable", WFVariableName="pageTitle", WFInput=attachment(out(title))),
    action("is.workflow.actions.properties.safariwebpage", selection, WFInput=attachment(EXTENSION_INPUT),
           WFContentItemPropertyName="Page Selection"),
    action("is.workflow.actions.setvariable", WFVariableName="pageSelection", WFInput=attachment(out(selection))),
    end_if(groups[3]),

    action("is.workflow.actions.detect.link", urls, WFInput=attachment(EXTENSION_INPUT)),
    action("is.workflow.actions.detect.text", text_in, WFInput=attachment(EXTENSION_INPUT)),
    action("is.workflow.actions.dictionary", dictionary,
           WFItems={"Value": {"WFDictionaryFieldValueItems": [
               {"WFItemType": 0, "WFKey": token([], "url"), "WFValue": token([out(urls)], "{}")},
               {"WFItemType": 0, "WFKey": token([], "title"), "WFValue": token([var("pageTitle")], "{}")},
               {"WFItemType": 0, "WFKey": token([], "text"), "WFValue": token([var("pageSelection")], "{}")},
               {"WFItemType": 0, "WFKey": token([], "input"), "WFValue": token([out(text_in)], "{}")},
               {"WFItemType": 0, "WFKey": token([], "file"), "WFValue": token([var("fileRef")], "{}")},
           ]}, "WFSerializationType": "WFDictionaryFieldValue"}),
    action("is.workflow.actions.detect.text", json_text, WFInput=attachment(out(dictionary))),
    action("is.workflow.actions.documentpicker.save", WFInput=attachment(out(json_text)),
           WFAskWhereToSave=False, WFSaveFileOverwrite=True,
           WFFileDestinationPath=token([STAMP], "/Noter/Inbox/{}.json")),
]

workflow = {
    "WFWorkflowClientVersion": "2607.1.3",
    "WFWorkflowMinimumClientVersion": 900,
    "WFWorkflowMinimumClientVersionString": "900",
    "WFWorkflowHasShortcutInputVariables": True,
    "WFWorkflowHasOutputFallback": False,
    "WFWorkflowIcon": {"WFWorkflowIconStartColor": 463140863, "WFWorkflowIconGlyphNumber": 59511},
    "WFWorkflowInputContentItemClasses": [
        "WFURLContentItem", "WFSafariWebPageContentItem", "WFStringContentItem", "WFArticleContentItem",
        "WFRichTextContentItem", "WFImageContentItem", "WFPDFContentItem", "WFGenericFileContentItem",
        "WFAVAssetContentItem", "WFContactContentItem", "WFLocationContentItem",
    ],
    "WFWorkflowTypes": ["ActionExtension"],
    "WFWorkflowImportQuestions": [],
    "WFWorkflowActions": actions,
}

here = pathlib.Path(__file__).parent
unsigned = here / "Send to Noter.unsigned.shortcut"
signed = here / "Send to Noter.shortcut"
with open(unsigned, "wb") as f:
    plistlib.dump(workflow, f)
subprocess.run(["shortcuts", "sign", "--input", str(unsigned), "--output", str(signed)], check=True)
unsigned.unlink()
print(signed)
