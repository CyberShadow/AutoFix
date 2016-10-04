import std.conv;
import std.file;
import std.regex;
import std.stdio;
import std.string;
import std.ascii;

import ae.utils.json;

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

string process(string file, string id)
{
	auto summary = getJsonSummary();
	if (id !in summary)
		return null;
	string[] mods = summary[id];

	string[string][][string] result;

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

		string[string][] commands;

		void goTo(int line, int col=0)
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

		void ret(int offset)
		{
			commands ~= [
				"command" : "return",
				"offset" : offset.text,
			];
		}

		void addImport(int line, string prefix=null, string postfix=null)
		{
			goTo(line);
			//insertText(prefix ~ "import " ~ mod ~ " : " ~ id ~ ";\n" ~ postfix);
			insertText(prefix ~ "import " ~ mod ~ ";\n" ~ postfix);
		}

		if (lastImportLine >= 0)
		{
			auto importLine = "import " ~ mod;
			int n;
			for (n = firstImportLine; n <= lastImportLine; n++)
			{
				auto line = lines[n];
				if (line.startsWith(importLine) && line.length > importLine.length && !isAlphaNum(line[importLine.length]))
				{
					// Add to existing import.
					auto p = cast(int)line.indexOf(";");
					if (p < 0)
						continue;
					auto c = line.indexOf(":");
					bool haveColon = c>0 && c<p;
					goTo(n, p);
					if (haveColon)
						insertText(", " ~ id);
					else
						insertText(" : " ~ id);	
					ret(0);
					result["Import " ~ id ~ " from " ~ mod] = commands;
					continue moduleLoop;
				}
				else
				if (line > importLine)
					break; // assume import list is sorted alphabetically, stop here
			}

			// Existing import not found, insert one
			addImport(n);
			ret(1);
		}
		else
		if (moduleLine >= 0) // add first import, after "module" statement
		{
			addImport(moduleLine+1, "\n");
			ret(2);
		}
		else // add first import, at the top of the program
		{
			addImport(0, null, "\n");
			ret(2);
		}

		result["Import " ~ mod] = commands;
	}
	return result.toJson();
}
