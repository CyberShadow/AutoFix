import std.algorithm.mutation;
import std.conv;
import std.file;
import std.regex;
import std.stdio;
import std.string;
import std.ascii;

import ae.utils.json;
import ae.utils.meta : I;
import ae.utils.regex;
import ae.utils.text;

import djson;

//enum FN = `C:\Temp\colorout.json`;

void main()
{
	string[string][] entries;
	foreach (line; stdin.byLine)
		entries ~= line.chomp.jsonParse!(string[string]);

	bool dirty;
	foreach (ref entry; entries)
	{
		if ("id" in entry)
		{
			auto fix = process(entry["file"], entry["id"]);
			if (fix)
			{
				entry["fixes"] = fix;
				dirty = true;
			}
		}
	}

	foreach (entry; entries)
		writeln(entry.toJson);
}

struct Editor
{
	string[string][] commands;

	void goTo(size_t line, size_t col=0)
	{
		commands ~= [
			"command" : "goto",
			"line" : (line+1).text,
			"char" : (col+1).text,
		];
	}

	void insertText(string text)
	{
		commands ~= [
			"command" : "insert",
			"text" : text,
		];
	}

	void deleteText(size_t count)
	{
		commands ~= [
			"command" : "delete",
			"count" : count.text,
		];
	}

	void ret(int offset)
	{
		commands ~= [
			"command" : "return",
			"offset" : offset.text,
		];
	}

	void addImport(string mod, int line, string prefix=null, string postfix=null)
	{
		goTo(line);
		//insertText(prefix ~ "import " ~ mod ~ " : " ~ id ~ ";\n" ~ postfix);
		insertText(prefix ~ "import " ~ mod ~ ";\n" ~ postfix);
	}
}

string process(string file, string id)
{
	string origId = id;
	auto summary = getJsonSummary();
	string[string][][string] result;

	if (id !in summary)
	{
		auto knownIds = summary.keys;
		auto index = findBestMatch(knownIds, id, 0.3);
		if (index < 0)
			return null;
		id = knownIds[index];

		string[string][][] edits;

		auto re = regex(`\b` ~ escapeRE(origId) ~ `\b`);
		auto lines = file.readText().splitLines();
		foreach (int i, line; lines)
			foreach (c; matchAll(line, re))
			{
				Editor editor;
				editor.goTo(i, c.pre.length);
				editor.deleteText(origId.length);
				editor.insertText(id);
				edits ~= editor.commands;
			}
		edits.reverse();
		edits ~= { Editor ed; ed.ret(0); return ed.commands; }();
		result["Correct to " ~ id] = edits.join();
		return result.toJson();
	}
	string[] mods = summary[id];

moduleLoop:
	foreach (mod; mods)
	{
		auto modPackage = mod.indexOf(".") >= 0 ? mod.split(".")[0] : null;
		auto importLinePrefix = "import " ~ modPackage;

		int moduleLine=-1, firstImportLine=-1, lastImportLine=-1;
		bool inImport;

		auto lines = file.readText().splitLines();
		foreach (int i, line; lines)
		{
			enum BOM = "\uFEFF";
			if (line.startsWith(BOM))
				line = line[BOM.length..$];
			if (moduleLine<0 && line.startsWith("module "))
				moduleLine = i;
			else
			if (firstImportLine<0 && line.startsWith(importLinePrefix))
			{
				firstImportLine = lastImportLine = i;
				inImport = true;
			}
			else
			if (inImport && line.startsWith(importLinePrefix))
				lastImportLine = i;
			else
			if (inImport && line == "")
				inImport = false;
		}

		Editor editor;

		if (lastImportLine >= 0)
		{
			auto importLine = "import " ~ mod;
			int n;
			for (n = firstImportLine; n <= lastImportLine; n++)
			{
				auto line = lines[n];
				if (line.startsWith(importLine) && line.length > importLine.length && !line[importLine.length].I!(c => c.isAlphaNum() || c == '.'))
				{
					// Add to existing import.
					auto p = cast(int)line.indexOf(";");
					if (p < 0)
						continue;
					auto c = line.indexOf(":");
					bool haveColon = c>0 && c<p;
					editor.goTo(n, p);
					if (haveColon)
						editor.insertText(", " ~ id);
					else
						editor.insertText(" : " ~ id);	
					editor.ret(0);
					result["Import " ~ id ~ " from " ~ mod] = editor.commands;
					continue moduleLoop;
				}
				else
				if (line > importLine)
					break; // assume import list is sorted alphabetically, stop here
			}

			// Existing import not found, insert one
			editor.addImport(mod, n);
			editor.ret(1);
		}
		else
		if (moduleLine >= 0) // add first import, after "module" statement
		{
			editor.addImport(mod, moduleLine+1, "\n");
			editor.ret(2);
		}
		else // add first import, at the top of the program
		{
			editor.addImport(mod, 0, null, "\n");
			editor.ret(2);
		}

		result["Import " ~ mod] = editor.commands;
	}
	return result.toJson();
}
