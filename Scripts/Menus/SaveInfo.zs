// What a save is. The engine's comment only knows the shared "Level" map, and
// nothing outside a save can read inside one, so a manual save carries this in
// its title after SEPARATOR. Autosaves name themselves: those are looked up by
// their timestamp in g_autosaveinfo.
class SaveInfo : StaticEventHandler
{
	const SEPARATOR = "\x1F";
	const KEEPAUTOSAVES = 8; // Entries kept in g_autosaveinfo

	ui Map<String, String> known; // By file name
	String autosaveinfo;
	int autosaves;
	ui int autosaveswritten;

	static clearscope SaveInfo Get()
	{
		return SaveInfo(StaticEventHandler.Find("SaveInfo"));
	}

	// game|map|level tics|total tics
	static clearscope String Current()
	{
		MapHandler handler = MapHandler.Get();
		ParsedMap map = handler ? handler.curmap : null;

		String mapname = level.LevelName;
		if (map)
		{
			int len = 0;
			while (len < int(map.mapname.Length()) && map.mapname.ByteAt(len) >= 0x20) { len++; }
			mapname = ZScriptTools.Trim(map.mapname.Left(len));
		}
		mapname.Replace("|", "/");

		return String.Format("%s|%s|%i|%i", handler ? handler.gametitle : "", mapname, level.maptime, level.totaltime);
	}

	// Remembered as the engine makes the autosave, which names it with the time.
	// Only ui code can read the clock, so that's where this is written
	static void RecordAutosave()
	{
		let this = SaveInfo.Get();
		if (!this) { return; }

		this.autosaveinfo = Current();
		this.autosaves++;
	}

	override void UiTick()
	{
		if (autosaveswritten == autosaves) { return; }
		autosaveswritten = autosaves;

		CVar saved = CVar.GetCVar("g_autosaveinfo", players[consoleplayer]);
		if (!saved) { return; }

		Array<String> entries;
		saved.GetString().Split(entries, "^", TOK_SKIPEMPTY);
		entries.Push(SystemTime.Format("%Y-%m-%d %H:%M:%S", SystemTime.Now()) .. "|" .. autosaveinfo);
		while (entries.Size() > KEEPAUTOSAVES) { entries.Delete(0); }

		String value;
		for (int e = 0; e < entries.Size(); e++) { value = value .. (e ? "^" : "") .. entries[e]; }
		saved.SetString(value);
	}

	static ui String FindAutosave(String title)
	{
		if (title.Left(9) != "Autosave ") { return ""; }

		String stamp = title.Mid(9);
		int seconds = Seconds(stamp);

		CVar saved = CVar.GetCVar("g_autosaveinfo", players[consoleplayer]);
		if (!saved) { return ""; }

		Array<String> entries;
		saved.GetString().Split(entries, "^", TOK_SKIPEMPTY);
		for (int e = entries.Size() - 1; e >= 0; e--)
		{
			if (entries[e].Left(10) != stamp.Left(10) || abs(Seconds(entries[e]) - seconds) > 3) { continue; }

			return entries[e].Mid(entries[e].IndexOf("|") + 1);
		}

		return "";
	}

	// Of "YYYY-MM-DD HH:MM:SS"
	static clearscope int Seconds(String stamp)
	{
		return stamp.Mid(11, 2).ToInt() * 3600 + stamp.Mid(14, 2).ToInt() * 60 + stamp.Mid(17, 2).ToInt();
	}

	static clearscope String FormatTime(int tics)
	{
		int seconds = tics / GameTicRate;

		return String.Format("%02i:%02i:%02i", seconds / 3600, (seconds / 60) % 60, seconds % 60);
	}

	static clearscope String Describe(String info)
	{
		Array<String> parts;
		info.Split(parts, "|");
		if (parts.Size() < 4) { return ""; }

		String text = parts[1] .. "\n";
		if (parts[0].length()) { text = parts[0] .. "\n" .. text; }

		return text .. "Level time: " .. FormatTime(parts[2].ToInt()) .. "\nTotal time: " .. FormatTime(parts[3].ToInt());
	}
}

mixin class SaveListInfo
{
	int lastinfo;

	// Move each save's details out of its title, where the list would draw them
	void ReadSaveInfo()
	{
		let store = SaveInfo.Get();
		if (!store) { return; }

		for (int s = 0; s < manager.SavegameCount(); s++)
		{
			SaveGameNode node = manager.GetSavegame(s);
			if (!node || !node.Filename.length()) { continue; }

			int at = node.SaveTitle.IndexOf(SaveInfo.SEPARATOR);
			if (at >= 0)
			{
				store.known.Insert(node.Filename, node.SaveTitle.Mid(at + 1));
				node.SaveTitle = node.SaveTitle.Left(at);
			}
			else if (!store.known.CheckKey(node.Filename))
			{
				String info = SaveInfo.FindAutosave(node.SaveTitle);
				if (info.length()) { store.known.Insert(node.Filename, info); }
			}
		}

		lastinfo = -2;
	}

	void ShowSaveInfo()
	{
		let store = SaveInfo.Get();
		if (!store || !manager.SavegameCount()) { return; }

		// Until a row is picked the comment is the first one's
		int shown = max(Selected, 0);
		if (shown >= manager.SavegameCount()) { return; }

		SaveGameNode node = manager.GetSavegame(shown);
		if (!node) { return; }

		String info;
		if (!node.Filename.length()) { info = SaveInfo.Current(); }
		else if (store.known.CheckKey(node.Filename)) { info = store.known.Get(node.Filename); }

		// The menu puts the engine's comment back whenever the selection moves
		String text = SaveInfo.Describe(info);
		if (text.length()) { BrokenSaveComment = NewConsoleFont.BreakLines(text, int(commentWidth / FontScale)); }
	}
}
