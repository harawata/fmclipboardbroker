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

	var settings: UserDefaults!

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

	func applicationDidFinishLaunching(_ aNotification: Notification) {
		settings = UserDefaults.standard
		setupDefaults()
		typeArrayController.content = typeLabels
		typeArrayController.setSelectionIndex(settings.integer(forKey: contentSelection))
		showMsg(nil)
	}

	func applicationWillTerminate(_ aNotification: Notification) {
		settings.set(typeArrayController.selectionIndex, forKey: contentSelection)
	}

	@IBAction func onClickChooseImportPathFile(_ sender: AnyObject) {
		showOpenPanel({ (path: String!) -> Void in
			self.settings.setValue(path, forKey: self.importPath)
		})
	}

	@IBAction func onClickChooseExportFile(_ sender: AnyObject) {
		showSavePanel(false, function: { (path: String!) -> Void in
			self.settings.setValue(path, forKey: self.exportPath)
		})
	}

	@IBAction func saveAs(_ sender: AnyObject) {
		window.makeFirstResponder(nil)
		showSavePanel(true, function: saveClipboardToFile)
	}

	@IBAction func onClickSaveButton(_ sender: AnyObject) {
		window.makeFirstResponder(nil)
		if NSEvent.modifierFlags().contains(NSEventModifierFlags.shift) {
			saveAs(sender)
		} else {
			saveClipboardToFile(settings.string(forKey: exportPath))
		}
	}

	func saveClipboardToFile(_ filePath: String?) {
		let pasteboard = NSPasteboard.general()
		if let uti = pasteboard.pasteboardItems?[0].types[0] {
			if let ostype = UTTypeCopyPreferredTagWithClass(uti as CFString, kUTTagClassOSType)?.takeRetainedValue() as String? {
				if let typeIdx = types.index(of: ostype) {
					typeArrayController.setSelectionIndex(typeIdx)
					let xmlStr = pasteboard.string(forType: uti)
					if let path = filePath {
						var saved = false
						if settings.bool(forKey: prettyPrintXml) {
							saved = savePrettyXml(path, xmlStr: xmlStr)
						} else {
							saved = saveRawXml(path, xmlStr: xmlStr)
						}
						if saved && settings.bool(forKey: openFileAfterExport) {
							NSWorkspace.shared().openFile(path)
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

	func saveRawXml(_ path: String!, xmlStr: String?) -> Bool {
		do {
			try xmlStr?.write(toFile: path, atomically: true, encoding: String.Encoding.utf8)
			return true
		} catch {
			showMsg(NSLocalizedString("failedToExportXmlStr", comment: "Failed to write XML string to the file."))
		}
		return false
	}

	func savePrettyXml(_ path: String!, xmlStr: String?) -> Bool {
		if let str = xmlStr {
			do {
				let xml = try XMLDocument(xmlString: str, options: Int(XMLNode.Options.nodePrettyPrint.rawValue))
				let xmlData = xml.xmlData(withOptions: Int(XMLNode.Options.nodePrettyPrint.rawValue))
				return ((try? xmlData.write(to: URL(fileURLWithPath: path), options: [.atomic])) != nil)
			} catch {
				showMsg(NSLocalizedString("parseErrorInLoadedXml", comment: "Failed to parse XML string copied from FM."))
			}
		}
		return false
	}

	@IBAction func loadFrom(_ sender: AnyObject) {
		window.makeFirstResponder(nil)
		showOpenPanel(loadClipboardFromFile)
	}

	@IBAction func onClickLoadButton(_ sender: AnyObject) {
		window.makeFirstResponder(nil)
		if NSEvent.modifierFlags().contains(NSEventModifierFlags.shift) {
			loadFrom(sender)
		} else {
			let path = settings.bool(forKey: useSamePath) ? settings.string(forKey: exportPath) : settings.string(forKey: importPath)
			loadClipboardFromFile(path)
		}
	}

	func loadClipboardFromFile(_ filePath: String?) {
		let pasteboard = NSPasteboard.general()
		do {
			if let path = filePath {
				let xmlStr = try String(contentsOfFile: path, encoding: String.Encoding.utf8)
				if let ostype = detectOstypeFromXmlStr(xmlStr) {
					let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassOSType, ostype as CFString, kUTTypeData)?.takeRetainedValue()
					if let type = uti as String? {
						pasteboard.declareTypes([type], owner: nil)
						if pasteboard.setString(xmlStr as String, forType: type) {
							if let idx = types.index(of: ostype) {
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

	func showSavePanel(_ useAltPath: Bool, function: @escaping (String!) -> Void) {
		let savePanel = NSSavePanel()
		var initPath: String! = nil
		if useAltPath {
			if let altPath = settings.string(forKey: lastAltPath) {
				initPath = altPath
			} else {
				initPath = defaultFilePath()
			}
		} else {
			if let expPath = settings.string(forKey: exportPath) {
				initPath = expPath
			} else {
				initPath = defaultFilePath()
			}
		}
		let initUrl = URL(fileURLWithPath: initPath, isDirectory: false)
		savePanel.directoryURL = initUrl.deletingLastPathComponent()
		savePanel.nameFieldStringValue = initUrl.lastPathComponent == "" ? defaultFilename : initUrl.lastPathComponent
		savePanel.begin { (result: Int) -> Void in
			if result == NSFileHandlingPanelOKButton {
				if let path = savePanel.url?.path {
					if useAltPath {
						self.settings.setValue(path, forKey: self.lastAltPath)
					}
					function(path)
				}
			}
		}
	}

	func showOpenPanel(_ function: @escaping (String!) -> Void) {
		let openPanel = NSOpenPanel()
		openPanel.allowsMultipleSelection = false
		openPanel.canChooseDirectories = false
		openPanel.canCreateDirectories = true
		openPanel.canChooseFiles = true
		openPanel.begin { (result: Int) -> Void in
			if result == NSFileHandlingPanelOKButton {
				if let path = openPanel.url?.path {
					function(path)
				}
			}
		}
	}

	func detectOstypeFromXmlStr(_ xmlStr: String!) -> String? {
		if !settings.bool(forKey: autoDetect) {
			return types[typeArrayController.selectionIndex]
		}
		do {
			let xml = try XMLDocument(xmlString: xmlStr, options: Int(XMLNode.Options.nodePrettyPrint.rawValue))
			let rootElem = xml.rootElement()
			let snippetType = rootElem?.attribute(forName: "type")?.stringValue
			var idx: Int! = -1
			switch snippetType ?? "" {
			case "LayoutObjectList":
				idx = settings.bool(forKey: readLayoutIn12Format) ? 5 : 4
			case "FMObjectList":
				let nextElem = rootElem?.next?.name
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

	func showMsg(_ msg: String?) {
		msgField.stringValue = msg ?? ""
	}

	func setupDefaults() {
		let defaultPath = defaultFilePath()
		let defaults: [String: Any] = [
			exportPath: defaultPath ?? "",
			openFileAfterExport: true,
			prettyPrintXml: true,
			importPath: defaultPath ?? "",
			useSamePath: true,
			contentSelection: 0,
			autoDetect: true,
			readLayoutIn12Format: true
		]
		settings.register(defaults: defaults)
	}

	func defaultFilePath() -> String! {
		let documentsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0] as NSString
		return documentsDir.appendingPathComponent(defaultFilename)
	}
}

