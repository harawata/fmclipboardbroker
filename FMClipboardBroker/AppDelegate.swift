//
//  AppDelegate.swift
//  FMClipboardBroker
//
//  Created by Iwao AVE! on 2016/05/28.
//  Copyright © 2016年 Iwao AVE!. All rights reserved.
//  Licensed under Apache License v2.0
//

import Cocoa

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

	@IBOutlet weak var msgField: NSTextField!
	@IBOutlet weak var typeArrayController: NSArrayController!
	@IBOutlet weak var contentSelectionPopup: NSPopUpButton!
	@IBOutlet weak var savePathLabel: NSTextField!
	@IBOutlet weak var chooseImportPathButton: NSButton!
	@IBOutlet weak var chooseExportPathButton: NSButton!
	@IBOutlet weak var saveButton: NSButton!
	@IBOutlet weak var loadButton: NSButton!
	@IBOutlet weak var exportPathField: NSTextField!
	@IBOutlet weak var window: NSWindow!

	var settings: NSUserDefaults!

	let defaultFilename = "clipboard.xml"
	let exportPath = "exportPath"
	let openFileAfterExport = "openFileAfterExport"
	let importPath = "importPath"
	let useSamePath = "useSamePath"
	let contentSelection = "contentSelection"
	let autoDetect = "autoDetect"
	let readLayoutIn12Format = "readLayoutIn12Format"
	let lastAltPath = "lastAltPath"
	let prettyPrintXml = "prettyPrintXml"

	let types = ["XMTB", "XMFD", "XMSC", "XMSS", "XMLO", "XML2", "XMFN"]
	let typeLabels = [
		NSLocalizedString("table", comment: "Table"),
		NSLocalizedString("field", comment: "Field"),
		NSLocalizedString("script", comment: "Script"),
		NSLocalizedString("scriptStep", comment: "Script Step"),
		NSLocalizedString("layout", comment: "Layout"),
		NSLocalizedString("layout12", comment: "Layout (v12+)"),
		NSLocalizedString("customFunction", comment: "Custom Function")
	]

	func applicationDidFinishLaunching(aNotification: NSNotification) {
		settings = NSUserDefaults.standardUserDefaults()
		setupDefaults()
		typeArrayController.content = typeLabels
		typeArrayController.setSelectionIndex(settings.integerForKey(contentSelection))
		showMsg(nil)
	}

	func applicationWillTerminate(aNotification: NSNotification) {
		settings.setInteger(typeArrayController.selectionIndex, forKey: contentSelection)
	}

	@IBAction func onClickChooseImportPathFile(sender: AnyObject) {
		showOpenPanel({ (path: String!) -> Void in
			self.settings.setValue(path, forKey: self.importPath)
		})
	}

	@IBAction func onClickChooseExportFile(sender: AnyObject) {
		showSavePanel(false, function: { (path: String!) -> Void in
			self.settings.setValue(path, forKey: self.exportPath)
		})
	}

	@IBAction func saveAs(sender: AnyObject) {
		window.makeFirstResponder(nil)
		showSavePanel(true, function: saveClipboardToFile)
	}

	@IBAction func onClickSaveButton(sender: AnyObject) {
		window.makeFirstResponder(nil)
		if NSEvent.modifierFlags().contains(NSEventModifierFlags.ShiftKeyMask) {
			saveAs(sender)
		} else {
			saveClipboardToFile(settings.stringForKey(exportPath))
		}
	}

	func saveClipboardToFile(filePath: String?) {
		let pasteboard = NSPasteboard.generalPasteboard()
		if let uti = pasteboard.pasteboardItems?[0].types[0] {
			if let ostype = UTTypeCopyPreferredTagWithClass(uti, kUTTagClassOSType)?.takeRetainedValue() as String? {
				if let typeIdx = types.indexOf(ostype) {
					typeArrayController.setSelectionIndex(typeIdx)
					let xmlStr = pasteboard.stringForType(uti)
					if let path = filePath {
						var saved = false
						if settings.boolForKey(prettyPrintXml) {
							saved = savePrettyXml(path, xmlStr: xmlStr)
						} else {
							saved = saveRawXml(path, xmlStr: xmlStr)
						}
						if saved && settings.boolForKey(openFileAfterExport) {
							NSWorkspace.sharedWorkspace().openFile(path)
						}
					} else {
						showMsg(NSLocalizedString("missingExportPath", comment: "Export file path must be set"))
					}
				} else {
					showMsg(NSLocalizedString("unsupportedClipboardType", comment: "Unsupported clipboard type"))
				}
			}
		}
	}

	func saveRawXml(path: String!, xmlStr: String?) -> Bool {
		do {
			try xmlStr?.writeToFile(path, atomically: true, encoding: NSUTF8StringEncoding)
			return true
		} catch {
			showMsg(NSLocalizedString("failedToExportXmlStr", comment: "Failed to write XML string to the file."))
		}
		return false
	}

	func savePrettyXml(path: String!, xmlStr: String?) -> Bool {
		if let str = xmlStr {
			do {
				let xml = try NSXMLDocument(XMLString: str, options: NSXMLNodePrettyPrint)
				let xmlData = xml.XMLDataWithOptions(NSXMLNodePrettyPrint)
				return xmlData.writeToFile(path, atomically: true)
			} catch {
				showMsg(NSLocalizedString("parseErrorInLoadedXml", comment: "Failed to parse XML string copied from FM."))
			}
		}
		return false
	}

	@IBAction func loadFrom(sender: AnyObject) {
		window.makeFirstResponder(nil)
		showOpenPanel(loadClipboardFromFile)
	}

	@IBAction func onClickLoadButton(sender: AnyObject) {
		window.makeFirstResponder(nil)
		if NSEvent.modifierFlags().contains(NSEventModifierFlags.ShiftKeyMask) {
			loadFrom(sender)
		} else {
			let path = settings.boolForKey(useSamePath) ? settings.stringForKey(exportPath) : settings.stringForKey(importPath)
			loadClipboardFromFile(path)
		}
	}

	func loadClipboardFromFile(filePath: String?) {
		let pasteboard = NSPasteboard.generalPasteboard()
		do {
			if let path = filePath {
				let xmlStr = try String(contentsOfFile: path, encoding: NSUTF8StringEncoding)
				if let ostype = detectOstypeFromXmlStr(xmlStr) {
					let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassOSType, ostype, kUTTypeData)?.takeRetainedValue()
					if let type = uti as String? {
						pasteboard.declareTypes([type], owner: nil)
						if pasteboard.setString(xmlStr as String, forType: type) {
							if let idx = types.indexOf(ostype) {
								showMsg(String(format: NSLocalizedString("copiedToClipboard", comment: "%s definition copied to the clipboard."), typeLabels[idx]))
							}
						} else {
							showMsg(NSLocalizedString("failedToSetClipboard", comment: "Failed to update the clipboard."))
						}
					}
				}
			}
		} catch {
			showMsg(NSLocalizedString("failedToReadFile", comment: "Failed to read the file."))
		}
	}

	func showSavePanel(useAltPath: Bool, function: (String!) -> Void) {
		let savePanel = NSSavePanel()
		var initPath: String! = nil
		if useAltPath {
			if let altPath = settings.stringForKey(lastAltPath) {
				initPath = altPath
			} else {
				initPath = defaultFilePath()
			}
		} else {
			if let expPath = settings.stringForKey(exportPath) {
				initPath = expPath
			} else {
				initPath = defaultFilePath()
			}
		}
		let initUrl = NSURL.fileURLWithPath(initPath, isDirectory: false)
		savePanel.directoryURL = initUrl.URLByDeletingLastPathComponent
		savePanel.nameFieldStringValue = initUrl.lastPathComponent ?? defaultFilename
		savePanel.beginWithCompletionHandler { (result: Int) -> Void in
			if result == NSFileHandlingPanelOKButton {
				if let path = savePanel.URL?.path {
					if useAltPath {
						self.settings.setValue(path, forKey: self.lastAltPath)
					}
					function(path)
				}
			}
		}
	}

	func showOpenPanel(function: (String!) -> Void) {
		let openPanel = NSOpenPanel()
		openPanel.allowsMultipleSelection = false
		openPanel.canChooseDirectories = false
		openPanel.canCreateDirectories = true
		openPanel.canChooseFiles = true
		openPanel.beginWithCompletionHandler { (result: Int) -> Void in
			if result == NSFileHandlingPanelOKButton {
				if let path = openPanel.URL?.path {
					function(path)
				}
			}
		}
	}

	func detectOstypeFromXmlStr(xmlStr: String!) -> String? {
		if !settings.boolForKey(autoDetect) {
			return types[typeArrayController.selectionIndex]
		}
		do {
			let xml = try NSXMLDocument(XMLString: xmlStr, options: NSXMLNodeOptionsNone)
			let rootElem = xml.rootElement()
			let snippetType = rootElem?.attributeForName("type")?.stringValue
			var idx: Int! = -1
			switch snippetType ?? "" {
			case "LayoutObjectList":
				idx = settings.boolForKey(readLayoutIn12Format) ? 5 : 4
			case "FMObjectList":
				let nextElem = rootElem?.nextNode?.name
				switch nextElem ?? "" {
				case "BaseTable":
					idx = 0
				case "Field":
					idx = 1
				case "Script":
					idx = 2
				case "Step":
					idx = 3
				case "CustomFunction":
					idx = 6
				default:
					showMsg(String(format: NSLocalizedString("unknownNode", comment: "Unknown node name"), (nextElem ?? "(nil)")))
				}
			default:
				showMsg(String(format: NSLocalizedString("unknownSnippetType", comment: "Unknown fmxmlsnippet type"), (snippetType ?? "(nil)")))
			}
			if (idx > -1) {
				typeArrayController.setSelectionIndex(idx)
				return types[idx]
			}
		} catch {
			showMsg(NSLocalizedString("invalidXmlFormat", comment: "Invalid XML format."))
		}
		return nil
	}

	func showMsg(msg: String?) {
		msgField.stringValue = msg ?? ""
	}

	func setupDefaults() {
		let defaultPath = defaultFilePath()
		let defaults: [String: AnyObject!] = [
			exportPath: defaultPath,
			openFileAfterExport: true,
			prettyPrintXml: true,
			importPath: defaultPath,
			useSamePath: true,
			contentSelection: 0,
			autoDetect: true,
			readLayoutIn12Format: true
		]
		settings.registerDefaults(defaults)
	}

	func defaultFilePath() -> String! {
		let documentsDir = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true)[0] as NSString
		return documentsDir.stringByAppendingPathComponent(defaultFilename)
	}
}

